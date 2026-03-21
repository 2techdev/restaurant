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
	TenantID string `json:"tenant_id,omitempty"`
	DeviceID string `json:"device_id,omitempty"`
	UserID   string `json:"user_id,omitempty"`
	Role     string `json:"role,omitempty"` // device, admin, manager, waiter, cashier

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

// GenerateToken creates a signed JWT with the given claims.
func (s *JWTService) GenerateToken(claims Claims) (string, error) {
	now := time.Now()
	claims.IssuedAt = now.Unix()
	claims.ExpiresAt = now.Add(s.expiry).Unix()
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
	if claims.Role != "" {
		result["role"] = claims.Role
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
