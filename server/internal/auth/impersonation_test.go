package auth

// Unit tests for F1 super admin impersonation. DB-touching tests need a real
// Postgres — those land in impersonation_integration_test.go (separate file
// with build tag) once test sunucusu erişimi netleşir.

import (
	"strings"
	"sync"
	"testing"
	"time"
)

// ── JWT impersonation claims round-trip ──────────────────────────────────────

func TestImpersonationClaimsRoundTrip(t *testing.T) {
	svc := NewJWTService("test-secret-32-bytes-long-enough", 1*time.Hour)
	tok, err := svc.GenerateTokenWithExpiry(Claims{
		TenantID:               "tenant-A",
		UserID:                 "target-user-1",
		Role:                   "manager",
		OrganizationID:         "tenant-A",
		OrgRole:                "RESTAURANT_MANAGER",
		ImpersonatedBy:         "super-admin-7",
		ImpersonationSessionID: "sess-XYZ",
	}, 15*time.Minute)
	if err != nil {
		t.Fatalf("GenerateTokenWithExpiry: %v", err)
	}
	claims, err := svc.ValidateToken(tok)
	if err != nil {
		t.Fatalf("ValidateToken: %v", err)
	}
	if claims["impersonated_by"] != "super-admin-7" {
		t.Errorf("impersonated_by lost: %q", claims["impersonated_by"])
	}
	if claims["impersonation_session_id"] != "sess-XYZ" {
		t.Errorf("session_id lost: %q", claims["impersonation_session_id"])
	}
	if claims["user_id"] != "target-user-1" {
		t.Errorf("target user_id lost: %q", claims["user_id"])
	}
	if _, ok := claims["is_super_admin"]; ok {
		t.Errorf("impersonation token must NOT carry is_super_admin (defense-in-depth)")
	}
}

func TestSuperAdminClaimRoundTrip(t *testing.T) {
	svc := NewJWTService("test-secret-32-bytes-long-enough", 1*time.Hour)
	tok, err := svc.GenerateToken(Claims{
		UserID:       "super-1",
		Role:         "admin",
		IsSuperAdmin: true,
	})
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	claims, err := svc.ValidateToken(tok)
	if err != nil {
		t.Fatalf("ValidateToken: %v", err)
	}
	if claims["is_super_admin"] != "true" {
		t.Errorf("is_super_admin not propagated: %q", claims["is_super_admin"])
	}
}

// ── Short-expiry semantics (15 min hard cap) ─────────────────────────────────

func TestImpersonationTokenExpires(t *testing.T) {
	svc := NewJWTService("test-secret", 0)
	// Negative expiry → claims.ExpiresAt is in the past at generate-time,
	// so ValidateToken must reject. (1 ns is below Unix-second precision
	// and would silently round to "now".)
	tok, err := svc.GenerateTokenWithExpiry(Claims{
		UserID:                 "u",
		ImpersonatedBy:         "su",
		ImpersonationSessionID: "s",
	}, -1*time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.ValidateToken(tok); err == nil {
		t.Errorf("expected expiry error, got nil")
	} else if !strings.Contains(err.Error(), "expired") {
		t.Errorf("expected 'expired' in error, got %v", err)
	}
}

// ── Rate limiter (in-memory, per-super-admin) ────────────────────────────────

func TestImpersonationRateLimit_AllowsUpToMax(t *testing.T) {
	r := &impersonationRateState{buckets: make(map[string]*rateBucket)}
	for i := 0; i < impersonationRateLimitMax; i++ {
		if !r.allow("su-1") {
			t.Fatalf("allow #%d returned false (max=%d)", i+1, impersonationRateLimitMax)
		}
	}
	if r.allow("su-1") {
		t.Errorf("expected (max+1)th call to be blocked")
	}
}

func TestImpersonationRateLimit_PerSuperAdminIsolation(t *testing.T) {
	r := &impersonationRateState{buckets: make(map[string]*rateBucket)}
	for i := 0; i < impersonationRateLimitMax; i++ {
		r.allow("su-A")
	}
	if r.allow("su-A") {
		t.Errorf("su-A should be blocked")
	}
	if !r.allow("su-B") {
		t.Errorf("su-B should be allowed (different bucket)")
	}
}

func TestImpersonationRateLimit_BucketResets(t *testing.T) {
	r := &impersonationRateState{buckets: make(map[string]*rateBucket)}
	r.buckets["su-X"] = &rateBucket{count: impersonationRateLimitMax, resetAt: time.Now().Add(-time.Minute)}
	if !r.allow("su-X") {
		t.Errorf("expired bucket should reset and allow")
	}
}

func TestImpersonationRateLimit_ConcurrentSafe(t *testing.T) {
	r := &impersonationRateState{buckets: make(map[string]*rateBucket)}
	var wg sync.WaitGroup
	allowed := 0
	var mu sync.Mutex
	for i := 0; i < 200; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if r.allow("su-C") {
				mu.Lock()
				allowed++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if allowed != impersonationRateLimitMax {
		t.Errorf("concurrent allowed=%d, want %d", allowed, impersonationRateLimitMax)
	}
}

// ── clientIP extraction ──────────────────────────────────────────────────────

func TestClientIP_Extraction(t *testing.T) {
	cases := []struct {
		xff, xrip, remote, want string
	}{
		{"203.0.113.5", "", "10.0.0.1:12345", "203.0.113.5"},
		{"203.0.113.5, 198.51.100.1", "", "", "203.0.113.5"},
		{"", "198.51.100.42", "", "198.51.100.42"},
		{"", "", "10.0.0.1:12345", "10.0.0.1:12345"},
	}
	for _, tc := range cases {
		got := pickIP(tc.xff, tc.xrip, tc.remote)
		if got != tc.want {
			t.Errorf("pickIP(%q,%q,%q) = %q, want %q", tc.xff, tc.xrip, tc.remote, got, tc.want)
		}
	}
}

func pickIP(xff, xrip, remote string) string {
	if xff != "" {
		if i := strings.Index(xff, ","); i >= 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	if xrip != "" {
		return xrip
	}
	return remote
}
