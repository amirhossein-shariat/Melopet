package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

type catalogItem struct {
	Id         string  `json:"id"`
	Name       string  `json:"name"`
	Code       string  `json:"code"`
	Category   string  `json:"category"`
	SampleType string  `json:"sample_type"`
	Hours      float64 `json:"turnaround_hours"`
	Price      float64 `json:"price"`
	Desc       string  `json:"description"`
}

// catalogFor returns the active tests with their price.
func catalogFor(app core.App) ([]catalogItem, error) {
	records, err := app.FindRecordsByFilter("tests", "active = true", "sort,name", 0, 0)
	if err != nil {
		return nil, err
	}
	out := make([]catalogItem, 0, len(records))
	for _, r := range records {
		out = append(out, catalogItem{
			Id:         r.Id,
			Name:       r.GetString("name"),
			Code:       r.GetString("code"),
			Category:   r.GetString("category"),
			SampleType: r.GetString("sample_type"),
			Hours:      r.GetFloat("turnaround_hours"),
			Price:      r.GetFloat("price"),
			Desc:       r.GetString("description"),
		})
	}
	return out, nil
}

type orderRequest struct {
	Clinic        string   `json:"clinic"` // admins only: create on behalf of a clinic
	Tests         []string `json:"tests"`
	PetName       string   `json:"pet_name"`
	Species       string   `json:"species"`
	Breed         string   `json:"breed"`
	Age           string   `json:"age"`
	Sex           string   `json:"sex"`
	Weight        float64  `json:"weight"`
	OwnerName     string   `json:"owner_name"`
	FileNo        string   `json:"file_no"`
	SampleType    string   `json:"sample_type"`
	SampleCount   int      `json:"sample_count"`
	PromoCode     string   `json:"promo_code"`
	Delivery      string   `json:"delivery"`       // "standard" (free, next round) | "urgent" (quoted fee)
	DeliveryQuote string   `json:"delivery_quote"` // token from /delivery/quote, required for urgent (clinics)
	Fasting       bool     `json:"fasting"`
	PickupAddress string   `json:"pickup_address"`
	PickupTime    string   `json:"pickup_time"`
	ClinicalNotes string   `json:"clinical_notes"` // case history (text)
	VoiceSeconds  float64  `json:"history_voice_seconds"`
	Lat           float64  `json:"lat"`
	Lon           float64  `json:"lon"`
}

