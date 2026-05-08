package menu

// ETL transformations for magic-link menu import (D Strategy Aşama 1).
//
// Pure functions only — no DB, no HTTP. Each one is unit-tested in
// import_test.go.

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
)

// decimalToCents converts a Decimal-string price to int64 cents.
//
//	"12.50"  → 1250
//	"0"      → 0
//	"3"      → 300
//	"1.234"  → 123  (rounds — Reservation only uses 2 decimals)
//	""       → 0    (Reservation Decimal? null mapped to 0 cents)
//	"-5"     → error
//
// Returns error for non-numeric input or negative values.
func decimalToCents(s string) (int64, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, nil
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, fmt.Errorf("decimalToCents: invalid number %q: %w", s, err)
	}
	if f < 0 {
		return 0, fmt.Errorf("decimalToCents: negative price %q", s)
	}
	if math.IsInf(f, 0) || math.IsNaN(f) {
		return 0, fmt.Errorf("decimalToCents: non-finite %q", s)
	}
	// Round to nearest cent. f is non-negative so floor(f*100+0.5) is fine.
	return int64(math.Floor(f*100 + 0.5)), nil
}

// nameToTranslations wraps a single string into a {"de": name} JSONB blob.
// POS schema uses name_translations JSONB; Reservation has only flat name.
// Default locale = 'de' (Swiss pilot). Empty input → empty object {}.
func nameToTranslations(name string) []byte {
	name = strings.TrimSpace(name)
	if name == "" {
		return []byte("{}")
	}
	b, err := json.Marshal(map[string]string{"de": name})
	if err != nil {
		// json.Marshal of map[string]string never fails for valid UTF-8.
		return []byte("{}")
	}
	return b
}

// normalizeImageURL converts a Reservation MenuItem.image value into an
// absolute URL the POS terminal can fetch.
//
//	""                                → ""
//	"https://cdn.2hub.ch/x/y.jpg"     → as-is (R2 public, ~57% of items)
//	"http://example.com/x.jpg"        → as-is
//	"/uploads/palazzo/x.png"          → "<fallbackBase>/uploads/palazzo/x.png"
//	"uploads/x.png"                   → "<fallbackBase>/uploads/x.png" (defensive)
//	"data:image/..."                  → "" (not supported)
//
// fallbackBase is typically "https://gastro.2hub.ch" (env-driven).
// Trailing slash on fallbackBase is tolerated.
func normalizeImageURL(image, fallbackBase string) string {
	image = strings.TrimSpace(image)
	if image == "" {
		return ""
	}
	if strings.HasPrefix(image, "https://") || strings.HasPrefix(image, "http://") {
		return image
	}
	if strings.HasPrefix(image, "data:") {
		return ""
	}
	base := strings.TrimRight(strings.TrimSpace(fallbackBase), "/")
	if base == "" {
		// No way to build absolute URL; better to drop than to write a relative
		// path that POS terminals can't resolve.
		return ""
	}
	if !strings.HasPrefix(image, "/") {
		image = "/" + image
	}
	return base + image
}

// translateExtraGroupSelectionType maps Reservation ExtraType (SINGLE/MULTI)
// to POS modifier_groups.selection_type ('single'/'multiple'). Defensive
// fallback to 'single' for unknown values.
func translateExtraGroupSelectionType(t string) string {
	switch strings.ToUpper(strings.TrimSpace(t)) {
	case "MULTI":
		return "multiple"
	case "SINGLE":
		return "single"
	default:
		return "single"
	}
}

// snapshotEnvelope is the wire format returned by Reservation
// /api/gastrocore/menu/by-token/[token]. Mirrors menu-io IR plus an envelope.
type snapshotEnvelope struct {
	SchemaVersion int            `json:"schemaVersion"`
	GeneratedAt   string         `json:"generatedAt"`
	Restaurant    snapRestaurant `json:"restaurant"`
	Snapshot      snapBody       `json:"snapshot"`
}

type snapRestaurant struct {
	ID   string `json:"id"`
	Slug string `json:"slug"`
}

type snapBody struct {
	Categories   []snapImportCategory `json:"categories"`
	Items        []snapImportItem     `json:"items"`
	ExtraGroups  []snapImportExtraGrp `json:"extraGroups"`
	ExtraOptions []snapImportExtraOpt `json:"extraOptions"`
	ExtraLinks   []snapImportExtraLnk `json:"extraLinks"`
}

type snapImportCategory struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	SortOrder int    `json:"sortOrder"`
	IsActive  bool   `json:"isActive"`
}

type snapImportItem struct {
	ID            string  `json:"id"`
	CategoryID    string  `json:"categoryId"`
	CategoryName  string  `json:"categoryName"`
	Name          string  `json:"name"`
	Description   *string `json:"description"`
	Image         *string `json:"image"`
	PriceStandard string  `json:"priceStandard"`
	PriceTakeaway *string `json:"priceTakeaway"`
	PriceDelivery *string `json:"priceDelivery"`
	IsAvailable   bool    `json:"isAvailable"`
	IsPopular     bool    `json:"isPopular"`
	SortOrder     int     `json:"sortOrder"`
}

type snapImportExtraGrp struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Type       string `json:"type"` // SINGLE | MULTI
	IsRequired bool   `json:"isRequired"`
	MinSelect  int    `json:"minSelect"`
	MaxSelect  int    `json:"maxSelect"`
	SortOrder  int    `json:"sortOrder"`
}

type snapImportExtraOpt struct {
	ID         string `json:"id"`
	GroupID    string `json:"groupId"`
	Name       string `json:"name"`
	PriceExtra string `json:"priceExtra"`
	IsDefault  bool   `json:"isDefault"`
	SortOrder  int    `json:"sortOrder"`
}

type snapImportExtraLnk struct {
	ExtraGroupName     string  `json:"extraGroupName"`
	Target             string  `json:"target"` // CATEGORY | ITEM
	TargetCategoryName *string `json:"targetCategoryName"`
	TargetItemName     *string `json:"targetItemName"`
}

// validateSnapshot performs structural checks before any DB work. Returns
// nil for a usable snapshot, or a wrapped error describing what's wrong.
func validateSnapshot(env *snapshotEnvelope) error {
	if env == nil {
		return errors.New("snapshot is nil")
	}
	if env.SchemaVersion < 1 {
		return fmt.Errorf("snapshot: unsupported schemaVersion %d", env.SchemaVersion)
	}
	if env.Restaurant.ID == "" || env.Restaurant.Slug == "" {
		return errors.New("snapshot: restaurant.id and restaurant.slug are required")
	}
	catIDs := make(map[string]bool, len(env.Snapshot.Categories))
	for _, c := range env.Snapshot.Categories {
		if c.ID == "" || c.Name == "" {
			return fmt.Errorf("snapshot: category with empty id/name: id=%q name=%q", c.ID, c.Name)
		}
		catIDs[c.ID] = true
	}
	for _, it := range env.Snapshot.Items {
		if it.ID == "" || it.Name == "" {
			return fmt.Errorf("snapshot: item with empty id/name: id=%q name=%q", it.ID, it.Name)
		}
		if it.CategoryID == "" || !catIDs[it.CategoryID] {
			return fmt.Errorf("snapshot: item %q references unknown category %q", it.Name, it.CategoryID)
		}
	}
	return nil
}
