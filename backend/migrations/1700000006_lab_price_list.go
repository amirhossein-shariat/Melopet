package migrations

import (
	"regexp"
	"strings"

	"github.com/pocketbase/pocketbase/core"
)

// v5: the lab's own partner price list (k1.xlsx). Prices there are in thousands of Toman
// (CBC 400 = 400,000). "*" in the sheet means "no fixed price" → stored as 0 and shown to
// clinics as "توافقی". Everything here stays editable from the admin panel.
//
// Reference ranges are deliberately NOT filled for the newly added tests: the lab's technical
// manager should enter the ranges validated for their own analyzers (the app shows no H/L
// flag for a parameter without a range).
type labTest struct {
	Code, Name, Category, Sample string
	Hours                        float64
	PriceK                       float64 // thousands of Toman; 0 = negotiable ("*")
	Param, Unit                  string  // single numeric parameter, empty → free-text report
}

var labPriceList = []labTest{
	{"CBC", "", "", "", 0, 400, "", ""}, // already seeded with full parameters: only the price is aligned
	{"AST", "", "", "", 0, 95, "", ""},
	{"ALT", "", "", "", 0, 95, "", ""},
	{"ALP", "", "", "", 0, 95, "", ""},
	{"GGT", "", "", "", 0, 99, "", ""},
	{"UREA", "Urea (اوره)", "biochemistry", "سرم", 4, 95, "Urea", "mg/dL"},
	{"SCR", "Creatinine (کراتینین)", "biochemistry", "سرم", 4, 95, "Creatinine", "mg/dL"},
	{"BIL.T", "Total Bilirubin (بیلی‌روبین کل)", "biochemistry", "سرم", 4, 95, "Total Bilirubin", "mg/dL"},
	{"BIL.D", "Direct Bilirubin (بیلی‌روبین مستقیم)", "biochemistry", "سرم", 4, 95, "Direct Bilirubin", "mg/dL"},
	{"CHOL", "", "", "", 0, 95, "", ""},
	{"TG", "", "", "", 0, 95, "", ""},
	{"GLU", "", "", "", 0, 95, "", ""},
	{"T.P", "Total Protein (پروتئین توتال)", "biochemistry", "سرم", 4, 95, "Total Protein", "g/dL"},
	{"ALB", "Albumin (آلبومین)", "biochemistry", "سرم", 4, 95, "Albumin", "g/dL"},
	{"CK", "CK (کراتین کیناز)", "biochemistry", "سرم", 4, 200, "CK", "U/L"},
	{"CA", "Calcium (کلسیم)", "biochemistry", "سرم", 4, 95, "Calcium", "mg/dL"},
	{"PHOS", "Phosphorus (فسفر)", "biochemistry", "سرم", 4, 95, "Phosphorus", "mg/dL"},
	{"NA", "Sodium (سدیم)", "biochemistry", "سرم", 4, 190, "Sodium", "mmol/L"},
	{"K", "Potassium (پتاسیم)", "biochemistry", "سرم", 4, 190, "Potassium", "mmol/L"},
	{"LIPASE", "Lipase (لیپاز)", "biochemistry", "سرم", 4, 300, "Lipase", "U/L"},
	{"AMYLASE", "Amylase (آمیلاز)", "biochemistry", "سرم", 4, 300, "Amylase", "U/L"},
	{"F10", "F10", "other", "", 0, 950, "", ""},
	{"FE", "Iron (آهن)", "biochemistry", "سرم", 4, 190, "Iron", "µg/dL"},
	{"CL", "Chloride (کلر)", "biochemistry", "سرم", 4, 190, "Chloride", "mmol/L"},
	{"CORTISOL", "Cortisol (کورتیزول)", "hormone", "سرم", 0, 490, "Cortisol", "µg/dL"},
	{"T4", "T4 (تیروکسین)", "hormone", "سرم", 0, 490, "Total T4", "µg/dL"},
	{"TSH", "TSH (هورمون محرک تیروئید)", "hormone", "سرم", 0, 500, "TSH", "ng/mL"},
	{"URINALYSIS", "Urinalysis (آنالیز ادرار)", "urinalysis", "ادرار", 0, 570, "", ""},
	{"URHIIASIS", "URHIIASIS", "other", "", 0, 490, "", ""},
	{"FNA", "FNA (آسپیراسیون با سوزن ظریف)", "pathology", "", 0, 1300, "", ""},
	{"RIVALTA", "Rivalta (تست ریوالتا)", "fluid", "مایع", 0, 340, "", ""},
	{"CYTOLOGY", "Cytology (سیتولوژی)", "pathology", "", 0, 1000, "", ""},
	{"DIRECT SMEAR", "Direct Smear (اسمیر مستقیم)", "parasitology", "", 0, 400, "", ""},
	{"INCUBATION", "Incubation (انکوباسیون)", "culture", "", 0, 400, "", ""},
	{"GRAM", "Gram Stain (رنگ‌آمیزی گرم)", "culture", "", 0, 0, "", ""},
	{"STOOL EXAM", "Stool Exam (آزمایش مدفوع)", "parasitology", "مدفوع", 0, 600, "", ""},
	{"FLOTATION", "Flotation (فلوتاسیون)", "parasitology", "مدفوع", 0, 0, "", ""},
	{"PATHOLOGY", "Pathology (پاتولوژی)", "pathology", "بافت", 0, 2500, "", ""},
	{"VAGINAL SMEAR", "Vaginal Smear (اسمیر واژینال)", "pathology", "", 0, 550, "", ""},
	{"PCR", "PCR", "pcr", "", 0, 1400, "", ""},
	{"REAL TIME", "Real-Time PCR", "pcr", "", 0, 0, "", ""},
	{"KNOT", "Knott's test (تست ناتس)", "parasitology", "خون کامل (EDTA)", 0, 590, "", ""},
	{"RABBIS IN", "Rabies (RABBIS IN)", "serology", "", 0, 14000, "", ""},
	{"RABBIS EX", "Rabies (RABBIS EX)", "serology", "", 0, 0, "", ""},
	{"RETICULOCYTE C.", "Reticulocyte Count (شمارش رتیکولوسیت)", "hematology", "خون کامل (EDTA)", 0, 375, "", ""},
	{"CROSS MATCH", "Cross Match (کراس‌مچ)", "hematology", "خون کامل (EDTA)", 0, 900, "", ""},
	{"PBFD", "PBFD (بیماری منقار و پر)", "pcr", "", 0, 875, "", ""},
	{"GENDER", "Gender (تعیین جنسیت)", "pcr", "", 0, 875, "", ""},
}

