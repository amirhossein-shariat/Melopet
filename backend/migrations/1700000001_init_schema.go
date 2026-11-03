package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Access-rule building blocks.
const (
	ruleAdmin    = `@request.auth.role = "admin"`
	ruleAuthed   = `@request.auth.id != ""`
	maxFileBytes = 25 << 20 // 25MB
)

func imageTypes() []string {
	return []string{"image/jpeg", "image/png", "image/webp", "image/gif"}
}

func autodates(c *core.Collection) {
	c.Fields.Add(&core.AutodateField{Name: "created", OnCreate: true})
	c.Fields.Add(&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true})
}

func init() {
	core.AppMigrations.Register(func(app core.App) error {
		// ------------------------------------------------------------------
		// users (clinics, hospitals and lab admins)
		// ------------------------------------------------------------------
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}

		if email, ok := users.Fields.GetByName("email").(*core.EmailField); ok {
			email.Required = false
		}

		users.Fields.Add(
			&core.SelectField{Name: "role", Values: []string{"clinic", "admin"}, MaxSelect: 1},
			&core.TextField{Name: "mobile", Required: true, Pattern: `^09\d{9}$`},
			&core.TextField{Name: "clinic_name", Max: 200},
			&core.SelectField{Name: "clinic_type", Values: []string{"clinic", "hospital", "petshop", "other"}, MaxSelect: 1},
			&core.TextField{Name: "doctor_name", Max: 200},
			&core.TextField{Name: "council_no", Max: 50},
			&core.TextField{Name: "phone", Max: 50},
			&core.TextField{Name: "contact_person", Max: 200},
			&core.TextField{Name: "contact_mobile", Max: 50},
			&core.TextField{Name: "city", Max: 100},
			&core.TextField{Name: "address", Max: 1000},
			&core.GeoPointField{Name: "location"},
			&core.TextField{Name: "working_hours", Max: 200},
			&core.TextField{Name: "instagram", Max: 100},
			&core.FileField{Name: "logo", MaxSelect: 1, MaxSize: 5 << 20, MimeTypes: imageTypes(), Thumbs: []string{"200x200"}},
			&core.FileField{Name: "letterhead", MaxSelect: 1, MaxSize: 10 << 20, MimeTypes: imageTypes()},
			&core.NumberField{Name: "letterhead_top", Min: types.Pointer(0.0), Max: types.Pointer(150.0)},
			&core.NumberField{Name: "letterhead_bottom", Min: types.Pointer(0.0), Max: types.Pointer(150.0)},
			&core.BoolField{Name: "approved"},
			&core.BoolField{Name: "profile_completed"},
		)
		users.AddIndex("idx_users_mobile", true, "mobile", "mobile != ''")
		users.PasswordAuth.IdentityFields = []string{"mobile", "email"}

		// clinics can see/edit only themselves; admins can see everyone
		users.ListRule = types.Pointer("id = @request.auth.id || " + ruleAdmin)
		users.ViewRule = types.Pointer("id = @request.auth.id || " + ruleAdmin)
		users.CreateRule = types.Pointer("") // public sign-up (role is forced to "clinic" by a hook)
		users.UpdateRule = types.Pointer(`(id = @request.auth.id && @request.body.role:isset = false && @request.body.approved:isset = false) || ` + ruleAdmin)
		users.DeleteRule = nil // superusers only
		// lab admins may reset clinic passwords
		users.ManageRule = types.Pointer(ruleAdmin)

		if err := app.Save(users); err != nil {
			return err
		}

		// ------------------------------------------------------------------
		// clinic_tiers (gold / silver / bronze) — visible ONLY to admins
		// ------------------------------------------------------------------
		tiers := core.NewBaseCollection("clinic_tiers", "pbc_clinic_tiers")
		tiers.Fields.Add(
			&core.RelationField{Name: "clinic", CollectionId: users.Id, MaxSelect: 1, Required: true, CascadeDelete: true},
			&core.SelectField{Name: "tier", Values: []string{"gold", "silver", "bronze"}, MaxSelect: 1, Required: true},
			&core.TextField{Name: "note", Max: 500},
		)
		autodates(tiers)
		tiers.AddIndex("idx_clinic_tiers_clinic", true, "clinic", "")
		tiers.ListRule = types.Pointer(ruleAdmin)
		tiers.ViewRule = types.Pointer(ruleAdmin)
		tiers.CreateRule = types.Pointer(ruleAdmin)
		tiers.UpdateRule = types.Pointer(ruleAdmin)
		tiers.DeleteRule = types.Pointer(ruleAdmin)
		if err := app.Save(tiers); err != nil {
			return err
		}

		// ------------------------------------------------------------------
		// tests — catalog with per-tier prices. Clinics read it only through
		// the /api/melopet/catalog route, which returns their own price.
		// ------------------------------------------------------------------
		tests := core.NewBaseCollection("tests", "pbc_tests")
		tests.Fields.Add(
			&core.TextField{Name: "name", Required: true, Max: 200},
			&core.TextField{Name: "code", Max: 50},
			&core.SelectField{Name: "category", MaxSelect: 1, Required: true, Values: []string{
				"hematology", "biochemistry", "urinalysis", "fluid", "culture",
				"hormone", "pathology", "pcr", "parasitology", "serology", "other",
			}},
			&core.TextField{Name: "description", Max: 2000},
			&core.TextField{Name: "sample_type", Max: 200},
			&core.NumberField{Name: "turnaround_hours", Min: types.Pointer(0.0)},
			&core.NumberField{Name: "price_gold", Min: types.Pointer(0.0)},
			&core.NumberField{Name: "price_silver", Min: types.Pointer(0.0)},
			&core.NumberField{Name: "price_bronze", Min: types.Pointer(0.0)},
			&core.SelectField{Name: "visible_tiers", MaxSelect: 3, Values: []string{"gold", "silver", "bronze"}},
			&core.BoolField{Name: "active"},
			&core.NumberField{Name: "sort"},
			// [{key, name, unit, ref: {dog: [lo, hi], cat: [lo, hi], ...}}]
			&core.JSONField{Name: "parameters", MaxSize: 200000},
		)
		autodates(tests)
		tests.ListRule = types.Pointer(ruleAdmin)
		tests.ViewRule = types.Pointer(ruleAdmin)
		tests.CreateRule = types.Pointer(ruleAdmin)
		tests.UpdateRule = types.Pointer(ruleAdmin)
		tests.DeleteRule = types.Pointer(ruleAdmin)
		if err := app.Save(tests); err != nil {
			return err
		}

		// ------------------------------------------------------------------
		// orders — courier request + sample + results
		// ------------------------------------------------------------------
		orders := core.NewBaseCollection("orders", "pbc_orders")
		orders.Fields.Add(
			&core.TextField{Name: "code", Max: 30},
			&core.RelationField{Name: "clinic", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.SelectField{Name: "status", MaxSelect: 1, Required: true, Values: []string{
				"requested", "courier_assigned", "picked_up", "received", "in_progress", "ready", "cancelled",
			}},
			&core.TextField{Name: "pet_name", Max: 100},
			&core.SelectField{Name: "species", MaxSelect: 1, Values: []string{"dog", "cat", "bird", "rabbit", "rodent", "reptile", "horse", "ruminant", "other"}},
			&core.TextField{Name: "breed", Max: 100},
			&core.TextField{Name: "age", Max: 50},
			&core.SelectField{Name: "sex", MaxSelect: 1, Values: []string{"male", "female", "male_neutered", "female_spayed", "unknown"}},
			&core.NumberField{Name: "weight"},
			&core.TextField{Name: "owner_name", Max: 100},
			&core.TextField{Name: "file_no", Max: 50},
			&core.TextField{Name: "sample_type", Max: 200},
			&core.NumberField{Name: "sample_count"},
			&core.BoolField{Name: "urgent"},
			&core.BoolField{Name: "fasting"},
			&core.TextField{Name: "pickup_address", Max: 1000},
			&core.TextField{Name: "pickup_time", Max: 100},
			&core.TextField{Name: "clinical_notes", Max: 3000},
			&core.JSONField{Name: "items", MaxSize: 200000},   // [{test, name, code, category, price}]
			&core.NumberField{Name: "total"},
			&core.NumberField{Name: "discount"},
			&core.TextField{Name: "courier_name", Max: 100},
			&core.TextField{Name: "courier_phone", Max: 50},
			&core.JSONField{Name: "results", MaxSize: 2000000}, // {testId: {paramKey: value}}
			&core.TextField{Name: "lab_comment", Max: 5000},
			&core.FileField{Name: "result_files", MaxSelect: 10, MaxSize: maxFileBytes},
			&core.JSONField{Name: "history", MaxSize: 200000}, // [{status, at}]
			&core.DateField{Name: "ready_at"},
			&core.BoolField{Name: "paid"},
		)
		autodates(orders)
		orders.AddIndex("idx_orders_code", true, "code", "code != ''")
		orders.ListRule = types.Pointer("clinic = @request.auth.id || " + ruleAdmin)
		orders.ViewRule = types.Pointer("clinic = @request.auth.id || " + ruleAdmin)
		orders.CreateRule = types.Pointer(ruleAdmin) // clinics use /api/melopet/orders
		orders.UpdateRule = types.Pointer(ruleAdmin)
		orders.DeleteRule = nil
		if err := app.Save(orders); err != nil {
			return err
		}

		// ------------------------------------------------------------------
		// promotions — discounts / special offers
		// ------------------------------------------------------------------
		promos := core.NewBaseCollection("promotions", "pbc_promotions")
		promos.Fields.Add(
			&core.TextField{Name: "title", Required: true, Max: 200},
			&core.TextField{Name: "body", Max: 5000},
			&core.FileField{Name: "image", MaxSelect: 1, MaxSize: 10 << 20, MimeTypes: imageTypes(), Thumbs: []string{"600x300"}},
			&core.NumberField{Name: "discount_percent", Min: types.Pointer(0.0), Max: types.Pointer(100.0)},
			&core.TextField{Name: "code", Max: 50},
			&core.DateField{Name: "valid_until"},
			&core.BoolField{Name: "active"},
			&core.BoolField{Name: "notify"},
			&core.TextField{Name: "color", Max: 20},
		)
		autodates(promos)
		promos.ListRule = types.Pointer(`(active = true && ` + ruleAuthed + `) || ` + ruleAdmin)
		promos.ViewRule = types.Pointer(`(active = true && ` + ruleAuthed + `) || ` + ruleAdmin)
		promos.CreateRule = types.Pointer(ruleAdmin)
		promos.UpdateRule = types.Pointer(ruleAdmin)
		promos.DeleteRule = types.Pointer(ruleAdmin)
		if err := app.Save(promos); err != nil {
			return err
		}

		// ------------------------------------------------------------------
		// notifications — per user, or broadcast when user is empty
		// ------------------------------------------------------------------
		notifs := core.NewBaseCollection("notifications", "pbc_notifications")
		notifs.Fields.Add(
			&core.RelationField{Name: "user", CollectionId: users.Id, MaxSelect: 1, CascadeDelete: true},
			&core.SelectField{Name: "audience", MaxSelect: 1, Values: []string{"user", "clinics", "admins"}},
			&core.TextField{Name: "title", Required: true, Max: 200},
			&core.TextField{Name: "body", Max: 2000},
			&core.SelectField{Name: "type", MaxSelect: 1, Values: []string{"order", "result", "promo", "chat", "general"}},
			&core.TextField{Name: "ref", Max: 50},
			&core.BoolField{Name: "read"},
		)
		autodates(notifs)
		notifRead := `user = @request.auth.id || (user = "" && audience = "clinics" && @request.auth.role = "clinic") || (user = "" && audience = "admins" && ` + ruleAdmin + `)`
		notifs.ListRule = types.Pointer(notifRead)
		notifs.ViewRule = types.Pointer(notifRead)
		notifs.CreateRule = types.Pointer(ruleAdmin)
		notifs.UpdateRule = types.Pointer(`user = @request.auth.id && @request.body.title:isset = false && @request.body.body:isset = false && @request.body.user:isset = false`)
		notifs.DeleteRule = types.Pointer(`user = @request.auth.id || ` + ruleAdmin)
		if err := app.Save(notifs); err != nil {
			return err
		}

		// ------------------------------------------------------------------
		// conversations + messages (chat; messages can NEVER be deleted/edited)
		// ------------------------------------------------------------------
		convs := core.NewBaseCollection("conversations", "pbc_conversations")
		convs.Fields.Add(
			&core.RelationField{Name: "clinic", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.TextField{Name: "last_text", Max: 300},
			&core.DateField{Name: "last_at"},
			&core.TextField{Name: "last_sender", Max: 30},
			&core.DateField{Name: "clinic_read_at"},
			&core.DateField{Name: "admin_read_at"},
			&core.NumberField{Name: "unread_clinic"},
			&core.NumberField{Name: "unread_admin"},
		)
		autodates(convs)
		convs.AddIndex("idx_conversations_clinic", true, "clinic", "")
		convs.ListRule = types.Pointer("clinic = @request.auth.id || " + ruleAdmin)
		convs.ViewRule = types.Pointer("clinic = @request.auth.id || " + ruleAdmin)
		convs.CreateRule = nil // created by the server
		convs.UpdateRule = nil // read markers go through /api/melopet/chat/read
		convs.DeleteRule = nil
		if err := app.Save(convs); err != nil {
			return err
		}

		msgs := core.NewBaseCollection("messages", "pbc_messages")
		msgs.Fields.Add(
			&core.RelationField{Name: "conversation", CollectionId: convs.Id, MaxSelect: 1, Required: true},
			&core.RelationField{Name: "sender", CollectionId: users.Id, MaxSelect: 1, Required: true},
			&core.SelectField{Name: "kind", MaxSelect: 1, Values: []string{"text", "image", "file", "voice", "order"}},
			&core.TextField{Name: "text", Max: 5000},
			&core.FileField{Name: "file", MaxSelect: 1, MaxSize: maxFileBytes, Thumbs: []string{"400x0"}},
			&core.TextField{Name: "file_name", Max: 255},
			&core.NumberField{Name: "file_size"},
			&core.TextField{Name: "order_ref", Max: 30},
		)
		autodates(msgs)
		msgRule := `conversation.clinic = @request.auth.id || ` + ruleAdmin
		msgs.ListRule = types.Pointer(msgRule)
		msgs.ViewRule = types.Pointer(msgRule)
		msgs.CreateRule = types.Pointer(`(` + msgRule + `) && @request.body.sender = @request.auth.id && (@request.body.text != "" || @request.body.file:isset = true)`)
		msgs.UpdateRule = nil // no editing
		msgs.DeleteRule = nil // no deleting — permanent chat history
		msgs.AddIndex("idx_messages_conv_created", false, "conversation, created", "")
		if err := app.Save(msgs); err != nil {
			return err
		}
		// self relation can only be added once the collection exists
		msgs.Fields.Add(&core.RelationField{Name: "reply_to", CollectionId: msgs.Id, MaxSelect: 1})
		if err := app.Save(msgs); err != nil {
			return err
		}

		// ------------------------------------------------------------------
		// settings — single row with lab contact info (public read)
		// ------------------------------------------------------------------
		settings := core.NewBaseCollection("settings", "pbc_settings")
		settings.Fields.Add(
			&core.TextField{Name: "lab_name", Max: 200},
			&core.TextField{Name: "slogan", Max: 300},
			&core.TextField{Name: "phone", Max: 100},
			&core.TextField{Name: "mobile", Max: 100},
			&core.TextField{Name: "whatsapp", Max: 100},
			&core.TextField{Name: "telegram", Max: 100},
			&core.TextField{Name: "instagram", Max: 100},
			&core.TextField{Name: "email", Max: 200},
			&core.TextField{Name: "website", Max: 200},
			&core.TextField{Name: "address", Max: 1000},
			&core.GeoPointField{Name: "location"},
			&core.TextField{Name: "working_hours", Max: 500},
			&core.TextField{Name: "about", Max: 5000},
			&core.TextField{Name: "technical_manager", Max: 200},
			&core.FileField{Name: "logo", MaxSelect: 1, MaxSize: 5 << 20, MimeTypes: imageTypes()},
		)
		autodates(settings)
		settings.ListRule = types.Pointer("")
		settings.ViewRule = types.Pointer("")
		settings.CreateRule = nil
		settings.UpdateRule = types.Pointer(ruleAdmin)
		settings.DeleteRule = nil
		return app.Save(settings)
	}, func(app core.App) error {
		for _, name := range []string{"messages", "conversations", "notifications", "promotions", "orders", "tests", "clinic_tiers", "settings"} {
			if c, err := app.FindCollectionByNameOrId(name); err == nil {
				if err := app.Delete(c); err != nil {
					return err
				}
			}
		}
		return nil
	})
}
