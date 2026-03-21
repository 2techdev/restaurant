package license

import (
	"strings"
	"testing"
	"time"
)

// TestNewService verifies that the dev seed is accepted and that a production
// seed of the correct length is also accepted.
func TestNewService(t *testing.T) {
	t.Run("dev seed", func(t *testing.T) {
		svc, err := NewService("")
		if err != nil {
			t.Fatalf("NewService(\"\") failed: %v", err)
		}
		if svc == nil {
			t.Fatal("expected non-nil service")
		}
	})

	t.Run("invalid hex seed", func(t *testing.T) {
		_, err := NewService("notvalidhex")
		if err == nil {
			t.Error("expected error for invalid hex seed")
		}
	})

	t.Run("wrong length seed", func(t *testing.T) {
		_, err := NewService("deadbeef") // only 4 bytes
		if err == nil {
			t.Error("expected error for short seed")
		}
	})
}

// TestGenerateAndValidate is the primary round-trip test: generate a token
// then validate it with the same service.
func TestGenerateAndValidate(t *testing.T) {
	svc, err := NewService("")
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}

	req := GenerateRequest{
		BusinessID:   "rest-001",
		CustomerName: "Zum Goldenen Löwen",
		Edition:      EditionPro,
		DurationDays: 365,
		MaxDevices:   3,
	}

	resp, err := svc.Generate(req)
	if err != nil {
		t.Fatalf("Generate: %v", err)
	}

	if resp.Token == "" {
		t.Error("expected non-empty token string")
	}

	claims, err := svc.Validate(resp.Token)
	if err != nil {
		t.Fatalf("Validate: %v", err)
	}

	if claims.BusinessID != req.BusinessID {
		t.Errorf("businessId: got %q, want %q", claims.BusinessID, req.BusinessID)
	}
	if claims.CustomerName != req.CustomerName {
		t.Errorf("customerName: got %q, want %q", claims.CustomerName, req.CustomerName)
	}
	if claims.Edition != EditionPro {
		t.Errorf("edition: got %q, want %q", claims.Edition, EditionPro)
	}
	if claims.MaxDevices != 3 {
		t.Errorf("maxDevices: got %d, want 3", claims.MaxDevices)
	}
	if claims.Version != 1 {
		t.Errorf("v: got %d, want 1", claims.Version)
	}
}

// TestGenerateEditions verifies that each edition maps to the correct
// default feature set.
func TestGenerateEditions(t *testing.T) {
	svc, _ := NewService("")

	cases := []struct {
		edition          Edition
		mustContain      string
		mustNotContain   string
	}{
		{EditionFree, "", "kds"},
		{EditionStarter, "analytics", "kds"},
		{EditionPro, "kds", "cloudSync"},
		{EditionEnterprise, "cloudSync", ""},
	}

	for _, tc := range cases {
		t.Run(string(tc.edition), func(t *testing.T) {
			resp, err := svc.Generate(GenerateRequest{
				BusinessID: "test",
				Edition:    tc.edition,
			})
			if err != nil {
				t.Fatalf("Generate: %v", err)
			}
			features := resp.Claims.Features

			if tc.mustContain != "" && !containsString(features, tc.mustContain) {
				t.Errorf("edition %s: expected %q in features %v",
					tc.edition, tc.mustContain, features)
			}
			if tc.mustNotContain != "" && containsString(features, tc.mustNotContain) {
				t.Errorf("edition %s: did not expect %q in features %v",
					tc.edition, tc.mustNotContain, features)
			}
		})
	}
}

// TestValidateTamperedToken verifies that modifying the token invalidates it.
func TestValidateTamperedToken(t *testing.T) {
	svc, _ := NewService("")

	resp, err := svc.Generate(GenerateRequest{
		BusinessID: "honest-rest",
		Edition:    EditionPro,
	})
	if err != nil {
		t.Fatalf("Generate: %v", err)
	}

	// Flip the last character of the token string.
	token := []rune(resp.Token)
	last := len(token) - 1
	if token[last] == 'A' {
		token[last] = 'B'
	} else {
		token[last] = 'A'
	}

	_, err = svc.Validate(string(token))
	if err == nil {
		t.Error("expected validation to fail for tampered token")
	}
}

// TestValidateWrongKey ensures that a token signed with key A cannot be
// validated with key B.
func TestValidateWrongKey(t *testing.T) {
	// Two different valid Ed25519 seeds (32 bytes each, hex).
	seedA := devPrivateSeed
	seedB := strings.Repeat("ab", 32) // 64 hex chars = 32 bytes

	svcA, _ := NewService(seedA)
	svcB, _ := NewService(seedB)

	resp, err := svcA.Generate(GenerateRequest{
		BusinessID: "rest-a",
		Edition:    EditionEnterprise,
	})
	if err != nil {
		t.Fatalf("Generate: %v", err)
	}

	_, err = svcB.Validate(resp.Token)
	if err == nil {
		t.Error("expected validation to fail when using a different public key")
	}
}

// TestIsExpired verifies the IsExpired helper.
func TestIsExpired(t *testing.T) {
	past := time.Now().Add(-24 * time.Hour).UTC().Format(time.RFC3339)
	future := time.Now().Add(24 * time.Hour).UTC().Format(time.RFC3339)

	if !IsExpired(&LicenseClaims{ExpiresAt: past}) {
		t.Error("expected expired for past timestamp")
	}
	if IsExpired(&LicenseClaims{ExpiresAt: future}) {
		t.Error("expected not-expired for future timestamp")
	}
}

// TestValidateEmptyToken ensures that an empty token returns a clear error.
func TestValidateEmptyToken(t *testing.T) {
	svc, _ := NewService("")
	_, err := svc.Validate("")
	if err == nil {
		t.Error("expected error for empty token string")
	}
}

// TestDeviceFingerprint verifies that deviceFingerprint is round-tripped
// correctly when set.
func TestDeviceFingerprint(t *testing.T) {
	svc, _ := NewService("")
	fingerprint := "device-uuid-1234"

	resp, err := svc.Generate(GenerateRequest{
		BusinessID:        "fp-test",
		Edition:           EditionPro,
		DeviceFingerprint: fingerprint,
	})
	if err != nil {
		t.Fatalf("Generate: %v", err)
	}

	claims, err := svc.Validate(resp.Token)
	if err != nil {
		t.Fatalf("Validate: %v", err)
	}
	if claims.DeviceFingerprint != fingerprint {
		t.Errorf("deviceFingerprint: got %q, want %q",
			claims.DeviceFingerprint, fingerprint)
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func containsString(slice []string, s string) bool {
	for _, v := range slice {
		if v == s {
			return true
		}
	}
	return false
}
