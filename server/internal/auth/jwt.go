package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// Claims holds the JWT payload fields used by GastroCore.
type Claims struct {
	TenantID   string `json:"tenant_id,omitempty"`   // organization / brand ID
	DeviceID   string `json:"device_id,omitempty"`   // legacy device auth
	UserID     string `json:"user_id,omitempty"`     // app_user or admin_user ID
	StoreID    string `json:"store_id,omitempty"`    // store scope (empty = org-level)
	DeviceType string `json:"device_type,omitempty"` // kds, kiosk, pos, waiter
	Role       string `json:"role,omitempty"`        // brand_manager, store_manager, waiter, kiosk, kds, device, admin

	// HQ chain fields — added in 014_hq_chain. The DB-side org_role on
	// users/admin_users is mirrored here so /api/v1/org/* authorization
	// can run without an extra DB round-trip.
	OrganizationID string `json:"organization_id,omitempty"`
	OrgRole        string `json:"org_role,omitempty"` // HQ_ADMIN | HQ_MANAGER | RESTAURANT_MANAGER | RESTAURANT_STAFF | POS_OPERATOR

	// Super admin / impersonation fields (migration 024 — F1).
	// IsSuperAdmin is set on the *normal* admin JWT for users with the
	// admin_users.is_super_admin flag. ImpersonatedBy + ImpersonationSessionID
	// are set on the *short-lived* impersonation JWT (15 min). Their presence
	// flags downstream audit trails that this token acts on behalf of a super
	// admin, not the target user themselves.
	IsSuperAdmin           bool   `json:"is_super_admin,omitempty"`
	ImpersonatedBy         string `json:"impersonated_by,omitempty"`
	ImpersonationSessionID string `json:"impersonation_session_id,omitempty"`

	// Standard JWT fields
	Subject   string `json:"sub,omitempty"`
	IssuedAt  int64  `json:"iat,omitempty"`
	ExpiresAt int64  `json:"exp,omitempty"`
	Issuer    string `json:"iss,omitempty"`
}

// JWTService handles JWT generation and validation.
type JWTService struct {
	secret []byte
	expiry time.Duration
}

// NewJWTService creates a new JWT service.
func NewJWTService(secret string, expiry time.Duration) *JWTService {
	return &JWTService{
		secret: []byte(secret),
		expiry: expiry,
	}
}

// jwtHeader is the static header for HS256 JWTs.
var jwtHeader = base64URLEncode([]byte(`{"alg":"HS256","typ":"JWT"}`))

// GenerateToken creates a signed JWT with the given claims using the service's
// default expiry.
func (s *JWTService) GenerateToken(claims Claims) (string, error) {
	return s.GenerateTokenWithExpiry(claims, s.expiry)
}

// GenerateTokenWithExpiry creates a signed JWT with a caller-specified expiry.
// Used by short-lived impersonation tokens (15 min) without spinning up a
// separate JWTService instance.
func (s *JWTService) GenerateTokenWithExpiry(claims Claims, expiry time.Duration) (string, error) {
	now := time.Now()
	claims.IssuedAt = now.Unix()
	claims.ExpiresAt = now.Add(expiry).Unix()
	claims.Issuer = "gastrocore"

	if claims.UserID != "" {
		claims.Subject = claims.UserID
	} else if claims.DeviceID != "" {
		claims.Subject = claims.DeviceID
	}

	payload, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("marshal claims: %w", err)
	}

	encodedPayload := base64URLEncode(payload)
	signingInput := jwtHeader + "." + encodedPayload

	mac := hmac.New(sha256.New, s.secret)
	mac.Write([]byte(signingInput))
	signature := base64URLEncode(mac.Sum(nil))

	return signingInput + "." + signature, nil
}

// ValidateToken verifies the JWT signature and expiry, returning the claims as
// a string map suitable for middleware context injection.
func (s *JWTService) ValidateToken(token string) (map[string]string, error) {
	parts := strings.SplitN(token, ".", 3)
	if len(parts) != 3 {
		return nil, errors.New("invalid token format")
	}

	// Verify signature
	signingInput := parts[0] + "." + parts[1]
	mac := hmac.New(sha256.New, s.secret)
	mac.Write([]byte(signingInput))
	expectedSig := base64URLEncode(mac.Sum(nil))

	if !hmac.Equal([]byte(parts[2]), []byte(expectedSig)) {
		return nil, errors.New("invalid token signature")
	}

	// Decode payload
	payload, err := base64URLDecode(parts[1])
	if err != nil {
		return nil, fmt.Errorf("decode payload: %w", err)
	}

	var claims Claims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return nil, fmt.Errorf("unmarshal claims: %w", err)
	}

	// Check expiry
	if claims.ExpiresAt > 0 && time.Now().Unix() > claims.ExpiresAt {
		return nil, errors.New("token expired")
	}

	// Convert to string map for middleware
	result := make(map[string]string)
	if claims.TenantID != "" {
		result["tenant_id"] = claims.TenantID
	}
	if claims.DeviceID != "" {
		result["device_id"] = claims.DeviceID
	}
	if claims.UserID != "" {
		result["user_id"] = claims.UserID
	}
	if claims.StoreID != "" {
		result["store_id"] = claims.StoreID
	}
	if claims.DeviceType != "" {
		result["device_type"] = claims.DeviceType
	}
	if claims.Role != "" {
		result["role"] = claims.Role
	}
	if claims.OrganizationID != "" {
		result["organization_id"] = claims.OrganizationID
	}
	if claims.OrgRole != "" {
		result["org_role"] = claims.OrgRole
	}
	if claims.IsSuperAdmin {
		result["is_super_admin"] = "true"
	}
	if claims.ImpersonatedBy != "" {
		result["impersonated_by"] = claims.ImpersonatedBy
	}
	if claims.ImpersonationSessionID != "" {
		result["impersonation_session_id"] = claims.ImpersonationSessionID
	}

	return result, nil
}

func base64URLEncode(data []byte) string {
	return strings.TrimRight(base64.URLEncoding.EncodeToString(data), "=")
}

func base64URLDecode(s string) ([]byte, error) {
	// Add padding if needed
	switch len(s) % 4 {
	case 2:
		s += "=="
	case 3:
		s += "="
	}
	return base64.URLEncoding.DecodeString(s)
}
