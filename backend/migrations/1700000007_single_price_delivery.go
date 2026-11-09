package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// v6: no more gold/silver/bronze clinics — every test has ONE price.
//   - tests.price  ← the base (bronze) price that used to be the list price
//   - tests.price_gold/silver/bronze + visible_tiers and the clinic_tiers collection are removed
//
// Orders get a delivery choice (free pick-up within the lab's round, or urgent courier with a
// quoted fee that is added to the order total); the lab settings get the fee parameters used by
// the built-in estimate and the pick-up round length.
func init() {
	core.AppMigrations.Register(func(app core.App) error {
		tests, err := app.FindCollectionByNameOrId("tests")
		if err != nil {
			return err
		}
		if tests.Fields.GetByName("price") == nil {
			tests.Fields.Add(&core.NumberField{Name: "price", Min: types.Pointer(0.0)})
			if err := app.Save(tests); err != nil {
				return err
			}
			records, err := app.FindAllRecords("tests")
			if err != nil {
				return err
			}
			for _, r := range records {
				r.Set("price", r.GetFloat("price_bronze"))
				if err := app.Save(r); err != nil {
					return err
				}
			}
			tests, err = app.FindCollectionByNameOrId("tests")
			if err != nil {
				return err
			}
			for _, f := range []string{"price_gold", "price_silver", "price_bronze", "visible_tiers"} {
				tests.Fields.RemoveByName(f)
			}
			if err := app.Save(tests); err != nil {
				return err
			}
		}
		if tiers, err := app.FindCollectionByNameOrId("clinic_tiers"); err == nil {
			if err := app.Delete(tiers); err != nil {
				return err
			}
		}

		orders, err := app.FindCollectionByNameOrId("orders")
		if err != nil {
			return err
		}
		if orders.Fields.GetByName("delivery_type") == nil {
			orders.Fields.Add(
				&core.SelectField{Name: "delivery_type", Values: []string{"standard", "urgent"}, MaxSelect: 1},
				&core.NumberField{Name: "delivery_fee", Min: types.Pointer(0.0)},
				&core.TextField{Name: "delivery_source", Max: 40}, // estimate | snapp
				&core.NumberField{Name: "delivery_distance_km"},
			)
			if err := app.Save(orders); err != nil {
				return err
			}
			// existing orders: "urgent" ones become urgent deliveries (fee unknown = 0)
			records, err := app.FindAllRecords("orders")
			if err != nil {
				return err
			}
			for _, r := range records {
				if r.GetBool("urgent") {
					r.Set("delivery_type", "urgent")
				} else {
					r.Set("delivery_type", "standard")
				}
				if err := app.Save(r); err != nil {
					return err
				}
			}
		}

		settings, err := app.FindCollectionByNameOrId("settings")
		if err != nil {
			return err
		}
		if settings.Fields.GetByName("urgent_base_fee") == nil {
			settings.Fields.Add(
				&core.NumberField{Name: "urgent_base_fee", Min: types.Pointer(0.0)},
				&core.NumberField{Name: "urgent_per_km", Min: types.Pointer(0.0)},
				&core.NumberField{Name: "urgent_min_fee", Min: types.Pointer(0.0)},
				&core.NumberField{Name: "pickup_interval_hours", Min: types.Pointer(1.0)},
			)
			if err := app.Save(settings); err != nil {
				return err
			}
			records, err := app.FindAllRecords("settings")
			if err != nil {
				return err
			}
			for _, r := range records {
				r.Set("urgent_base_fee", 50000)
				r.Set("urgent_per_km", 10000)
				r.Set("urgent_min_fee", 80000)
				r.Set("pickup_interval_hours", 4)
				if err := app.Save(r); err != nil {
					return err
				}
			}
		}
		return nil
	}, nil)
}
