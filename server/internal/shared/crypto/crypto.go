// Package crypto provides password hashing utilities using PBKDF2-HMAC-SHA256.
// This is a pure-stdlib implementation that avoids external dependencies.
// 100 000 iterations of HMAC-SHA256 with a 128-bit random salt is compliant
// with NIST SP 800-132 and comparable in security to bcrypt cost 12.
package crypto

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"strconv"
	"strings"
)

const (
	defaultIterations = 100_000
	keyLen            = 32
	saltLen           = 16
)

// HashPassword creates a PBKDF2-SHA256 hash suitable for storage.
// The returned string is self-describing:
//
//	pbkdf2$sha256$<iters>$<base64salt>$<base64key>
func HashPassword(password string) (string, error) {
	salt := make([]byte, saltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("crypto: generate salt: %w", err)
	}
	dk := pbkdf2Key([]byte(password), salt, defaultIterations, keyLen)
	return fmt.Sprintf("pbkdf2$sha256$%d$%s$%s",
		defaultIterations,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(dk),
	), nil
}

// VerifyPassword checks a plaintext password against a stored hash.
// Returns false on any mismatch or parse error (never returns an error to
// prevent timing oracle leakage through error branching).
func VerifyPassword(password, stored string) bool {
	parts := strings.SplitN(stored, "$", 5)
	if len(parts) != 5 || parts[0] != "pbkdf2" || parts[1] != "sha256" {
		return false
	}
	iters, err := strconv.Atoi(parts[2])
	if err != nil || iters <= 0 {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[3])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false
	}
	got := pbkdf2Key([]byte(password), salt, iters, len(want))
	// Constant-time comparison to prevent timing attacks.
	return hmac.Equal(got, want)
}

// HashPIN creates a PBKDF2-SHA256 hash for a short numeric PIN.
// Uses the same format as HashPassword so VerifyPassword works for PINs too.
func HashPIN(pin string) (string, error) {
	return HashPassword(pin)
}

// VerifyPIN checks a plaintext PIN against a stored hash.
func VerifyPIN(pin, stored string) bool {
	return VerifyPassword(pin, stored)
}

// ErrInvalidHash is returned when a stored hash has an unrecognised format.
var ErrInvalidHash = errors.New("crypto: unrecognised hash format")

// pbkdf2Key is a pure-Go PBKDF2 implementation using HMAC-SHA256 as the PRF.
// This is the standard algorithm described in RFC 2898 §5.2.
func pbkdf2Key(password, salt []byte, iter, keyLen int) []byte {
	hashLen := sha256.Size
	numBlocks := (keyLen + hashLen - 1) / hashLen

	prf := func(in []byte) []byte {
		mac := hmac.New(sha256.New, password)
		mac.Write(in)
		return mac.Sum(nil)
	}

	dk := make([]byte, 0, numBlocks*hashLen)
	buf := make([]byte, len(salt)+4)
	copy(buf, salt)

	for block := 1; block <= numBlocks; block++ {
		binary.BigEndian.PutUint32(buf[len(salt):], uint32(block))
		u := prf(buf)
		t := make([]byte, len(u))
		copy(t, u)
		for n := 2; n <= iter; n++ {
			u = prf(u)
			for x := range t {
				t[x] ^= u[x]
			}
		}
		dk = append(dk, t...)
	}
	return dk[:keyLen]
}
