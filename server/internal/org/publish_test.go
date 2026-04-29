package org

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

// TestHandlePublishMasterMenu_FanOutToAllMembers verifies the critical
// distribution path: when an HQ admin publishes the master menu, a new
// master_menu_versions row is inserted, master_menus.current_version is
// bumped, and a per-tenant menu_versions row is inserted for every member.
func TestHandlePublishMasterMenu_FanOutToAllMembers(t *testing.T) {
	db, mock, err := sqlmock.New(sqlmock.QueryMatcherOption(sqlmock.QueryMatcherRegexp))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	m := &Module{db: db}

	// Authorize: user is HQ_ADMIN of testOrgID
	expectResolveUser(mock, testUserID, testOrgID, RoleHQAdmin)

	// ensureMasterTenant: existing master tenant is testTenantA
	mock.ExpectQuery("FROM organization_memberships").
		WithArgs(testOrgID).
		WillReturnRows(sqlmock.NewRows([]string{"tenant_id"}).AddRow(testTenantA))

	// buildSnapshotFromTenant for the master tenant — return one category, one product, no modifier groups.
	mock.ExpectQuery(`FROM categories\s+WHERE tenant_id`).
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "name", "display_order", "color", "icon", "parent_id", "is_active",
		}).AddRow("cat-1", "Drinks", 0, "", "", "", true))
	mock.ExpectQuery(`FROM products\s+WHERE tenant_id`).
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "category_id", "name", "description",
			"price", "cost_price", "tax_group",
			"image_path", "barcode",
			"is_active", "display_order", "prep_time_minutes",
			"printer_group", "default_gang",
		}).AddRow(testProductA, "cat-1", "Latte", "", 500, 200, "default",
			"", "", true, 0, nil, "kitchen", nil))
	mock.ExpectQuery(`FROM modifier_groups\s+WHERE tenant_id`).
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "name", "selection_type", "min_selections", "max_selections",
			"is_required", "display_order",
		}))

	// loadOrgPolicies — empty
	mock.ExpectQuery(`FROM menu_policies WHERE organization_id`).
		WithArgs(testOrgID).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "organization_id", "product_id", "lock_type",
			"allow_local_additions", "allow_local_disable", "created_at", "updated_at",
		}))

	// Publish transaction
	mock.ExpectBegin()

	// Compute next version → 1 (no existing master_menus row → empty rows
	// → Scan returns sql.ErrNoRows; the handler then inserts the row.)
	mock.ExpectQuery(`FROM master_menus WHERE organization_id`).
		WithArgs(testOrgID).
		WillReturnRows(sqlmock.NewRows([]string{"v"}))

	mock.ExpectExec(`INSERT INTO master_menus`).
		WithArgs(testOrgID).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Insert master_menu_versions
	mock.ExpectExec(`INSERT INTO master_menu_versions`).
		WithArgs(testOrgID, 1, sqlmock.AnyArg(), testUserID).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Bump current version
	mock.ExpectExec(`UPDATE master_menus SET current_version`).
		WithArgs(testOrgID, 1).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// memberTenantIDsTx — 2 followers (master + B)
	mock.ExpectQuery(`FROM organization_memberships WHERE organization_id`).
		WithArgs(testOrgID).
		WillReturnRows(sqlmock.NewRows([]string{"tenant_id"}).AddRow(testTenantA).AddRow(testTenantB))

	// For master tenant (testTenantA) — already snapshotted, only need version + insert.
	mock.ExpectQuery(`FROM menu_versions WHERE tenant_id`).
		WithArgs(testTenantA).
		WillReturnRows(sqlmock.NewRows([]string{"v"}).AddRow(1))
	mock.ExpectExec(`INSERT INTO menu_versions`).
		WithArgs(testTenantA, 1, sqlmock.AnyArg(), testOrgID, 1, testUserID).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// For tenant B — re-snapshot (categories, products, modifier_groups, possibly modifiers).
	mock.ExpectQuery(`FROM categories\s+WHERE tenant_id`).
		WithArgs(testTenantB).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "name", "display_order", "color", "icon", "parent_id", "is_active",
		}))
	mock.ExpectQuery(`FROM products\s+WHERE tenant_id`).
		WithArgs(testTenantB).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "category_id", "name", "description",
			"price", "cost_price", "tax_group",
			"image_path", "barcode",
			"is_active", "display_order", "prep_time_minutes",
			"printer_group", "default_gang",
		}))
	mock.ExpectQuery(`FROM modifier_groups\s+WHERE tenant_id`).
		WithArgs(testTenantB).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "name", "selection_type", "min_selections", "max_selections",
			"is_required", "display_order",
		}))

	mock.ExpectQuery(`FROM menu_versions WHERE tenant_id`).
		WithArgs(testTenantB).
		WillReturnRows(sqlmock.NewRows([]string{"v"}).AddRow(1))
	mock.ExpectExec(`INSERT INTO menu_versions`).
		WithArgs(testTenantB, 1, sqlmock.AnyArg(), testOrgID, 1, testUserID).
		WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectCommit()

	req := httptest.NewRequest(http.MethodPost, "/api/v1/org/"+testOrgID+"/master-menu/publish", strings.NewReader(""))
	req.SetPathValue("orgId", testOrgID)
	req = withAuth(req, testUserID, RoleHQAdmin)
	w := httptest.NewRecorder()
	m.handlePublishMasterMenu(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d body=%s", w.Code, w.Body.String())
	}

	var body map[string]any
	decodeJSON(t, w, &body)
	if body["master_version"].(float64) != 1 {
		t.Errorf("want master_version=1, got %v", body["master_version"])
	}
	if body["published_to"].(float64) != 2 {
		t.Errorf("want published_to=2, got %v", body["published_to"])
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet sqlmock expectations: %v", err)
	}
}

// Compile-time guard against unused-import for `regexp` (kept for query
// matchers in case the generated SQL drifts).
var _ = regexp.MustCompile
