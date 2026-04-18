// Package uuid provides a minimal UUID v4 generator using only crypto/rand.
// This avoids the github.com/google/uuid dependency while producing standards-
// compliant RFC 4122 version 4 (random) UUIDs.
package uuid

import (
	"crypto/rand"
	"fmt"
	"regexp"
)

// New generates a random UUID v4 string.
// Panics if the OS CSPRNG is unavailable (should never happen in practice).
func New() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic("uuid: crypto/rand unavailable: " + err.Error())
	}
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant bits (RFC 4122)
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// uuidPattern matches canonical 8-4-4-4-12 hex UUIDs (any version).
var uuidPattern = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// IsValid reports whether s is a canonical RFC 4122 UUID string. Use as a
// pre-flight check before passing user-supplied IDs to Postgres UUID columns,
// otherwise the driver returns a generic 22P02 error that we'd rather surface
// as a client-side 400 / 401.
func IsValid(s string) bool {
	return uuidPattern.MatchString(s)
}
