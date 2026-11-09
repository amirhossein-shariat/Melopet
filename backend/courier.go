package main

import (
	"errors"
	"math"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/pocketbase/pocketbase/tools/security"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Delivery choice at checkout (like an online shop):
//
//	standard — free. The lab sends a courier round every `pickup_interval_hours` (4 h), so the
//	           sample is collected within that window.
//	urgent   — a dedicated courier right now. The fee is quoted for the exact pick-up point →
//	           lab route and ADDED to the order total.
//
// Quotes come from a courierQuoter. The built-in one is a distance-based ESTIMATE whose
// parameters (base fee, per-km, minimum) are editable in the lab settings. When the lab has an
// API account with a courier service (Snapp Box, Alopeyk, …) a quoter for it replaces the
// estimate: implement courierQuoter and select it with MELOPET_COURIER_PROVIDER.

const (
	sourceEstimate = "estimate"
	quoteTTL       = 15 * time.Minute
	quoteType      = "delivery-quote"
)

type quote struct {
	Fee        float64 `json:"fee"`
	Source     string  `json:"source"` // estimate | snapp
	DistanceKm float64 `json:"distance_km"`
}

type courierQuoter interface {
	Quote(app core.App, from, to types.GeoPoint) (quote, error)
}

var errNoLabLocation = errors.New("lab location is not set")

// quoter returns the configured provider. Only the estimate exists until the lab connects a
// courier API account; an unknown provider name is a configuration error, not a silent fallback.
func quoter() (courierQuoter, error) {
	switch strings.ToLower(os.Getenv("MELOPET_COURIER_PROVIDER")) {
	case "", sourceEstimate:
		return estimateQuoter{}, nil
	}
	return nil, errors.New("unknown MELOPET_COURIER_PROVIDER")
}

type estimateQuoter struct{}

func (estimateQuoter) Quote(app core.App, from, to types.GeoPoint) (quote, error) {
	s := labSettings(app)
	km := haversineKm(from, to)
	// road distance is longer than the straight line
	km = math.Round(km*1.3*10) / 10
	fee := s.GetFloat("urgent_base_fee") + km*s.GetFloat("urgent_per_km")
	if min := s.GetFloat("urgent_min_fee"); fee < min {
		fee = min
	}
	// round to the nearest 1,000 Toman
	fee = math.Round(fee/1000) * 1000
	return quote{Fee: fee, Source: sourceEstimate, DistanceKm: km}, nil
}

func labSettings(app core.App) *core.Record {
	list, err := app.FindRecordsByFilter("settings", "1=1", "", 1, 0)
	if err != nil || len(list) == 0 {
		col, _ := app.FindCollectionByNameOrId("settings")
		return core.NewRecord(col)
	}
	return list[0]
}

func labLocation(app core.App) (types.GeoPoint, error) {
	gp, ok := labSettings(app).Get("location").(types.GeoPoint)
	if !ok || (gp.Lat == 0 && gp.Lon == 0) {
		return types.GeoPoint{}, errNoLabLocation
	}
	return gp, nil
}

func pickupIntervalHours(app core.App) int {
	if h := int(labSettings(app).GetFloat("pickup_interval_hours")); h > 0 {
		return h
	}
	return 4
}

func haversineKm(a, b types.GeoPoint) float64 {
	const r = 6371.0
	rad := func(d float64) float64 { return d * math.Pi / 180 }
	dLat, dLon := rad(b.Lat-a.Lat), rad(b.Lon-a.Lon)
	h := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(rad(a.Lat))*math.Cos(rad(b.Lat))*math.Sin(dLon/2)*math.Sin(dLon/2)
	return 2 * r * math.Asin(math.Sqrt(h))
}

// pickupPoint: the explicit pin of the request, else the clinic's saved location.
func pickupPoint(clinic *core.Record, lat, lon float64) (types.GeoPoint, bool) {
	if lat != 0 && lon != 0 {
		return types.GeoPoint{Lat: lat, Lon: lon}, true
	}
	if gp, ok := clinic.Get("location").(types.GeoPoint); ok && (gp.Lat != 0 || gp.Lon != 0) {
		return gp, true
	}
	return types.GeoPoint{}, false
}

// signQuote binds a quoted fee to the clinic and the exact pick-up point, for a short time,
// so the price the clinic saw is the price that is charged and nobody can send their own fee.
func signQuote(clinicID string, p types.GeoPoint, q quote) (string, error) {
	return security.NewJWT(jwt.MapClaims{
		"typ": quoteType, "clinic": clinicID, "lat": round5(p.Lat), "lon": round5(p.Lon),
		"fee": q.Fee, "src": q.Source, "km": q.DistanceKm,
	}, proofKey, quoteTTL)
}

func round5(v float64) float64 { return math.Round(v*1e5) / 1e5 }

func verifyQuote(token, clinicID string, p types.GeoPoint) (quote, bool) {
	if token == "" {
		return quote{}, false
	}
	c, err := security.ParseJWT(token, proofKey)
	if err != nil || c["typ"] != quoteType || c["clinic"] != clinicID {
		return quote{}, false
	}
	lat, _ := c["lat"].(float64)
	lon, _ := c["lon"].(float64)
	if lat != round5(p.Lat) || lon != round5(p.Lon) {
		return quote{}, false
	}
	fee, _ := c["fee"].(float64)
	km, _ := c["km"].(float64)
	src, _ := c["src"].(string)
	return quote{Fee: fee, Source: src, DistanceKm: km}, true
}

type quoteRequest struct {
	Clinic string  `json:"clinic"` // admins only
	Lat    float64 `json:"lat"`
	Lon    float64 `json:"lon"`
}

func registerCourierRoutes(g *router.RouterGroup[*core.RequestEvent]) {
	// What each delivery option costs for this pick-up point, right now.
	g.POST("/delivery/quote", func(e *core.RequestEvent) error {
		var body quoteRequest
		if err := e.BindBody(&body); err != nil {
			return e.BadRequestError("درخواست نامعتبر است", err)
		}
		clinic := e.Auth
		if isAdmin(e.Auth) {
			c, err := e.App.FindRecordById("users", body.Clinic)
			if err != nil {
				return e.BadRequestError("کلینیک را انتخاب کنید", err)
			}
			clinic = c
		}
		out := map[string]any{
			"standard": map[string]any{"fee": 0, "window_hours": pickupIntervalHours(e.App)},
		}
		from, ok := pickupPoint(clinic, body.Lat, body.Lon)
		lab, labErr := labLocation(e.App)
		q, qErr := quoter()
		if !ok || labErr != nil || qErr != nil {
			// the free option still works; urgent just can't be priced
			reason := "location"
			if labErr != nil {
				reason = "lab_location"
			} else if qErr != nil {
				reason = "provider"
			}
			out["urgent"] = map[string]any{"available": false, "reason": reason}
			return e.JSON(http.StatusOK, out)
		}
		res, err := q.Quote(e.App, from, lab)
		if err != nil {
			out["urgent"] = map[string]any{"available": false, "reason": "provider"}
			return e.JSON(http.StatusOK, out)
		}
		token, err := signQuote(clinic.Id, from, res)
		if err != nil {
			return e.InternalServerError("", err)
		}
		out["urgent"] = map[string]any{
			"available": true, "fee": res.Fee, "source": res.Source, "distance_km": res.DistanceKm,
			"quote": token, "valid_minutes": int(quoteTTL.Minutes()),
		}
		return e.JSON(http.StatusOK, out)
	})
}