var nonAlnum = regexp.MustCompile(`[^a-z0-9]+`)

func init() {
	core.AppMigrations.Register(func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("tests")
		if err != nil {
			return err
		}
		existing, err := app.FindAllRecords("tests")
		if err != nil {
			return err
		}
		byCode := map[string]*core.Record{}
		maxSort := 0
		for _, r := range existing {
			byCode[strings.ToLower(strings.TrimSpace(r.GetString("code")))] = r
			if s := r.GetInt("sort"); s > maxSort {
				maxSort = s
			}
		}
		for _, t := range labPriceList {
			price := t.PriceK * 1000
			if r, ok := byCode[strings.ToLower(t.Code)]; ok {
				// align the price only while the three tiers are still untouched (all equal)
				g, s, b := r.GetFloat("price_gold"), r.GetFloat("price_silver"), r.GetFloat("price_bronze")
				if g == s && s == b && g != price {
					r.Set("price_gold", price)
					r.Set("price_silver", price)
					r.Set("price_bronze", price)
					if err := app.Save(r); err != nil {
						return err
					}
				}
				continue
			}
			maxSort++
			r := core.NewRecord(col)
			r.Set("name", t.Name)
			r.Set("code", t.Code)
			r.Set("category", t.Category)
			r.Set("sample_type", t.Sample)
			r.Set("turnaround_hours", t.Hours)
			r.Set("price_gold", price)
			r.Set("price_silver", price)
			r.Set("price_bronze", price)
			r.Set("visible_tiers", []string{"gold", "silver", "bronze"})
			r.Set("active", true)
			r.Set("sort", maxSort)
			if price == 0 {
				r.Set("description", "قیمت توافقی؛ برای استعلام با آزمایشگاه تماس بگیرید.")
			}
			params := []param{}
			if t.Param != "" {
				params = append(params, param{Key: nonAlnum.ReplaceAllString(strings.ToLower(t.Param), ""), Name: t.Param, Unit: t.Unit})
			}
			r.Set("parameters", params)
			if err := app.Save(r); err != nil {
				return err
			}
		}
		return nil
	}, nil)
}
