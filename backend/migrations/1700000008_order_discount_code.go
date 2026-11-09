package migrations

import "github.com/pocketbase/pocketbase/core"

// v7: the discount code used on an order (the amount lives in the existing `discount` field).
func init() {
	core.AppMigrations.Register(func(app core.App) error {
		orders, err := app.FindCollectionByNameOrId("orders")
		if err != nil {
			return err
		}
		if orders.Fields.GetByName("discount_code") == nil {
			orders.Fields.Add(&core.TextField{Name: "discount_code", Max: 50})
			return app.Save(orders)
		}
		return nil
	}, nil)
}
