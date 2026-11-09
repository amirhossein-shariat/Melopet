package main

import (
	"errors"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

// Discount codes (from the "پیشنهادهای ویژه" promotions) can be entered while placing an order.
// The percentage is taken off the TESTS only (the courier fee is not discounted) and is always
// computed on the server, so the amount cannot be tampered with from the phone.

type promoResult struct {
	Code     string  `json:"code"`
	Title    string  `json:"title"`
	Percent  float64 `json:"percent"`
	Subtotal float64 `json:"subtotal"`
	Discount float64 `json:"discount"`
}

var (
	errPromoUnknown = errors.New("کد تخفیف معتبر نیست")
	errPromoExpired = errors.New("مهلت این کد تخفیف تمام شده است")
)

// findPromo returns the active promotion with this code (case-insensitive, spaces ignored).
func findPromo(app core.App, code string) (*core.Record, error) {
	code = strings.TrimSpace(code)
	if code == "" {
		return nil, errPromoUnknown
	}
	promos, err := app.FindRecordsByFilter("promotions", "active = true && code != ''", "", 0, 0)
	if err != nil {
		return nil, err
	}
	for _, p := range promos {
		if !strings.EqualFold(strings.TrimSpace(p.GetString("code")), code) || p.GetFloat("discount_percent") <= 0 {
			continue
		}
		if until := p.GetDateTime("valid_until"); !until.IsZero() && until.Time().Before(time.Now()) {
			return nil, errPromoExpired
		}
		return p, nil
	}
	return nil, errPromoUnknown
}

func applyPromo(app core.App, code string, subtotal float64) (promoResult, error) {
	p, err := findPromo(app, code)
	if err != nil {
		return promoResult{}, err
	}
	pct := p.GetFloat("discount_percent")
	return promoResult{
		Code:     strings.ToUpper(strings.TrimSpace(p.GetString("code"))),
		Title:    p.GetString("title"),
		Percent:  pct,
		Subtotal: subtotal,
		Discount: math.Round(subtotal * pct / 100),
	}, nil
}

type promoCheckRequest struct {
	Code  string   `json:"code"`
	Tests []string `json:"tests"`
}

func registerPromoRoutes(g *router.RouterGroup[*core.RequestEvent]) {
	// Preview of a code for the tests selected so far.
	g.POST("/promo/check", func(e *core.RequestEvent) error {
		var body promoCheckRequest
		if err := e.BindBody(&body); err != nil {
			return e.BadRequestError("درخواست نامعتبر است", err)
		}
		catalog, err := catalogFor(e.App)
		if err != nil {
			return e.InternalServerError("", err)
		}
		price := map[string]float64{}
		for _, c := range catalog {
			price[c.Id] = c.Price
		}
		subtotal := 0.0
		for _, id := range body.Tests {
			subtotal += price[id]
		}
		res, err := applyPromo(e.App, body.Code, subtotal)
		if err != nil {
			return e.BadRequestError(err.Error(), nil)
		}
		return e.JSON(http.StatusOK, res)
	})
}
