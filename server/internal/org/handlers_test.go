package org

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/gastrocore/server/internal/shared/middleware"
)

// ─────────────────────────────────────────────────────────────
// Test helpers
// ─────────────────────────────────────────────────────────────

const (
	testOrgID    = "11111111-1111-4111-8111-111111111111"
	testUserID   = "22222222-2222-4222-8222-222222222222"
	testTenantA  = "33333333-3333-4333-8333-333333333333"
	testTenantB  = "44444444-4444-4444-8444-444444444444"
	testProductA = "55555555-5555-4555-8555-555555555555"
)

func withAuth(r *http.Request, userID, role string) *http.Request {
	ctx := r.Context()
	ctx = context.WithValue(ctx, middleware.ContextKeyUserID, userID)
	if role != "" {
		ctx = context.WithValue(ctx, middleware.ContextKeyRole, role)
	}
	return r.WithContext(ctx)
}

func decodeJSON(t *testing.T, w *httptest.ResponseRecorder, dst any) {
	t.Helper()
	if err := json.NewDecoder(w.Body).Decode(dst); err != nil {
		t.Fatalf("decode response: %v (body=%s)", err, w.Body.String())
	}
}

func assertCode(t *testing.T, w *httptest.ResponseRecorder, want int) {
	t.Helper()
	if w.Code != want {
		t.Fatalf("want HTTP %d, got %d body=%s", want, w.Code, w.Body.String())
	}
}

func assertErrorJSON(t *testing.T, w *httptest.ResponseRecorder, code string) {
	t.Helper()
	var body map[string]any
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("decode error body: %v", err)
	}
	if body["code"] != code {
		t.Errorf("want error code %q, got %v body=%v", code, body["code"], body)
	}
}

// expectResolveUser primes the resolveUser DB query.
func expectResolveUser(mock sqlmock.Sqlmock, userID, orgID, orgRole string) {
	rows := sqlmock.NewRows([]string{"organization_id", "org_role"})
	if orgID == "" && orgRole == "" {
		rows = rows.AddRow(nil, nil)
	} else if orgID == "" {
		rows = rows.AddRow(nil, orgRole)
	} else if orgRole == "" {
		rows = rows.AddRow(orgID, nil)
	} else {
		rows = rows.AddRow(orgID, orgRole)
	}
	mock.ExpectQuery("SELECT organization_id::text, org_role").
		WithArgs(userID).
		WillReturnRows(rows)
}

// ─────────────────────────────────────────────────────────────
// Auth — forbidden cases
// ─────────────────────────────────────────────────────────────

func TestAuthorize_NoUserID(t *testing.T) {
	db, _, _ := sqlmock.New()
	defer db.Close()
	m := &Module{db: db}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/org/"+testOrgID+"/restaurants", nil)
	req.SetPathValue("orgId", testOrgID)
	w := httptest.NewRecorder()
	m.handleListRestaurants(w, req)
	assertCode(t, w, http.StatusUnauthorized)
	assertErrorJSON(t, w, "UNAUTHORIZED")
}

func TestAuthorize_OrgMismatch(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()
	m := &Module{db: db}

	otherOrg := "99999999-9999-4999-8999-999999999999"
	expectResolveUser(mock, testUserID, otherOrg, RoleHQAdmin)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/org/"+testOrgID+"/restaurants", nil)
	req.SetPathValue("orgId", testOrgID)
	req = withAuth(req, testUserID, RoleHQAdmin)
	w := httptest.NewRecorder()
	m.handleListRestaurants(w, req)
	assertCode(t, w, http.StatusForbidden)
	assertErrorJSON(t, w, "ORG_MISMATCH")
}

func TestAuthorize_InsufficientRole(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()
	m := &Module{db: db}

	expectResolveUser(mock, testUserID, testOrgID, RoleRestaurantManager)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/org/"+testOrgID+"/restaurants", nil)
	req.SetPathValue("orgId", testOrgID)
	req = withAuth(req, testUserID, RoleRestaurantManager)
	w := httptest.NewRecorder()
	m.handleListRestaurants(w, req)
	assertCode(t, w, http.StatusForbidden)
	assertErrorJSON(t, w, "FORBIDDEN")
}

