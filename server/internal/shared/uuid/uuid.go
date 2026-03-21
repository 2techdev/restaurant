// Package uuid provides a minimal UUID v4 generator using only crypto/rand.
// This avoids the github.com/google/uuid dependency while producing standards-
// compliant RFC 4122 version 4 (random) UUIDs.
package uuid

import (
	"crypto/rand"
	"fmt"
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