func registerRoutes(se *core.ServeEvent) {
	g := se.Router.Group("/api/melopet")
	g.Bind(apis.RequireAuth("users"))
	registerCourierRoutes(g)
	registerPromoRoutes(g)

	// The active tests with their prices.
	g.GET("/catalog", func(e *core.RequestEvent) error {
		items, err := catalogFor(e.App)
		if err != nil {
			return e.InternalServerError("", err)
		}
		return e.JSON(http.StatusOK, items)
	})

	// Courier request / new order. Prices are computed on the server.
	// Accepts JSON, or multipart with a "data" JSON field + optional "history_voice" file.
	g.POST("/orders", func(e *core.RequestEvent) error {
		var body orderRequest
		if strings.HasPrefix(e.Request.Header.Get("Content-Type"), "multipart/") {
			if err := e.Request.ParseMultipartForm(32 << 20); err != nil {
				return e.BadRequestError("درخواست نامعتبر است", err)
			}
			raw := e.Request.FormValue("data")
			if raw == "" {
				raw = e.Request.FormValue("@jsonPayload") // official SDKs
			}
			if err := json.Unmarshal([]byte(raw), &body); err != nil {
				return e.BadRequestError("درخواست نامعتبر است", err)
			}
		} else if err := e.BindBody(&body); err != nil {
			return e.BadRequestError("درخواست نامعتبر است", err)
		}
		voice, _ := e.FindUploadedFiles("history_voice")
		if strings.TrimSpace(body.ClinicalNotes) == "" && len(voice) == 0 {
			return e.BadRequestError("تاریخچه کیس (متن یا ویس) الزامی است", nil)
		}
		if strings.TrimSpace(body.PetName) == "" || strings.TrimSpace(body.OwnerName) == "" || body.Species == "" {
			return e.BadRequestError("نام حیوان، نام صاحب و نوع حیوان الزامی است", nil)
		}

		clinic := e.Auth
		if isAdmin(e.Auth) {
			if body.Clinic == "" {
				return e.BadRequestError("کلینیک را انتخاب کنید", nil)
			}
			c, err := e.App.FindRecordById("users", body.Clinic)
			if err != nil {
				return e.NotFoundError("کلینیک یافت نشد", err)
			}
			clinic = c
		} else if !clinic.GetBool("approved") {
			return e.ForbiddenError("حساب شما هنوز توسط آزمایشگاه تایید نشده است", nil)
		}

		catalog, err := catalogFor(e.App)
		if err != nil {
			return e.InternalServerError("", err)
		}
		byId := map[string]catalogItem{}
		for _, c := range catalog {
			byId[c.Id] = c
		}

		items := []map[string]any{}
		total := 0.0
		for _, id := range body.Tests {
			c, ok := byId[id]
			if !ok {
				return e.BadRequestError("آزمایش انتخاب‌شده معتبر نیست", nil)
			}
			items = append(items, map[string]any{
				"test": c.Id, "name": c.Name, "code": c.Code, "category": c.Category, "price": c.Price,
			})
			total += c.Price
		}

		// ---- delivery: free (next round) or urgent (quoted fee added to the total) ----
		delivery := body.Delivery
		if delivery == "" {
			delivery = "standard"
		}
		if delivery != "standard" && delivery != "urgent" {
			return e.BadRequestError("روش ارسال نامعتبر است", nil)
		}
		pickup, hasPickup := pickupPoint(clinic, body.Lat, body.Lon)
		var dq quote
		if delivery == "urgent" {
			if !hasPickup {
				return e.BadRequestError("برای پیک فوری، موقعیت مکانی مرکز را ثبت کنید", nil)
			}
			if t, ok := verifyQuote(body.DeliveryQuote, clinic.Id, pickup); ok {
				dq = t
			} else if isAdmin(e.Auth) {
				// the lab registering on behalf of a clinic: price it right now
				lab, err := labLocation(e.App)
				if err != nil {
					return e.BadRequestError("لوکیشن آزمایشگاه در تنظیمات ثبت نشده است", err)
				}
				qr, err := quoter()
				if err != nil {
					return e.InternalServerError("", err)
				}
				if dq, err = qr.Quote(e.App, pickup, lab); err != nil {
					return e.BadRequestError("قیمت پیک فوری دریافت نشد", err)
				}
			} else {
				return e.BadRequestError("قیمت پیک فوری منقضی شده است؛ دوباره قیمت را دریافت کنید", nil)
			}
			total += dq.Fee
		}

		// ---- discount code: a percentage of the tests (not of the courier fee) ----
		var promo promoResult
		if strings.TrimSpace(body.PromoCode) != "" {
			testsTotal := total - dq.Fee
			p, err := applyPromo(e.App, body.PromoCode, testsTotal)
			if err != nil {
				return e.BadRequestError(err.Error(), nil)
			}
			promo = p
		}

		col, err := e.App.FindCollectionByNameOrId("orders")
		if err != nil {
			return e.InternalServerError("", err)
		}
		r := core.NewRecord(col)
		r.Set("clinic", clinic.Id)
		r.Set("status", "requested")
		r.Set("pet_name", body.PetName)
		r.Set("species", body.Species)
		r.Set("breed", body.Breed)
		r.Set("age", body.Age)
		r.Set("sex", body.Sex)
		r.Set("weight", body.Weight)
		r.Set("owner_name", body.OwnerName)
		r.Set("file_no", body.FileNo)
		r.Set("sample_type", body.SampleType)
		r.Set("sample_count", body.SampleCount)
		r.Set("urgent", delivery == "urgent")
		r.Set("delivery_type", delivery)
		r.Set("delivery_fee", dq.Fee)
		r.Set("delivery_source", dq.Source)
		r.Set("delivery_distance_km", dq.DistanceKm)
		r.Set("fasting", body.Fasting)
		addr := strings.TrimSpace(body.PickupAddress)
		if addr == "" {
			addr = clinic.GetString("address")
		}
		r.Set("pickup_address", addr)
		pickupTime := body.PickupTime
		if pickupTime == "" {
			if delivery == "urgent" {
				pickupTime = "فوری"
			} else {
				pickupTime = fmt.Sprintf("تا %d ساعت آینده", pickupIntervalHours(e.App))
			}
		}
		r.Set("pickup_time", pickupTime)
		r.Set("clinical_notes", body.ClinicalNotes)
		if len(voice) > 0 {
			r.Set("history_voice", voice[0])
			r.Set("history_voice_seconds", body.VoiceSeconds)
		}
		// pickup location: explicit pin, else the clinic's saved location
		if body.Lat != 0 && body.Lon != 0 {
			r.Set("location", types.GeoPoint{Lon: body.Lon, Lat: body.Lat})
		} else {
			r.Set("location", clinic.Get("location"))
		}
		r.Set("items", items)
		r.Set("total", total)
		r.Set("discount", promo.Discount)
		r.Set("discount_code", promo.Code)
		if err := e.App.Save(r); err != nil {
			return e.BadRequestError("ثبت سفارش ناموفق بود", err)
		}
		return e.JSON(http.StatusOK, r)
	})

	// A clinic may cancel its own request until the courier is dispatched.
	g.POST("/orders/{id}/cancel", func(e *core.RequestEvent) error {
		r, err := e.App.FindRecordById("orders", e.Request.PathValue("id"))
		if err != nil {
			return e.NotFoundError("", err)
		}
		if !isAdmin(e.Auth) {
			if r.GetString("clinic") != e.Auth.Id {
				return e.ForbiddenError("", nil)
			}
			if r.GetString("status") != "requested" {
				return e.BadRequestError("پیک اعزام شده و امکان لغو از طریق اپ وجود ندارد؛ لطفا در چت پیام دهید.", nil)
			}
		}
		r.Set("status", "cancelled")
		if err := e.App.Save(r); err != nil {
			return e.BadRequestError("", err)
		}
		return e.JSON(http.StatusOK, r)
	})

	// Get-or-create the chat with a clinic (clinic: own chat; admin: ?clinic=ID).
	g.GET("/chat/conversation", func(e *core.RequestEvent) error {
		clinicId := e.Auth.Id
		if isAdmin(e.Auth) {
			clinicId = e.Request.URL.Query().Get("clinic")
			if clinicId == "" {
				return e.BadRequestError("clinic is required", nil)
			}
		}
		conv, err := e.App.FindFirstRecordByFilter("conversations", "clinic = {:c}", dbx.Params{"c": clinicId})
		if err != nil {
			col, err := e.App.FindCollectionByNameOrId("conversations")
			if err != nil {
				return e.InternalServerError("", err)
			}
			conv = core.NewRecord(col)
			conv.Set("clinic", clinicId)
			if err := e.App.Save(conv); err != nil {
				return e.BadRequestError("", err)
			}
		}
		return e.JSON(http.StatusOK, conv)
	})

	// Mark a conversation as read by the caller's side.
	g.POST("/chat/{id}/read", func(e *core.RequestEvent) error {
		conv, err := e.App.FindRecordById("conversations", e.Request.PathValue("id"))
		if err != nil {
			return e.NotFoundError("", err)
		}
		if isAdmin(e.Auth) {
			conv.Set("admin_read_at", types.NowDateTime())
			conv.Set("unread_admin", 0)
		} else if conv.GetString("clinic") == e.Auth.Id {
			conv.Set("clinic_read_at", types.NowDateTime())
			conv.Set("unread_clinic", 0)
		} else {
			return e.ForbiddenError("", nil)
		}
		if err := e.App.Save(conv); err != nil {
			return e.BadRequestError("", err)
		}
		return e.JSON(http.StatusOK, conv)
	})

	// Admin dashboard numbers.
	g.GET("/admin/stats", func(e *core.RequestEvent) error {
		if !isAdmin(e.Auth) {
			return e.ForbiddenError("", nil)
		}
		count := func(col, filter string) int64 {
			n, _ := e.App.CountRecords(col, dbx.NewExp(filter))
			return n
		}
		var revenue struct {
			Sum float64 `db:"s"`
		}
		_ = e.App.DB().NewQuery("SELECT COALESCE(SUM(total - discount),0) AS s FROM orders WHERE status != 'cancelled'").One(&revenue)
		var unread struct {
			Sum int64 `db:"s"`
		}
		_ = e.App.DB().NewQuery("SELECT COALESCE(SUM(unread_admin),0) AS s FROM conversations").One(&unread)

		return e.JSON(http.StatusOK, map[string]any{
			"orders_open":     count("orders", "status NOT IN ('ready','cancelled')"),
			"orders_new":      count("orders", "status = 'requested'"),
			"orders_ready":    count("orders", "status = 'ready'"),
			"orders_total":    count("orders", "1=1"),
			"clinics":         count("users", "role = 'clinic'"),
			"clinics_pending": count("users", "role = 'clinic' AND approved = FALSE"),
			"revenue":         revenue.Sum,
			"unread_chats":    unread.Sum,
		})
	})

}
