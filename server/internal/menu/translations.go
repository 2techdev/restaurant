package menu

import "encoding/json"

// MarshalTranslations serialises a Translations map for INSERT/UPDATE binding.
// Returns "{}" when the map is nil/empty so the JSONB column never sees NULL
// — keeps SELECT scans simple (always parses to a non-nil map).
func MarshalTranslations(t Translations) []byte {
	if len(t) == 0 {
		return []byte("{}")
	}
	b, err := json.Marshal(t)
	if err != nil || len(b) == 0 {
		return []byte("{}")
	}
	return b
}

// ScanTranslations parses a JSONB column value (received as []byte) back into
// a Translations map. Empty / invalid input yields an empty (non-nil) map.
func ScanTranslations(raw []byte) Translations {
	if len(raw) == 0 {
		return Translations{}
	}
	var t Translations
	if err := json.Unmarshal(raw, &t); err != nil || t == nil {
		return Translations{}
	}
	return t
}