// ─────────────────────────────────────────────────────────────
// /me
// ─────────────────────────────────────────────────────────────

func TestHandleMe_NoOrg(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()
	m := &Module{db: db}

	mock.ExpectQuery("SELECT organization_id::text, org_role, COALESCE\\(name").
		WithArgs(testUserID).
		WillReturnRows(sqlmock.NewRows([]string{"organization_id", "org_role", "name"}).
			AddRow(nil, nil, "Mario"))

	req := httptest.NewRequest(http.MethodGet, "/api/v1/org/me", nil)
	req = withAuth(req, testUserID, "")
	w := httptest.NewRecorder()
	m.handleMe(w, req)
	assertCode(t, w, http.StatusOK)
	var body map[string]any
	decodeJSON(t, w, &body)
	if body["organization"] != nil {
		t.Errorf("expected organization=nil, got %v", body["organization"])
	}
	if body["name"] != "Mario" {
		t.Errorf("expected name=Mario, got %v", body["name"])
	}
}

// ─────────────────────────────────────────────────────────────
// Policies — happy + lock check
// ─────────────────────────────────────────────────────────────

func TestHandleCreatePolicy_HappyPath(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()
	m := &Module{db: db}

	expectResolveUser(mock, testUserID, testOrgID, RoleHQAdmin)
	mock.ExpectExec("INSERT INTO menu_policies").
		WithArgs(sqlmock.AnyArg(), testOrgID, testProductA, LockTypeFullyLocked, true, true).
		WillReturnResult(sqlmock.NewResult(1, 1))

	body := strings.NewReader(`{"product_id":"` + testProductA + `","lock_type":"FULLY_LOCKED"}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/org/"+testOrgID+"/policies", body)
	req.SetPathValue("orgId", testOrgID)
	req = withAuth(req, testUserID, RoleHQAdmin)
	w := httptest.NewRecorder()
	m.handleCreatePolicy(w, req)
	assertCode(t, w, http.StatusCreated)
}

func TestHandleCreatePolicy_BadLockType(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()
	m := &Module{db: db}

	expectResolveUser(mock, testUserID, testOrgID, RoleHQAdmin)

	body := strings.NewReader(`{"product_id":"` + testProductA + `","lock_type":"BANANA"}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/org/"+testOrgID+"/policies", body)
	req.SetPathValue("orgId", testOrgID)
	req = withAuth(req, testUserID, RoleHQAdmin)
	w := httptest.NewRecorder()
	m.handleCreatePolicy(w, req)
	assertCode(t, w, http.StatusBadRequest)
	assertErrorJSON(t, w, "VALIDATION_ERROR")
}

// ─────────────────────────────────────────────────────────────
// CheckMutation — lock semantics
// ─────────────────────────────────────────────────────────────

func TestCheckMutation_FullyLocked(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()

	mock.ExpectQuery("SELECT organization_id::text, is_master FROM organization_memberships").
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{"organization_id", "is_master"}).AddRow(testOrgID, false))
	mock.ExpectQuery("SELECT lock_type, allow_local_disable FROM menu_policies").
		WithArgs(testOrgID, testProductA).
		WillReturnRows(sqlmock.NewRows([]string{"lock_type", "allow_local_disable"}).AddRow(LockTypeFullyLocked, true))

	err := CheckMutation(context.Background(), db, Mutation{
		ProductID: testProductA, TenantID: testTenantA, ChangePrice: true,
	})
	var le LockedError
	if err == nil {
		t.Fatal("expected LockedError, got nil")
	}
	if !asLocked(err, &le) {
		t.Fatalf("expected LockedError, got %T %v", err, err)
	}
	if le.LockType != LockTypeFullyLocked {
		t.Errorf("expected lock_type=FULLY_LOCKED, got %s", le.LockType)
	}
}

