package uuid

import (
	"regexp"
	"testing"
)

var uuidRegex = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)

func TestNew_Format(t *testing.T) {
	for i := 0; i < 100; i++ {
		id := New()
		if !uuidRegex.MatchString(id) {
			t.Errorf("UUID %q does not match RFC 4122 v4 format", id)
		}
	}
}

func TestNew_Uniqueness(t *testing.T) {
	seen := make(map[string]struct{}, 1000)
	for i := 0; i < 1000; i++ {
		id := New()
		if _, dup := seen[id]; dup {
			t.Fatalf("duplicate UUID generated: %s", id)
		}
		seen[id] = struct{}{}
	}
}

func TestNew_Version4Bits(t *testing.T) {
	id := New()
	// Position 14 (0-indexed) is the version nibble — must be '4'.
	if id[14] != '4' {
		t.Errorf("expected version nibble '4', got %c in %s", id[14], id)
	}
	// Position 19 is the variant nibble — must be 8, 9, a, or b.
	v := id[19]
	if v != '8' && v != '9' && v != 'a' && v != 'b' {
		t.Errorf("expected variant nibble in {8,9,a,b}, got %c in %s", v, id)
	}
}

func TestNew_Length(t *testing.T) {
	id := New()
	// UUID v4 string: 32 hex + 4 dashes = 36 chars
	if len(id) != 36 {
		t.Errorf("expected UUID length 36, got %d: %s", len(id), id)
	}
}

func TestNew_HyphensAtCorrectPositions(t *testing.T) {
	id := New()
	// Hyphens at positions 8, 13, 18, 23
	for _, pos := range []int{8, 13, 18, 23} {
		if id[pos] != '-' {
			t.Errorf("expected hyphen at position %d, got %c in %s", pos, id[pos], id)
		}
	}
}
