package crypto

import (
	"strings"
	"testing"
)

func TestHashPassword_Format(t *testing.T) {
	h, err := HashPassword("mysecret")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	parts := strings.SplitN(h, "$", 5)
	if len(parts) != 5 {
		t.Fatalf("expected 5 parts, got %d in %q", len(parts), h)
	}
	if parts[0] != "pbkdf2" || parts[1] != "sha256" {
		t.Errorf("unexpected format prefix: %s$%s", parts[0], parts[1])
	}
}

func TestVerifyPassword_CorrectPassword(t *testing.T) {
	password := "correct-horse-battery-staple"
	hash, err := HashPassword(password)
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyPassword(password, hash) {
		t.Error("VerifyPassword returned false for the correct password")
	}
}

func TestVerifyPassword_WrongPassword(t *testing.T) {
	hash, _ := HashPassword("correct")
	if VerifyPassword("wrong", hash) {
		t.Error("VerifyPassword returned true for the wrong password")
	}
}

func TestVerifyPassword_TamperedHash(t *testing.T) {
	hash, _ := HashPassword("secret")
	tampered := hash[:len(hash)-1] + "X"
	if VerifyPassword("secret", tampered) {
		t.Error("VerifyPassword should reject a tampered hash")
	}
}

func TestVerifyPassword_InvalidFormat(t *testing.T) {
	if VerifyPassword("anything", "notahash") {
		t.Error("VerifyPassword should return false for garbage input")
	}
	if VerifyPassword("anything", "") {
		t.Error("VerifyPassword should return false for empty hash")
	}
}

func TestHashPassword_Uniqueness(t *testing.T) {
	h1, _ := HashPassword("same")
	h2, _ := HashPassword("same")
	if h1 == h2 {
		t.Error("two hashes of the same password should differ (random salt)")
	}
}

func TestHashPassword_DifferentPasswords(t *testing.T) {
	h1, _ := HashPassword("password1")
	h2, _ := HashPassword("password2")
	if h1 == h2 {
		t.Error("different passwords should produce different hashes")
	}
}

func TestVerifyPassword_EmptyPassword(t *testing.T) {
	hash, err := HashPassword("")
	if err != nil {
		t.Fatal(err)
	}
	if !VerifyPassword("", hash) {
		t.Error("empty password should verify against its own hash")
	}
	if VerifyPassword("notempty", hash) {
		t.Error("non-empty password should not verify against empty password hash")
	}
}
