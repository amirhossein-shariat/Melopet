package main

import (
	"crypto/subtle"
	"net/http"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
)

// SMS-code (OTP) login for clinics.
//
//	POST /api/melopet/auth/request-code {mobile}        → sends a 4-digit code
//	POST /api/melopet/auth/verify       {mobile, code}  → existing clinic: auth token
//	                                                       new number: {registered:false, proof}
//
// A new clinic account can only be created with the `proof` from a verified code
// (see the users create hook), so nobody can register a mobile number they don't own.
//
// TEST MODE: no SMS provider is wired yet, so while MELOPET_SMS_TEST_MODE is not "false"
// the code is the fixed MELOPET_SMS_TEST_CODE (default "1111") and NO SMS IS SENT.
// Anyone who knows a clinic's mobile number can then sign in as that clinic, so turn test
// mode off (and connect a provider in sendSMS) before real use.
//
// Lab admins never sign in with codes: they use their admin ID + password.

var mobileRe = regexp.MustCompile(`^09\d{9}$`)

const (
	otpTTL         = 5 * time.Minute
	otpResendAfter = 20 * time.Second
	otpMaxAttempts = 5
	proofTTL       = 30 * time.Minute
)

type otpEntry struct {
	code     string
	expires  time.Time
	sentAt   time.Time
	attempts int
}

var (
	otpMu      sync.Mutex
	otpStore   = map[string]*otpEntry{}
	proofKey   = security.RandomString(48) // per-process; proofs are short-lived anyway
	signupType = "signup"
)

func smsTestMode() bool {
	v := strings.ToLower(os.Getenv("MELOPET_SMS_TEST_MODE"))
	if v == "" {
		return true // no provider configured yet
	}
	return v != "false" && v != "0"
}

func smsTestCode() string {
	if c := os.Getenv("MELOPET_SMS_TEST_CODE"); len(c) == 4 {
		return c
	}
	return "1111"
}

// sendSMS delivers the code. Plug your SMS panel in here (Kavenegar, Melipayamak, ...).
func sendSMS(mobile, code string) error {
	return errSMSNotConfigured
}

type smsError string

func (e smsError) Error() string { return string(e) }

const errSMSNotConfigured = smsError("sms provider is not configured")

func normalizeMobile(s string) string {
	r := strings.NewReplacer("۰", "0", "۱", "1", "۲", "2", "۳", "3", "۴", "4", "۵", "5", "۶", "6", "۷", "7", "۸", "8", "۹", "9")
	return strings.TrimSpace(r.Replace(s))
}

// verifyProof checks a signup proof for the given mobile number.
func verifyProof(token, mobile string) bool {
	if token == "" {
		return false
	}
	claims, err := security.ParseJWT(token, proofKey)
	if err != nil {
		return false
	}
	return claims["typ"] == signupType && claims["mobile"] == mobile
}

func registerAuthRoutes(se *core.ServeEvent) {
	if smsTestMode() {
		se.App.Logger().Warn("SMS TEST MODE is ON: login code is fixed and no SMS is sent. Set MELOPET_SMS_TEST_MODE=false before real use.",
			"code", smsTestCode())
	}
	g := se.Router.Group("/api/melopet/auth")

	g.POST("/request-code", func(e *core.RequestEvent) error {
		var body struct {
			Mobile string `json:"mobile"`
		}
		if err := e.BindBody(&body); err != nil {
			return e.BadRequestError("درخواست نامعتبر است", err)
		}
		mobile := normalizeMobile(body.Mobile)
		if !mobileRe.MatchString(mobile) {
			return e.BadRequestError("شماره موبایل معتبر نیست", nil)
		}

		otpMu.Lock()
		defer otpMu.Unlock()
		if old, ok := otpStore[mobile]; ok && time.Since(old.sentAt) < otpResendAfter && time.Now().Before(old.expires) {
			return e.TooManyRequestsError("کمی صبر کنید و دوباره تلاش کنید", nil)
		}

		test := smsTestMode()
		code := smsTestCode()
		if !test {
			code = security.RandomStringWithAlphabet(4, "0123456789")
			if err := sendSMS(mobile, code); err != nil {
				e.App.Logger().Error("sms", "error", err)
				return e.Error(http.StatusNotImplemented, "ارسال پیامک هنوز فعال نشده است", err)
			}
		}
		otpStore[mobile] = &otpEntry{code: code, expires: time.Now().Add(otpTTL), sentAt: time.Now()}
		return e.JSON(http.StatusOK, map[string]any{"sent": true, "test_mode": test, "ttl": int(otpTTL.Seconds())})
	})

	g.POST("/verify", func(e *core.RequestEvent) error {
		var body struct {
			Mobile string `json:"mobile"`
			Code   string `json:"code"`
		}
		if err := e.BindBody(&body); err != nil {
			return e.BadRequestError("درخواست نامعتبر است", err)
		}
		mobile := normalizeMobile(body.Mobile)
		code := normalizeMobile(body.Code)

		otpMu.Lock()
		entry, ok := otpStore[mobile]
		valid := false
		if ok {
			switch {
			case time.Now().After(entry.expires) || entry.attempts >= otpMaxAttempts:
				delete(otpStore, mobile)
			default:
				entry.attempts++
				valid = subtle.ConstantTimeCompare([]byte(entry.code), []byte(code)) == 1
				if valid {
					delete(otpStore, mobile)
				}
			}
		}
		otpMu.Unlock()
		if !valid {
			return e.BadRequestError("کد وارد شده اشتباه یا منقضی شده است", nil)
		}

		user, err := e.App.FindFirstRecordByFilter("users", "mobile = {:m}", dbx.Params{"m": mobile})
		if err != nil {
			proof, err := security.NewJWT(jwt.MapClaims{"typ": signupType, "mobile": mobile}, proofKey, proofTTL)
			if err != nil {
				return e.InternalServerError("", err)
			}
			return e.JSON(http.StatusOK, map[string]any{"registered": false, "proof": proof})
		}
		if user.GetString("role") == "admin" {
			return e.ForbiddenError("این حساب با شناسه ادمین و رمز عبور وارد می‌شود", nil)
		}
		return apis.RecordAuthResponse(e, user, "otp", map[string]any{"registered": true})
	})
}
