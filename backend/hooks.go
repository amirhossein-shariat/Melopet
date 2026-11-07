package main

import (
	"fmt"
	"time"
	"unicode/utf8"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

var statusTitles = map[string]string{
	"requested":        "درخواست پیک ثبت شد",
	"courier_assigned": "پیک برای شما اعزام شد",
	"picked_up":        "نمونه توسط پیک تحویل گرفته شد",
	"received":         "نمونه در آزمایشگاه دریافت شد",
	"in_progress":      "آزمایش در حال انجام است",
	"ready":            "جواب آزمایش آماده شد",
	"cancelled":        "درخواست لغو شد",
}

// notify creates a notification row. user may be "" for broadcasts
// (audience "clinics" or "admins").
func notify(app core.App, user, audience, typ, title, body, ref string) {
	col, err := app.FindCollectionByNameOrId("notifications")
	if err != nil {
		app.Logger().Error("notify: collection", "error", err)
		return
	}
	n := core.NewRecord(col)
	n.Set("user", user)
	n.Set("audience", audience)
	n.Set("type", typ)
	n.Set("title", title)
	n.Set("body", body)
	n.Set("ref", ref)
	if err := app.Save(n); err != nil {
		app.Logger().Error("notify: save", "error", err)
	}
}

func appendHistory(r *core.Record, status, note string) {
	var history []map[string]any
	_ = r.UnmarshalJSONField("history", &history)
	history = append(history, map[string]any{
		"status": status,
		"at":     time.Now().UTC().Format(time.RFC3339),
		"note":   note,
	})
	r.Set("history", history)
}

func truncate(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	return string([]rune(s)[:n]) + "…"
}

func registerHooks(app core.App) {
	// ---- users: new sign-ups are always clinics ---------------------------
	app.OnRecordCreateRequest("users").BindFunc(func(e *core.RecordRequestEvent) error {
		if !e.HasSuperuserAuth() && !isAdmin(e.Auth) {
			// a clinic account can only be created for a mobile number verified by SMS code
			info, err := e.RequestInfo()
			if err != nil {
				return err
			}
			proof, _ := info.Body["otp_proof"].(string)
			if !verifyProof(proof, e.Record.GetString("mobile")) {
				return e.BadRequestError("ابتدا شماره موبایل را با کد پیامکی تایید کنید", nil)
			}
			e.Record.Set("role", "clinic")
			e.Record.Set("approved", autoApprove())
			e.Record.Set("username", "") // admin IDs are assigned by the lab only
		}
		if e.Record.GetString("role") == "" {
			e.Record.Set("role", "clinic")
		}
		return e.Next()
	})

	app.OnRecordAfterCreateSuccess("users").BindFunc(func(e *core.RecordEvent) error {
		if e.Record.GetString("role") == "clinic" {
			// every clinic starts at bronze; admins upgrade privately
			if col, err := e.App.FindCollectionByNameOrId("clinic_tiers"); err == nil {
				t := core.NewRecord(col)
				t.Set("clinic", e.Record.Id)
				t.Set("tier", "bronze")
				_ = e.App.Save(t)
			}
			name := e.Record.GetString("clinic_name")
			if name == "" {
				name = e.Record.GetString("mobile")
			}
			notify(e.App, "", "admins", "general", "همکار جدید ثبت‌نام کرد", name, e.Record.Id)
		}
		return e.Next()
	})

	app.OnRecordUpdate("users").BindFunc(func(e *core.RecordEvent) error {
		wasApproved := e.Record.Original().GetBool("approved")
		if err := e.Next(); err != nil {
			return err
		}
		if !wasApproved && e.Record.GetBool("approved") && e.Record.GetString("role") == "clinic" {
			notify(e.App, e.Record.Id, "user", "general", "حساب شما تایید شد",
				"اکنون می‌توانید درخواست پیک ثبت کنید.", "")
		}
		return nil
	})

	// ---- payments: clinics file them as pending, the lab confirms --------
	app.OnRecordCreateRequest("payments").BindFunc(func(e *core.RecordRequestEvent) error {
		if e.HasSuperuserAuth() || isAdmin(e.Auth) {
			if e.Record.GetString("status") == "" {
				e.Record.Set("status", "confirmed")
			}
		} else {
			e.Record.Set("status", "pending")
			e.Record.Set("clinic", e.Auth.Id)
		}
		if e.Record.GetString("paid_at") == "" {
			e.Record.Set("paid_at", time.Now().UTC().Format("2006-01-02 15:04:05.000Z"))
		}
		return e.Next()
	})
	app.OnRecordAfterCreateSuccess("payments").BindFunc(func(e *core.RecordEvent) error {
		amount := fmt.Sprintf("%.0f", e.Record.GetFloat("amount"))
		clinic, _ := e.App.FindRecordById("users", e.Record.GetString("clinic"))
		name := ""
		if clinic != nil {
			name = clinic.GetString("clinic_name")
		}
		if e.Record.GetString("status") == "pending" {
			notify(e.App, "", "admins", "general", "پرداخت جدید ثبت شد", name+" — "+amount+" تومان، در انتظار تایید", e.Record.Id)
		} else if e.Record.GetString("status") == "confirmed" {
			notify(e.App, e.Record.GetString("clinic"), "user", "general", "پرداخت شما ثبت شد", amount+" تومان به حساب شما افزوده شد.", e.Record.Id)
		}
		return e.Next()
	})
	app.OnRecordUpdate("payments").BindFunc(func(e *core.RecordEvent) error {
		before := e.Record.Original().GetString("status")
		if err := e.Next(); err != nil {
			return err
		}
		now := e.Record.GetString("status")
		if before == "pending" && now != before {
			amount := fmt.Sprintf("%.0f", e.Record.GetFloat("amount"))
			if now == "confirmed" {
				notify(e.App, e.Record.GetString("clinic"), "user", "general", "پرداخت شما تایید شد", amount+" تومان از بدهی شما کسر شد.", e.Record.Id)
			} else if now == "rejected" {
				notify(e.App, e.Record.GetString("clinic"), "user", "general", "پرداخت شما تایید نشد", "لطفا با آزمایشگاه تماس بگیرید.", e.Record.Id)
			}
		}
		return nil
	})

	// ---- orders: status history + notifications ---------------------------
	app.OnRecordCreate("orders").BindFunc(func(e *core.RecordEvent) error {
		if e.Record.GetString("status") == "" {
			e.Record.Set("status", "requested")
		}
		if e.Record.GetString("code") == "" {
			total, _ := e.App.CountRecords("orders")
			e.Record.Set("code", fmt.Sprintf("MP-%d", 10001+total))
		}
		appendHistory(e.Record, e.Record.GetString("status"), "")
		if err := e.Next(); err != nil {
			return err
		}
		clinic, _ := e.App.FindRecordById("users", e.Record.GetString("clinic"))
		name := ""
		if clinic != nil {
			name = clinic.GetString("clinic_name")
		}
		urgent := ""
		if e.Record.GetBool("urgent") {
			urgent = " (فوری)"
		}
		species := map[string]string{"dog": "سگ", "cat": "گربه", "bird": "پرنده", "rabbit": "خرگوش", "rodent": "جونده",
			"reptile": "خزنده", "horse": "اسب", "ruminant": "نشخوارکننده", "other": "سایر"}[e.Record.GetString("species")]
		var items []map[string]any
		_ = e.Record.UnmarshalJSONField("items", &items)
		body := fmt.Sprintf("%s | %s (%s) | %d آزمایش | %s", name, e.Record.GetString("pet_name"), species, len(items), e.Record.GetString("code"))
		notify(e.App, "", "admins", "order", "درخواست پیک جدید"+urgent, body, e.Record.Id)
		return nil
	})

	app.OnRecordUpdate("orders").BindFunc(func(e *core.RecordEvent) error {
		oldStatus := e.Record.Original().GetString("status")
		newStatus := e.Record.GetString("status")
		changed := oldStatus != newStatus
		if changed {
			appendHistory(e.Record, newStatus, "")
			if newStatus == "ready" && e.Record.GetDateTime("ready_at").IsZero() {
				e.Record.Set("ready_at", types.NowDateTime())
			}
		}
		if err := e.Next(); err != nil {
			return err
		}
		if changed {
			body := fmt.Sprintf("سفارش %s", e.Record.GetString("code"))
			if pet := e.Record.GetString("pet_name"); pet != "" {
				body += " — " + pet
			}
			typ := "order"
			if newStatus == "ready" {
				typ = "result"
				body += " | برای مشاهده و دریافت PDF وارد شوید."
			}
			if newStatus == "courier_assigned" && e.Record.GetString("courier_name") != "" {
				body += fmt.Sprintf(" | پیک: %s %s", e.Record.GetString("courier_name"), e.Record.GetString("courier_phone"))
			}
			notify(e.App, e.Record.GetString("clinic"), "user", typ, statusTitles[newStatus], body, e.Record.Id)
		}
		return nil
	})

	// ---- chat: conversation bookkeeping + notifications --------------------
	app.OnRecordCreate("messages").BindFunc(func(e *core.RecordEvent) error {
		if e.Record.GetString("kind") == "" {
			if e.Record.GetString("file") != "" {
				e.Record.Set("kind", "file")
			} else {
				e.Record.Set("kind", "text")
			}
		}
		return e.Next()
	})

	app.OnRecordAfterCreateSuccess("messages").BindFunc(func(e *core.RecordEvent) error {
		conv, err := e.App.FindRecordById("conversations", e.Record.GetString("conversation"))
		if err != nil {
			return e.Next()
		}
		sender, _ := e.App.FindRecordById("users", e.Record.GetString("sender"))
		fromAdmin := isAdmin(sender)

		preview := e.Record.GetString("text")
		switch e.Record.GetString("kind") {
		case "image":
			preview = "تصویر " + preview
		case "file":
			preview = "فایل: " + e.Record.GetString("file_name")
		case "voice":
			preview = "پیام صوتی"
		}
		preview = truncate(preview, 120)

		conv.Set("last_text", preview)
		conv.Set("last_at", e.Record.GetDateTime("created"))
		conv.Set("last_sender", e.Record.GetString("sender"))
		if fromAdmin {
			conv.Set("unread_clinic", conv.GetInt("unread_clinic")+1)
		} else {
			conv.Set("unread_admin", conv.GetInt("unread_admin")+1)
		}
		if err := e.App.Save(conv); err != nil {
			e.App.Logger().Error("chat: update conversation", "error", err)
		}

		if fromAdmin {
			notify(e.App, conv.GetString("clinic"), "user", "chat", "پیام جدید از آزمایشگاه ملوپت", preview, conv.Id)
		} else {
			title := "پیام جدید"
			if sender != nil {
				title = "پیام از " + sender.GetString("clinic_name")
			}
			notify(e.App, "", "admins", "chat", title, preview, conv.Id)
		}
		return e.Next()
	})

	// ---- promotions: broadcast notification -------------------------------
	app.OnRecordAfterCreateSuccess("promotions").BindFunc(func(e *core.RecordEvent) error {
		if e.Record.GetBool("active") && e.Record.GetBool("notify") {
			notify(e.App, "", "clinics", "promo", e.Record.GetString("title"),
				truncate(e.Record.GetString("body"), 200), e.Record.Id)
		}
		return e.Next()
	})
}

func isAdmin(r *core.Record) bool {
	return r != nil && r.Collection().Name == "users" && r.GetString("role") == "admin"
}
