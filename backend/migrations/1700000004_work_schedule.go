package migrations

import "github.com/pocketbase/pocketbase/core"

// v3: structured working schedule (days, start/end time, official-holiday answer) on clinics
// and on the lab settings. The human-readable summary keeps living in `working_hours`.
func init() {
	core.AppMigrations.Register(func(app core.App) error {
		for _, name := range []string{"users", "settings"} {
			col, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				return err
			}
			if col.Fields.GetByName("work_schedule") == nil {
				col.Fields.Add(&core.JSONField{Name: "work_schedule", MaxSize: 4000})
			}
			// the summary can now be longer than a hand-typed line
			if f, ok := col.Fields.GetByName("working_hours").(*core.TextField); ok {
				f.Max = 400
			}
			if err := app.Save(col); err != nil {
				return err
			}
		}
		return nil
	}, nil)
}