func TestCheckMutation_PriceLocked_PriceChange_Blocked(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()

	mock.ExpectQuery("SELECT organization_id::text, is_master FROM organization_memberships").
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{"organization_id", "is_master"}).AddRow(testOrgID, false))
	mock.ExpectQuery("SELECT lock_type, allow_local_disable FROM menu_policies").
		WithArgs(testOrgID, testProductA).
		WillReturnRows(sqlmock.NewRows([]string{"lock_type", "allow_local_disable"}).AddRow(LockTypePriceLocked, true))

	err := CheckMutation(context.Background(), db, Mutation{
		ProductID: testProductA, TenantID: testTenantA, ChangePrice: true,
	})
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	var le LockedError
	if !asLocked(err, &le) || le.LockType != LockTypePriceLocked {
		t.Errorf("expected PRICE_LOCKED LockedError, got %v", err)
	}
}

func TestCheckMutation_PriceLocked_OtherFields_Allowed(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()

	mock.ExpectQuery("SELECT organization_id::text, is_master FROM organization_memberships").
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{"organization_id", "is_master"}).AddRow(testOrgID, false))
	mock.ExpectQuery("SELECT lock_type, allow_local_disable FROM menu_policies").
		WithArgs(testOrgID, testProductA).
		WillReturnRows(sqlmock.NewRows([]string{"lock_type", "allow_local_disable"}).AddRow(LockTypePriceLocked, true))

	err := CheckMutation(context.Background(), db, Mutation{
		ProductID: testProductA, TenantID: testTenantA, ChangeOther: true,
	})
	if err != nil {
		t.Errorf("expected nil for non-price change under PRICE_LOCKED, got %v", err)
	}
}

func TestCheckMutation_Flexible_AllowsAll(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()

	mock.ExpectQuery("SELECT organization_id::text, is_master FROM organization_memberships").
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{"organization_id", "is_master"}).AddRow(testOrgID, false))
	mock.ExpectQuery("SELECT lock_type, allow_local_disable FROM menu_policies").
		WithArgs(testOrgID, testProductA).
		WillReturnRows(sqlmock.NewRows([]string{"lock_type", "allow_local_disable"}).AddRow(LockTypeFlexible, true))

	if err := CheckMutation(context.Background(), db, Mutation{
		ProductID: testProductA, TenantID: testTenantA, ChangePrice: true, Delete: true,
	}); err != nil {
		t.Errorf("expected nil for FLEXIBLE, got %v", err)
	}
}

func TestCheckMutation_NoOrgMembership_Pass(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()

	mock.ExpectQuery("SELECT organization_id::text, is_master FROM organization_memberships").
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{"organization_id", "is_master"})) // empty result

	if err := CheckMutation(context.Background(), db, Mutation{
		ProductID: testProductA, TenantID: testTenantA, ChangePrice: true,
	}); err != nil {
		t.Errorf("expected nil when tenant has no org, got %v", err)
	}
}

func TestCheckMutation_MasterTenant_Skipped(t *testing.T) {
	db, mock, _ := sqlmock.New()
	defer db.Close()

	// Master tenant — locks should NOT apply, even when a policy exists.
	mock.ExpectQuery("SELECT organization_id::text, is_master FROM organization_memberships").
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{"organization_id", "is_master"}).AddRow(testOrgID, true))

	if err := CheckMutation(context.Background(), db, Mutation{
		ProductID: testProductA, TenantID: testTenantA, ChangePrice: true, Delete: true,
	}); err != nil {
		t.Errorf("expected nil for master tenant, got %v", err)
	}
}

// asLocked is a tiny errors.As helper specialized for LockedError.
func asLocked(err error, target *LockedError) bool {
	if le, ok := err.(LockedError); ok {
		*target = le
		return true
	}
	return false
}

// ─────────────────────────────────────────────────────────────
// Merge inheritance — pure-function tests, no DB
// ─────────────────────────────────────────────────────────────

