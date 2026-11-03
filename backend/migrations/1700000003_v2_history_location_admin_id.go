package migrations

import (
	"os"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// v2:
//   - one login screen for everyone: clinics sign in with their mobile, the lab
//     admin with a dedicated admin ID (users.username), the server decides the role
//   - case history (text and/or voice) on orders, required for courier requests
//   - map location copied onto each order so the courier can navigate to it
func init() {
	core.AppMigrations.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		users.Fields.Add(&core.TextField{Name: "username", Max: 50, Pattern: `^[a-zA-Z][a-zA-Z0-9_.\-]{2,49}$`})
		users.AddIndex("idx_users_username", true, "username", "username != ''")
		users.PasswordAuth.IdentityFields = []string{"mobile", "username", "email"}
		// clinics cannot give themselves an admin ID
		users.UpdateRule = types.Pointer(`(id = @request.auth.id && @request.body.role:isset = false && @request.body.approved:isset = false && @request.body.username:isset = false) || ` + ruleAdmin)
		if err := app.Save(users); err != nil {
			return err
		}

		orders, err := app.FindCollectionByNameOrId("orders")
		if err != nil {
			return err
		}
		orders.Fields.Add(
			&core.FileField{
				Name:      "history_voice",
				MaxSelect: 1,
				MaxSize:   20 << 20,
				MimeTypes: []string{
					"audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac", "audio/mpeg", "audio/mp3",
					"audio/ogg", "audio/opus", "audio/wav", "audio/x-wav", "audio/webm", "audio/3gpp", "audio/amr",
					"video/mp4", "application/octet-stream",
				},
			},
			&core.NumberField{Name: "history_voice_seconds"},
			&core.GeoPointField{Name: "location"},
		)
		if err := app.Save(orders); err != nil {
			return err
		}

		// give the first admin a login ID
		id := os.Getenv("MELOPET_ADMIN_ID")
		if id == "" {
			id = "melopet"
		}
		admin, err := app.FindFirstRecordByData("users", "role", "admin")
		if err == nil && admin.GetString("username") == "" {
			admin.Set("username", id)
			return app.Save(admin)
		}
		return nil
	}, nil)
}
