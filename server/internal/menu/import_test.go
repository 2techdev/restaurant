package menu

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"

	"github.com/gastrocore/server/internal/shared/middleware"
)

// ---------------------------------------------------------------------------
// Test helpers (used by handler & apply tests below)
// ---------------------------------------------------------------------------

var errBoom = errors.New("boom")

func withTenantAndRole(ctx context.Context, tenantID, role string) context.Context {
	ctx = context.WithValue(ctx, middleware.ContextKeyTenantID, tenantID)
	ctx = context.WithValue(ctx, middleware.ContextKeyRole, role)
	return ctx
}

func withAdminTenant(ctx context.Context, tenantID string) context.Context {
	return withTenantAndRole(ctx, tenantID, "admin")
}

// ---------------------------------------------------------------------------
// ETL: decimalToCents
// ---------------------------------------------------------------------------

func TestDecimalToCents(t *testing.T) {
	cases := []struct {
		in        string
		want      int64
		wantError bool
	}{
		{"12.50", 1250, false},
		{"0", 0, false},
		{"3", 300, false},
		{"3.00", 300, false},
		{"0.05", 5, false},
		{"0.99", 99, false},
		{"100", 10000, false},
		{"", 0, false},   // null Decimal mapped to 0
		{"  4.20 ", 420, false},
		{"1.234", 123, false}, // rounds (not strictly truncates)
		{"1.235", 124, false}, // half-up rounding
		{"-5", 0, true},
		{"abc", 0, true},
	}
	for _, c := range cases {
		got, err := decimalToCents(c.in)
		if c.wantError {
			if err == nil {
				t.Errorf("decimalToCents(%q): expected error, got %d", c.in, got)
			}
			continue
		}
		if err != nil {
			t.Errorf("decimalToCents(%q): unexpected error: %v", c.in, err)
			continue
		}
		if got != c.want {
			t.Errorf("decimalToCents(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

// ---------------------------------------------------------------------------
// ETL: nameToTranslations
// ---------------------------------------------------------------------------

func TestNameToTranslations(t *testing.T) {
	got := string(nameToTranslations("Margherita"))
	if got != `{"de":"Margherita"}` {
		t.Errorf("nameToTranslations: got %q", got)
	}
	if string(nameToTranslations("")) != "{}" {
		t.Error("empty name should yield {}")
	}
	if string(nameToTranslations("   ")) != "{}" {
		t.Error("whitespace name should yield {}")
	}
	// Unicode safe — Swiss umlauts.
	got = string(nameToTranslations("Käseschnitte"))
	var parsed map[string]string
	if err := json.Unmarshal([]byte(got), &parsed); err != nil {
		t.Fatalf("invalid JSON: %v (raw=%s)", err, got)
	}
	if parsed["de"] != "Käseschnitte" {
		t.Errorf("got %q, want Käseschnitte", parsed["de"])
	}
}

// ---------------------------------------------------------------------------
// ETL: normalizeImageURL
// ---------------------------------------------------------------------------

func TestNormalizeImageURL(t *testing.T) {
	cases := []struct {
		image, base, want string
	}{
		{"", "https://gastro.2hub.ch", ""},
		{"https://cdn.2hub.ch/img/x.jpg", "", "https://cdn.2hub.ch/img/x.jpg"},
		{"http://example.com/x.jpg", "https://gastro.2hub.ch", "http://example.com/x.jpg"},
		{"/uploads/palazzo/x.png", "https://gastro.2hub.ch", "https://gastro.2hub.ch/uploads/palazzo/x.png"},
		{"/uploads/palazzo/x.png", "https://gastro.2hub.ch/", "https://gastro.2hub.ch/uploads/palazzo/x.png"}, // trailing slash tolerated
		{"uploads/x.png", "https://gastro.2hub.ch", "https://gastro.2hub.ch/uploads/x.png"},                  // missing leading slash
		{"/uploads/x.png", "", ""},                                                                            // base unset → drop
		{"data:image/png;base64,iVBOR...", "https://gastro.2hub.ch", ""},                                      // data: refused
	}
	for _, c := range cases {
		got := normalizeImageURL(c.image, c.base)
		if got != c.want {
			t.Errorf("normalizeImageURL(%q, %q) = %q, want %q", c.image, c.base, got, c.want)
		}
	}
}

// ---------------------------------------------------------------------------
// ETL: translateExtraGroupSelectionType
// ---------------------------------------------------------------------------

func TestTranslateExtraGroupSelectionType(t *testing.T) {
	cases := []struct{ in, want string }{
		{"SINGLE", "single"},
		{"MULTI", "multiple"},
		{"single", "single"},
		{"multi", "multiple"},
		{"", "single"},
		{"unknown", "single"},
	}
	for _, c := range cases {
		got := translateExtraGroupSelectionType(c.in)
		if got != c.want {
			t.Errorf("translateExtraGroupSelectionType(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// ---------------------------------------------------------------------------
// validateSnapshot
// ---------------------------------------------------------------------------

func TestValidateSnapshot(t *testing.T) {
	if err := validateSnapshot(nil); err == nil {
		t.Error("nil envelope should error")
	}
	bad := &snapshotEnvelope{SchemaVersion: 0}
	if err := validateSnapshot(bad); err == nil {
		t.Error("schemaVersion=0 should error")
	}
	noRest := &snapshotEnvelope{SchemaVersion: 1}
	if err := validateSnapshot(noRest); err == nil {
		t.Error("missing restaurant should error")
	}
	orphanItem := &snapshotEnvelope{
		SchemaVersion: 1,
		Restaurant:    snapRestaurant{ID: "r1", Slug: "demo"},
		Snapshot: snapBody{
			Categories: []snapImportCategory{{ID: "c1", Name: "Drinks"}},
			Items:      []snapImportItem{{ID: "i1", Name: "Coke", CategoryID: "MISSING", PriceStandard: "3"}},
		},
	}
	if err := validateSnapshot(orphanItem); err == nil {
		t.Error("orphaned item should error")
	}
	good := &snapshotEnvelope{
		SchemaVersion: 1,
		Restaurant:    snapRestaurant{ID: "r1", Slug: "demo"},
		Snapshot: snapBody{
			Categories: []snapImportCategory{{ID: "c1", Name: "Drinks"}},
			Items:      []snapImportItem{{ID: "i1", Name: "Coke", CategoryID: "c1", PriceStandard: "3"}},
		},
	}
	if err := validateSnapshot(good); err != nil {
		t.Errorf("good snapshot should validate: %v", err)
	}
}

// ---------------------------------------------------------------------------
// Diff: NEW / UPDATE / UNCHANGED / SKIP
// ---------------------------------------------------------------------------

func TestComputeDiff(t *testing.T) {
	desc1 := "Klassisch"
	env := &snapshotEnvelope{
		SchemaVersion: 1,
		Restaurant:    snapRestaurant{ID: "r1", Slug: "demo"},
		Snapshot: snapBody{
			Categories: []snapImportCategory{
				{ID: "cat-new", Name: "Pizza", SortOrder: 1, IsActive: true},
				{ID: "cat-existing-unchanged", Name: "Drinks", SortOrder: 2, IsActive: true},
				{ID: "cat-existing-updated", Name: "Salad", SortOrder: 3, IsActive: true},
			},
			Items: []snapImportItem{
				{ID: "p-new", CategoryID: "cat-new", Name: "Margherita", PriceStandard: "12.50", IsAvailable: true, SortOrder: 1, Description: &desc1},
				{ID: "p-unchanged", CategoryID: "cat-existing-unchanged", Name: "Cola", PriceStandard: "3.00", IsAvailable: true, SortOrder: 1},
				{ID: "p-bad", CategoryID: "cat-new", Name: "Bad", PriceStandard: "abc"}, // forces ERROR row
			},
			ExtraGroups: []snapImportExtraGrp{
				{ID: "eg-1", Name: "Toppings", Type: "MULTI"},
			},
			ExtraOptions: []snapImportExtraOpt{
				{ID: "eo-1", GroupID: "eg-1", Name: "Mushrooms", PriceExtra: "1.50"},
			},
		},
	}

	existing := map[MappingKey]existingMapping{
		{EntityType: "category", RemoteID: "cat-existing-unchanged"}: {LocalID: "u-cat1", Name: "Drinks", SortOrder: 2, IsActive: true},
		{EntityType: "category", RemoteID: "cat-existing-updated"}:   {LocalID: "u-cat2", Name: "OldName", SortOrder: 99, IsActive: false},
		{EntityType: "product", RemoteID: "p-unchanged"}:             {LocalID: "u-p1", Name: "Cola", PriceCents: 300, SortOrder: 1, IsActive: true, Image: ""},
	}

	preview, err := computeDiff(env, existing, "https://gastro.2hub.ch")
	if err != nil {
		t.Fatalf("computeDiff: %v", err)
	}
	if preview.Summary.CategoriesNew != 1 || preview.Summary.CategoriesUpdated != 1 || preview.Summary.CategoriesUnchanged != 1 {
		t.Errorf("category counts: %+v", preview.Summary)
	}
	if preview.Summary.ProductsNew != 1 || preview.Summary.ProductsUnchanged != 1 || preview.Summary.Errors != 1 {
		t.Errorf("product counts: %+v", preview.Summary)
	}
	if preview.Summary.ModifiersSkipped != 2 {
		t.Errorf("expected 2 modifier rows skipped, got %d", preview.Summary.ModifiersSkipped)
	}

	// Spot-check action assignments.
	for _, c := range preview.Categories {
		switch c.RemoteID {
		case "cat-new":
			if c.Action != DiffNew {
				t.Errorf("cat-new: %s", c.Action)
			}
		case "cat-existing-unchanged":
			if c.Action != DiffUnchanged {
				t.Errorf("cat-existing-unchanged: %s", c.Action)
			}
		case "cat-existing-updated":
			if c.Action != DiffUpdate {
				t.Errorf("cat-existing-updated: %s", c.Action)
			}
		}
	}
	for _, m := range preview.Modifiers {
		if m.Action != DiffSkip || m.Reason != "SKIP_MODIFIER_CRUD_MISSING" {
			t.Errorf("modifier %s: action=%s reason=%s", m.RemoteID, m.Action, m.Reason)
		}
	}
}

// ---------------------------------------------------------------------------
// HMAC client signature
// ---------------------------------------------------------------------------

func TestSignatureMatchesIndependentHMAC(t *testing.T) {
	c := &GastroHubClient{secret: "secret-key-for-hmac-test"}
	got := c.signature("GET", "/api/gastrocore/menu/by-token/M7K-9PQ", nil)
	mac := hmac.New(sha256.New, []byte(c.secret))
	mac.Write([]byte("GET\n/api/gastrocore/menu/by-token/M7K-9PQ\n"))
	want := hex.EncodeToString(mac.Sum(nil))
	if got != want {
		t.Errorf("signature mismatch:\n  got=%s\n want=%s", got, want)
	}
}

// ---------------------------------------------------------------------------
// fetchSnapshotByToken: status code mapping (404, 410, 429, 200)
// ---------------------------------------------------------------------------

func TestFetchSnapshotByTokenStatusMapping(t *testing.T) {
	cases := []struct {
		name       string
		status     int
		body       string
		wantStatus int
		wantCode   string
		wantOK     bool
	}{
		{"not found", http.StatusNotFound, `{"error":"x"}`, http.StatusNotFound, "TOKEN_NOT_FOUND", false},
		{"gone", http.StatusGone, ``, http.StatusGone, "TOKEN_EXPIRED", false},
		{"rate", http.StatusTooManyRequests, ``, http.StatusTooManyRequests, "RATE_LIMITED", false},
		{"unauth", http.StatusUnauthorized, ``, http.StatusUnauthorized, "UPSTREAM_AUTH", false},
		{"500", 500, `boom`, http.StatusBadGateway, "UPSTREAM_ERROR", false},
		{"200 valid", http.StatusOK, `{"schemaVersion":1,"generatedAt":"now","restaurant":{"id":"r","slug":"s"},"snapshot":{"categories":[],"items":[]}}`, 0, "", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				// Verify header is present and well-formed.
				if !strings.HasPrefix(r.Header.Get("X-GastroCore-Signature"), "sha256=") {
					t.Errorf("missing signature header")
				}
				w.WriteHeader(c.status)
				_, _ = w.Write([]byte(c.body))
			}))
			defer srv.Close()

			client := &GastroHubClient{
				baseURL: srv.URL,
				secret:  "test-secret",
				http:    srv.Client(),
			}
			env, err := client.fetchSnapshotByToken(context.Background(), "M7K-9PQ")
			if c.wantOK {
				if err != nil {
					t.Fatalf("expected success, got error: %v", err)
				}
				if env == nil || env.Restaurant.ID != "r" {
					t.Errorf("expected envelope, got %+v", env)
				}
				return
			}
			if err == nil {
				t.Fatal("expected error, got nil")
			}
			ce, ok := err.(*ClientError)
			if !ok {
				t.Fatalf("expected *ClientError, got %T: %v", err, err)
			}
			if ce.Status != c.wantStatus {
				t.Errorf("status: got %d, want %d", ce.Status, c.wantStatus)
			}
			if ce.Code != c.wantCode {
				t.Errorf("code: got %q, want %q", ce.Code, c.wantCode)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Apply: rollback on error (sqlmock)
// ---------------------------------------------------------------------------

func TestApplyImportRollbackOnInsertFailure(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	defer db.Close()

	m := &Module{db: db}

	mock.ExpectBegin()
	// Idempotency check: empty result → Scan returns ErrNoRows → applyImport
	// proceeds normally instead of short-circuiting.
	mock.ExpectQuery("FROM menu_sync_events").
		WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "status"}))
	// loadExistingMapping: empty for both queries.
	mock.ExpectQuery("FROM external_menu_refs r").
		WithArgs("tenant-uuid").
		WillReturnRows(sqlmock.NewRows([]string{"entity_type", "remote_id", "local_id", "name", "display_order", "is_active"}))
	mock.ExpectQuery("FROM external_menu_refs r").
		WithArgs("tenant-uuid").
		WillReturnRows(sqlmock.NewRows([]string{"entity_type", "remote_id", "local_id", "name", "description", "image_path", "price", "display_order", "is_active", "category_id"}))
	// Insert categories: simulate failure on first insert → triggers rollback.
	mock.ExpectExec("INSERT INTO categories").
		WillReturnError(errBoom)
	mock.ExpectRollback()

	env := &snapshotEnvelope{
		SchemaVersion: 1,
		GeneratedAt:   "2026-05-08T10:00:00Z",
		Restaurant:    snapRestaurant{ID: "r1", Slug: "demo"},
		Snapshot: snapBody{
			Categories: []snapImportCategory{{ID: "cat-1", Name: "Pizza", SortOrder: 0, IsActive: true}},
			Items:      []snapImportItem{},
		},
	}
	_, err = m.applyImport(context.Background(), "tenant-uuid", "M7K-9PQ", env, "merge", false, "https://gastro.2hub.ch")
	if err == nil {
		t.Fatal("expected error from insert failure")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet expectations: %v", err)
	}
}

// ---------------------------------------------------------------------------
// Handler: token validation (no DB / no network needed)
// ---------------------------------------------------------------------------

func TestHandleImportFromTokenValidatesTokenShape(t *testing.T) {
	cases := []struct {
		name       string
		body       string
		wantStatus int
		wantCode   string
	}{
		{"missing token", `{}`, http.StatusBadRequest, "VALIDATION_ERROR"},
		{"bad shape", `{"token":"bad"}`, http.StatusBadRequest, "VALIDATION_ERROR"},
		{"contains I", `{"token":"M7I-9PQ"}`, http.StatusBadRequest, "VALIDATION_ERROR"},
		{"contains 0", `{"token":"M70-9PQ"}`, http.StatusBadRequest, "VALIDATION_ERROR"},
		{"contains 1", `{"token":"M71-9PQ"}`, http.StatusBadRequest, "VALIDATION_ERROR"},
		{"replace mode", `{"token":"M7K-9PQ","mode":"replace"}`, http.StatusBadRequest, "VALIDATION_ERROR"},
		{"invalid body", `not json`, http.StatusBadRequest, "INVALID_BODY"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			m := &Module{db: nil}
			req := httptest.NewRequest(http.MethodPost, "/api/v1/menu/import-from-token", bytes.NewReader([]byte(c.body)))
			req.Header.Set("Content-Type", "application/json")
			ctx := withAdminTenant(req.Context(), "tenant-x")
			req = req.WithContext(ctx)
			w := httptest.NewRecorder()
			m.handleImportFromToken(w, req)
			if w.Code != c.wantStatus {
				t.Errorf("status: got %d, want %d (body=%s)", w.Code, c.wantStatus, w.Body.String())
			}
			var body map[string]any
			if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
				t.Fatalf("decode: %v", err)
			}
			if body["code"] != c.wantCode {
				t.Errorf("code: got %v, want %s", body["code"], c.wantCode)
			}
		})
	}
}

func TestHandleImportFromTokenRejectsNonAdmin(t *testing.T) {
	m := &Module{db: nil}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/menu/import-from-token",
		bytes.NewReader([]byte(`{"token":"M7K-9PQ"}`)))
	req.Header.Set("Content-Type", "application/json")
	ctx := withTenantAndRole(req.Context(), "tenant-x", "cashier")
	req = req.WithContext(ctx)
	w := httptest.NewRecorder()
	m.handleImportFromToken(w, req)
	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403 for non-admin role, got %d (body=%s)", w.Code, w.Body.String())
	}
}

func TestHandleImportFromTokenRequiresTenant(t *testing.T) {
	m := &Module{db: nil}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/menu/import-from-token",
		bytes.NewReader([]byte(`{"token":"M7K-9PQ"}`)))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	m.handleImportFromToken(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 without tenant, got %d", w.Code)
	}
}
