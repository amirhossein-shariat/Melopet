package migrations

import (
	"os"

	"github.com/pocketbase/pocketbase/core"
)

type ref map[string][2]float64

type param struct {
	Key  string `json:"key"`
	Name string `json:"name"`
	Unit string `json:"unit"`
	Ref  ref    `json:"ref,omitempty"`
}

type seedTest struct {
	Name, Code, Category, SampleType string
	Hours                            float64
	Price                            float64 // partner (همکار) price in Toman/Rial as shown in the lab software
	Params                           []param
	Sort                             int
}

// NOTE: reference ranges are common published values for dogs/cats and are
// meant as editable defaults — the lab's technical manager should verify
// them against their own analyzers from the admin panel.
var seedTests = []seedTest{
	{
		Name: "CBC (شمارش کامل سلول‌های خون)", Code: "CBC", Category: "hematology", SampleType: "خون کامل (EDTA)", Hours: 6, Price: 400000, Sort: 1,
		Params: []param{
			{"wbc", "WBC", "×10³/µL", ref{"dog": {5.5, 16.9}, "cat": {5.5, 19.5}}},
			{"rbc", "RBC", "×10⁶/µL", ref{"dog": {5.5, 8.5}, "cat": {5.0, 10.0}}},
			{"hgb", "HGB", "g/dL", ref{"dog": {12, 18}, "cat": {8, 15}}},
			{"hct", "HCT", "%", ref{"dog": {37, 55}, "cat": {24, 45}}},
			{"mcv", "MCV", "fL", ref{"dog": {60, 77}, "cat": {39, 55}}},
			{"mch", "MCH", "pg", ref{"dog": {19.5, 24.5}, "cat": {12.5, 17.5}}},
			{"mchc", "MCHC", "g/dL", ref{"dog": {32, 36}, "cat": {30, 36}}},
			{"plt", "PLT", "×10³/µL", ref{"dog": {175, 500}, "cat": {300, 800}}},
			{"neut", "Neutrophils", "%", ref{"dog": {60, 77}, "cat": {35, 75}}},
			{"lymph", "Lymphocytes", "%", ref{"dog": {12, 30}, "cat": {20, 55}}},
			{"mono", "Monocytes", "%", ref{"dog": {3, 10}, "cat": {1, 4}}},
			{"eos", "Eosinophils", "%", ref{"dog": {2, 10}, "cat": {2, 12}}},
			{"baso", "Basophils", "%", ref{"dog": {0, 1}, "cat": {0, 1}}},
		},
	},
	{Name: "AST (SGOT)", Code: "AST", Category: "biochemistry", SampleType: "سرم", Hours: 4, Price: 95000, Sort: 10,
		Params: []param{{"ast", "AST", "U/L", ref{"dog": {0, 50}, "cat": {0, 48}}}}},
	{Name: "ALT (SGPT)", Code: "ALT", Category: "biochemistry", SampleType: "سرم", Hours: 4, Price: 95000, Sort: 11,
		Params: []param{{"alt", "ALT", "U/L", ref{"dog": {10, 125}, "cat": {12, 130}}}}},
	{Name: "ALP (آلکالین فسفاتاز)", Code: "ALP", Category: "biochemistry", SampleType: "سرم", Hours: 4, Price: 95000, Sort: 12,
		Params: []param{{"alp", "ALP", "U/L", ref{"dog": {23, 212}, "cat": {14, 111}}}}},
	{Name: "Cholesterol (کلسترول)", Code: "Chol", Category: "biochemistry", SampleType: "سرم", Hours: 4, Price: 95000, Sort: 13,
		Params: []param{{"chol", "Cholesterol", "mg/dL", ref{"dog": {110, 320}, "cat": {65, 225}}}}},
	{Name: "Triglyceride (تری‌گلیسرید)", Code: "TG", Category: "biochemistry", SampleType: "سرم", Hours: 4, Price: 95000, Sort: 14,
		Params: []param{{"tg", "Triglyceride", "mg/dL", ref{"dog": {20, 150}, "cat": {10, 100}}}}},
	{Name: "Glucose (قند خون)", Code: "Glu", Category: "biochemistry", SampleType: "سرم / پلاسما (فلوراید)", Hours: 4, Price: 95000, Sort: 15,
		Params: []param{{"glu", "Glucose", "mg/dL", ref{"dog": {74, 143}, "cat": {71, 159}}}}},
	{Name: "GGT (گاما گلوتامیل ترانسفراز)", Code: "GGT", Category: "biochemistry", SampleType: "سرم", Hours: 4, Price: 95000, Sort: 16,
		Params: []param{{"ggt", "GGT", "U/L", ref{"dog": {0, 11}, "cat": {0, 4}}}}},
}

func init() {
	core.AppMigrations.Register(func(app core.App) error {
		// ---- test catalog -------------------------------------------------
		tests, err := app.FindCollectionByNameOrId("tests")
		if err != nil {
			return err
		}
		for _, t := range seedTests {
			r := core.NewRecord(tests)
			r.Set("name", t.Name)
			r.Set("code", t.Code)
			r.Set("category", t.Category)
			r.Set("sample_type", t.SampleType)
			r.Set("turnaround_hours", t.Hours)
			// all tiers start with the current partner price; adjust per tier in the admin panel
			r.Set("price_gold", t.Price)
			r.Set("price_silver", t.Price)
			r.Set("price_bronze", t.Price)
			r.Set("visible_tiers", []string{"gold", "silver", "bronze"})
			r.Set("active", true)
			r.Set("sort", t.Sort)
			r.Set("parameters", t.Params)
			if err := app.Save(r); err != nil {
				return err
			}
		}

		// ---- lab settings -------------------------------------------------
		settings, err := app.FindCollectionByNameOrId("settings")
		if err != nil {
			return err
		}
		s := core.NewRecord(settings)
		s.Set("lab_name", "آزمایشگاه دامپزشکی ملوپت")
		s.Set("slogan", "دقت، سرعت، اعتماد")
		s.Set("phone", "021-00000000")
		s.Set("mobile", "09120000000")
		s.Set("address", "تهران، ... (آدرس آزمایشگاه را از پنل ادمین ویرایش کنید)")
		s.Set("working_hours", "شنبه تا پنجشنبه ۸ تا ۲۰")
		s.Set("instagram", "melopet.lab")
		s.Set("about", "ملوپت، آزمایشگاه تخصصی دامپزشکی با خدمات نمونه‌گیری در محل از طریق پیک.")
		if err := app.Save(s); err != nil {
			return err
		}

		// ---- first lab admin (change the password after first login!) ------
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		mobile := os.Getenv("MELOPET_ADMIN_MOBILE")
		if mobile == "" {
			mobile = "09000000000"
		}
		pass := os.Getenv("MELOPET_ADMIN_PASSWORD")
		if pass == "" {
			pass = "melopet-admin-1234"
		}
		admin := core.NewRecord(users)
		admin.Set("mobile", mobile)
		admin.Set("role", "admin")
		admin.Set("name", "مدیر آزمایشگاه")
		admin.Set("clinic_name", "آزمایشگاه ملوپت")
		admin.Set("approved", true)
		admin.Set("profile_completed", true)
		admin.SetPassword(pass)
		return app.Save(admin)
	}, nil)
}
