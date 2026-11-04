// Melopet backend — a PocketBase application (single binary: database, auth,
// file storage, realtime, admin dashboard) extended with the lab's business rules.
//
//	go run . serve --http=0.0.0.0:8090
package main

import (
	"log"
	"os"
	"strings"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"

	_ "github.com/amirhossein-shariat/melopet/backend/migrations"
)

func main() {
	app := pocketbase.New()

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		Automigrate: false,
	})

	registerHooks(app)

	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		registerAuthRoutes(se)
		registerRoutes(se)
		return se.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}

// autoApprove: when MELOPET_AUTO_APPROVE=true new clinics can request a courier
// right after sign-up; otherwise an admin approves them first.
func autoApprove() bool {
	return strings.EqualFold(os.Getenv("MELOPET_AUTO_APPROVE"), "true")
}
