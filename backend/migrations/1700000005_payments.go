package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// v4: accounts. A clinic's debt is the sum of its (non-cancelled) orders minus the
// confirmed payments. Clinics record a card-to-card payment (status "pending"), the lab
// confirms or rejects it; admins can also record payments themselves (already confirmed).
func init() {
	core.AppMigrations.Register(func(app core.App) error {
		settings, err := app.FindCollectionByNameOrId("settings")
		if err != nil {
			return err
		}
		if settings.Fields.GetByName("card_number") == nil {
			settings.Fields.Add(
				&core.TextField{Name: "card_number", Max: 40},
				&core.TextField{Name: "card_holder", Max: 200},
				&core.TextField{Name: "bank_name", Max: 100},
			)
			if err := app.Save(settings); err != nil {
				return err
			}
		}

		if _, err := app.FindCollectionByNameOrId("payments"); err == nil {
			return nil
		}
		pay := core.NewBaseCollection("payments", "pbc_payments")
		pay.Fields.Add(
			&core.RelationField{Name: "clinic", CollectionId: "_pb_users_auth_", Required: true, MaxSelect: 1, CascadeDelete: true},
			&core.NumberField{Name: "amount", Required: true, Min: types.Pointer(1.0)},
			&core.SelectField{Name: "method", Values: []string{"card", "cash", "other"}, MaxSelect: 1},
			&core.TextField{Name: "tracking_no", Max: 100},
			&core.TextField{Name: "note", Max: 1000},
			&core.DateField{Name: "paid_at"},
			&core.SelectField{Name: "status", Values: []string{"pending", "confirmed", "rejected"}, MaxSelect: 1},
		)
		autodates(pay)
		pay.AddIndex("idx_payments_clinic", false, "clinic", "")
		pay.ListRule = types.Pointer("clinic = @request.auth.id || " + ruleAdmin)
		pay.ViewRule = types.Pointer("clinic = @request.auth.id || " + ruleAdmin)
		// a clinic can only file a pending payment for itself; admins may record confirmed ones
		pay.CreateRule = types.Pointer(`(@request.body.clinic = @request.auth.id && @request.body.status:isset = false) || ` + ruleAdmin)
		pay.UpdateRule = types.Pointer(ruleAdmin)
		pay.DeleteRule = types.Pointer(ruleAdmin)
		return app.Save(pay)
	}, func(app core.App) error {
		if c, err := app.FindCollectionByNameOrId("payments"); err == nil {
			return app.Delete(c)
		}
		return nil
	})
}
