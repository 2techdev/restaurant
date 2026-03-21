package license

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"
)

// devPrivateSeed is the RFC 8032 Test Vector 1 private seed.
// The corresponding 32-byte public key (kDevPublicKey) is embedded in the
// Flutter client's license_validator.dart. Replace this with a production
// key pair via the LICENSE_SIGNING_KEY environment variable.
//
// Private seed (hex): 9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae3d55
// Public  key (hex): d75a980126086082f7a4e82bef20a6810f5f01b494c89b84db5ac92e7c6a6b3d
const devPrivateSeed = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae3d55"

// Service handles Ed25519 license token generation and validation.
//
// Tokens are self-contained (offline-first): the Flutter client verifies
// them locally using the embedded public key — no network call is required.
type Service struct {
	privateKey ed25519.PrivateKey
	publicKey  ed25519.PublicKey
}

// NewService creates a Service from a hex-encoded 32-byte Ed25519 private seed.
//
// Pass an empty string to use the built-in development seed (kDevPublicKey
// in Flutter). In production set LICENSE_SIGNING_KEY to a freshly generated
// seed.
func NewService(hexSeed string) (*Service, error) {
	if hexSeed == "" {
		hexSeed = devPrivateSeed
	}
	seed, err := hex.DecodeString(hexSeed)
	if err != nil {
		return nil, fmt.Errorf("license: decode seed hex: %w", err)
	}
	if len(seed) != ed25519.SeedSize {
		return nil, fmt.Errorf("license: seed must be %d bytes, got %d",
			ed25519.SeedSize, len(seed))
	}
	priv := ed25519.NewKeyFromSeed(seed)
	return &Service{
		privateKey: priv,
		publicKey:  priv.Public().(ed25519.PublicKey),
	}, nil
}

// Generate creates a signed offline license token from the given request.
//
// The returned token string is a base64url-encoded JSON blob that can be
// copy-pasted into the GastroCore POS app or distributed via any channel.
func (s *Service) Generate(req GenerateRequest) (GenerateResponse, error) {
	if req.BusinessID == "" {
		return GenerateResponse{}, fmt.Errorf("license: business_id is required")
	}
	if req.DurationDays <= 0 {
		req.DurationDays = 365
	}
	if req.MaxDevices <= 0 {
		req.MaxDevices = 1
	}
	if req.Edition == "" {
		req.Edition = EditionFree
	}
	if req.Features == nil {
		req.Features = defaultFeatures(req.Edition)
	}

	now := time.Now().UTC()
	expiresAt := now.AddDate(0, 0, req.DurationDays)

	claims := LicenseClaims{
		BusinessID:        req.BusinessID,
		CustomerName:      req.CustomerName,
		DeviceFingerprint: req.DeviceFingerprint,
		Edition:           req.Edition,
		ExpiresAt:         expiresAt.UTC().Format(time.RFC3339),
		Features:          req.Features,
		IssuedAt:          now.Format(time.RFC3339),
		MaxDevices:        req.MaxDevices,
		Version:           1,
	}

	token, err := s.signClaims(claims)
	if err != nil {
		return GenerateResponse{}, err
	}
	return GenerateResponse{
		Token:     token,
		Claims:    claims,
		IssuedAt:  now,
		ExpiresAt: expiresAt,
	}, nil
}

// Validate verifies the Ed25519 signature of a token and returns its claims.
//
// Returns an error when the signature is invalid, the token is malformed,
// or required fields are missing. Does NOT check whether the token is expired —
// call [IsExpired] separately when enforcement is needed.
func (s *Service) Validate(tokenBase64 string) (*LicenseClaims, error) {
	// 1. Decode base64url outer envelope.
	jsonBytes, err := base64URLDecode(tokenBase64)
	if err != nil {
		return nil, fmt.Errorf("license: base64url decode: %w", err)
	}

	// 2. Unmarshal into a generic map so we can extract and remove "sig".
	var payload map[string]any
	if err := json.Unmarshal(jsonBytes, &payload); err != nil {
		return nil, fmt.Errorf("license: JSON unmarshal: %w", err)
	}

	// 3. Extract and remove the "sig" field.
	sigB64, _ := payload["sig"].(string)
	if sigB64 == "" {
		return nil, fmt.Errorf("license: missing 'sig' field in token")
	}
	delete(payload, "sig")

	// 4. Build the canonical message (compact JSON, keys sorted by Go marshal).
	msg, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("license: canonical JSON: %w", err)
	}

	// 5. Verify Ed25519 signature.
	sig, err := base64URLDecode(sigB64)
	if err != nil {
		return nil, fmt.Errorf("license: decode sig: %w", err)
	}
	if len(sig) != ed25519.SignatureSize {
		return nil, fmt.Errorf("license: invalid signature length %d", len(sig))
	}
	if !ed25519.Verify(s.publicKey, msg, sig) {
		return nil, fmt.Errorf("license: signature verification failed")
	}

	// 6. Parse into typed claims using the full payload (including sig for
	//    unmarshalling — the sig field is simply ignored by the struct).
	var claims LicenseClaims
	if err := json.Unmarshal(jsonBytes, &claims); err != nil {
		return nil, fmt.Errorf("license: unmarshal claims: %w", err)
	}
	return &claims, nil
}

// IsExpired reports whether [claims] are past their expiry timestamp.
func IsExpired(claims *LicenseClaims) bool {
	exp, err := time.Parse(time.RFC3339, claims.ExpiresAt)
	if err != nil {
		return true
	}
	return time.Now().UTC().After(exp)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// signClaims converts claims to the wire token format:
//   base64url( JSON( sorted_fields + "sig" ) )
//
// The canonical message (what is signed) is compact JSON of all claim fields
// with keys sorted alphabetically — identical to the Dart client's
// _canonicalMessage helper in license_validator.dart.
func (s *Service) signClaims(claims LicenseClaims) (string, error) {
	// Marshal struct → JSON, then unmarshal into map[string]any so that
	// json.Marshal (which sorts map string keys) produces the canonical message.
	data, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("license: marshal claims: %w", err)
	}
	var payload map[string]any
	if err := json.Unmarshal(data, &payload); err != nil {
		return "", fmt.Errorf("license: unmarshal to map: %w", err)
	}

	// Canonical message: Go sorts map[string]any keys alphabetically.
	msg, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("license: canonical marshal: %w", err)
	}

	// Sign and embed the signature.
	sig := ed25519.Sign(s.privateKey, msg)
	payload["sig"] = base64.RawURLEncoding.EncodeToString(sig)

	// Final token JSON (still sorted because map keys are sorted).
	final, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("license: final marshal: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(final), nil
}

// base64URLDecode decodes a base64url string with or without padding.
func base64URLDecode(s string) ([]byte, error) {
	// Add padding characters if missing.
	switch len(s) % 4 {
	case 2:
		s += "=="
	case 3:
		s += "="
	}
	return base64.URLEncoding.DecodeString(s)
}

// defaultFeatures returns the implicit feature list for an edition.
// This must mirror FeatureFlags.defaultsByEdition in feature_flags.dart.
func defaultFeatures(edition Edition) []string {
	switch edition {
	case EditionStarter:
		return []string{"analytics", "printing", "reports"}
	case EditionPro:
		return []string{"analytics", "printing", "reports", "kds", "inventory", "crm"}
	case EditionEnterprise:
		return []string{
			"analytics", "printing", "reports",
			"kds", "inventory", "crm",
			"cloudSync", "multiDevice", "apiAccess",
		}
	default: // free
		return []string{}
	}
}
