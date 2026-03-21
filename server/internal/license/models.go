// Package license provides Ed25519 JWT token generation and validation for
// GastroCore POS offline-first licensing.
//
// Token format:
//
//	base64url( UTF-8( JSON-with-sig ) )
//
// The signed message is compact JSON of all payload fields (excluding "sig"),
// with keys sorted alphabetically — identical to the Dart canonical message
// produced by LicenseValidator in the Flutter client.
package license

import "time"

// Edition represents a GastroCore license tier.
type Edition string

const (
	EditionFree       Edition = "free"
	EditionStarter    Edition = "starter"
	EditionPro        Edition = "pro"
	EditionEnterprise Edition = "enterprise"
)

// LicenseClaims is the typed payload inside a signed license token.
//
// JSON field names are deliberately lowercase / camelCase to match the
// Flutter client's canonical key ordering. The struct tags mirror the
// canonical alphabetical key order:
//
//	businessId · customerName · (deviceFingerprint) · edition · expiresAt ·
//	features · issuedAt · maxDevices · v
type LicenseClaims struct {
	BusinessID        string   `json:"businessId"`
	CustomerName      string   `json:"customerName"`
	DeviceFingerprint string   `json:"deviceFingerprint,omitempty"`
	Edition           Edition  `json:"edition"`
	ExpiresAt         string   `json:"expiresAt"`
	Features          []string `json:"features"`
	IssuedAt          string   `json:"issuedAt"`
	MaxDevices        int      `json:"maxDevices"`
	Version           int      `json:"v"`
}

// GenerateRequest is the body for POST /api/license/generate.
type GenerateRequest struct {
	// BusinessID uniquely identifies the restaurant / tenant being licensed.
	BusinessID string `json:"business_id"`

	// CustomerName is the human-readable business name embedded in the token.
	CustomerName string `json:"customer_name"`

	// Edition is the license tier (free | starter | pro | enterprise).
	Edition Edition `json:"edition"`

	// Features optionally overrides the default feature list for the edition.
	// When empty, defaults for the edition are used.
	Features []string `json:"features,omitempty"`

	// MaxDevices is the maximum number of POS terminals allowed.
	MaxDevices int `json:"max_devices"`

	// DurationDays controls the validity window. Defaults to 365.
	DurationDays int `json:"duration_days"`

	// DeviceFingerprint optionally locks the token to a single device ID.
	DeviceFingerprint string `json:"device_fingerprint,omitempty"`
}

// GenerateResponse is returned by POST /api/license/generate.
type GenerateResponse struct {
	Token     string       `json:"token"`
	Claims    LicenseClaims `json:"claims"`
	IssuedAt  time.Time    `json:"issued_at"`
	ExpiresAt time.Time    `json:"expires_at"`
}

// ValidateRequest is the body for POST /api/license/validate.
type ValidateRequest struct {
	Token string `json:"token"`
}

// ValidateResponse is returned by POST /api/license/validate.
type ValidateResponse struct {
	Valid     bool          `json:"valid"`
	Claims    *LicenseClaims `json:"claims,omitempty"`
	Expired   bool          `json:"expired"`
	Error     string        `json:"error,omitempty"`
}