func TestMergeMasterIntoLocal_FullyLocked_OverridesLocal(t *testing.T) {
	master := MenuSnapshot{
		Version: 5,
		Products: []SnapshotProduct{
			{ID: testProductA, CategoryID: "cat", Name: "Master", Price: 1500, IsActive: true},
		},
	}
	local := MenuSnapshot{
		Products: []SnapshotProduct{
			{ID: testProductA, CategoryID: "cat", Name: "Local", Price: 999, IsActive: true},
		},
	}
	policies := map[string]MenuPolicy{
		testProductA: {ProductID: testProductA, LockType: LockTypeFullyLocked},
	}
	out := mergeMasterIntoLocal(master, local, policies)
	if len(out.Products) != 1 {
		t.Fatalf("expected 1 product, got %d", len(out.Products))
	}
	p := out.Products[0]
	if p.Name != "Master" || p.Price != 1500 {
		t.Errorf("expected master to win for FULLY_LOCKED, got %+v", p)
	}
	if !p.IsMaster || p.LockType != LockTypeFullyLocked {
		t.Errorf("expected IsMaster=true and lock_type set, got %+v", p)
	}
}

func TestMergeMasterIntoLocal_PriceLocked_KeepsLocalCosmetics(t *testing.T) {
	master := MenuSnapshot{
		Products: []SnapshotProduct{
			{ID: testProductA, CategoryID: "cat", Name: "MasterName", Price: 2000, IsActive: true, TaxGroup: "vat19"},
		},
	}
	descLocal := "Yerel açıklama"
	local := MenuSnapshot{
		Products: []SnapshotProduct{
			{ID: testProductA, CategoryID: "cat", Name: "LocalName", Description: &descLocal, Price: 100, IsActive: true},
		},
	}
	policies := map[string]MenuPolicy{
		testProductA: {ProductID: testProductA, LockType: LockTypePriceLocked},
	}
	out := mergeMasterIntoLocal(master, local, policies)
	p := out.Products[0]
	if p.Price != 2000 || p.TaxGroup != "vat19" {
		t.Errorf("expected master price/tax to win for PRICE_LOCKED, got %+v", p)
	}
	if p.Name != "LocalName" {
		t.Errorf("expected local name to be preserved for PRICE_LOCKED, got %s", p.Name)
	}
	if p.Description == nil || *p.Description != descLocal {
		t.Errorf("expected local description preserved, got %v", p.Description)
	}
}

func TestMergeMasterIntoLocal_Flexible_LocalWins(t *testing.T) {
	master := MenuSnapshot{
		Products: []SnapshotProduct{
			{ID: testProductA, CategoryID: "cat", Name: "Master", Price: 5000, IsActive: true},
		},
	}
	local := MenuSnapshot{
		Products: []SnapshotProduct{
			{ID: testProductA, CategoryID: "cat", Name: "LocalRebrand", Price: 4500, IsActive: true},
		},
	}
	policies := map[string]MenuPolicy{
		testProductA: {ProductID: testProductA, LockType: LockTypeFlexible},
	}
	out := mergeMasterIntoLocal(master, local, policies)
	p := out.Products[0]
	if p.Name != "LocalRebrand" || p.Price != 4500 {
		t.Errorf("expected local override for FLEXIBLE, got %+v", p)
	}
}

func TestMergeMasterIntoLocal_LocalOnlyProduct_Preserved(t *testing.T) {
	otherID := "66666666-6666-4666-8666-666666666666"
	master := MenuSnapshot{Products: []SnapshotProduct{}}
	local := MenuSnapshot{
		Products: []SnapshotProduct{
			{ID: otherID, CategoryID: "cat", Name: "LocalOnly", Price: 700, IsActive: true},
		},
	}
	out := mergeMasterIntoLocal(master, local, map[string]MenuPolicy{})
	if len(out.Products) != 1 {
		t.Fatalf("expected 1 product, got %d", len(out.Products))
	}
	if !out.Products[0].LocalOnly {
		t.Errorf("expected LocalOnly=true, got %+v", out.Products[0])
	}
}
