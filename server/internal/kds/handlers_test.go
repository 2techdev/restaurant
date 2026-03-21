package kds

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/gastrocore/server/internal/shared/middleware"
)

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

// withTenantID injects a tenant ID into the request context, simulating
// the AuthRequired + TenantRequired middleware chain.
func withTenantID(r *http.Request, tenantID string) *http.Request {
	ctx := context.WithValue(r.Context(), middleware.ContextKeyTenantID, tenantID)
	return r.WithContext(ctx)
}

func assertErrorCode(t *testing.T, w *httptest.ResponseRecorder, code string) {
	t.Helper()
	var body map[string]any
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["code"] != code {
		t.Errorf("expected error code %q, got %v", code, body["code"])
	}
}

// ---------------------------------------------------------------------------
// handleListTickets
// ---------------------------------------------------------------------------

func TestHandleListTickets_NoTenant(t *testing.T) {
	m := &Module{hub: NewHub()}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/kds/tickets", nil)
	w := httptest.NewRecorder()
	m.handleListTickets(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("want 401, got %d", w.Code)
	}
	assertErrorCode(t, w, "UNAUTHORIZED")
}

func TestHandleListTickets_EmptyResult(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("FROM tickets t").
		WithArgs("tenant-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "order_number", "order_type", "table_id",
			"channel", "notes", "status", "opened_at", "updated_at",
		}))

	m := &Module{db: db, hub: NewHub()}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/kds/tickets", nil)
	req = withTenantID(req, "tenant-1")
	w := httptest.NewRecorder()
	m.handleListTickets(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", w.Code, w.Body.String())
	}
	var tickets []KDSTicket
	json.NewDecoder(w.Body).Decode(&tickets)
	if len(tickets) != 0 {
		t.Errorf("want empty list, got %d tickets", len(tickets))
	}
}

func TestHandleListTickets_WithOneTicket(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	now := time.Now()
	mock.ExpectQuery("FROM tickets t").
		WithArgs("tenant-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "order_number", "order_type", "table_id",
			"channel", "notes", "status", "opened_at", "updated_at",
		}).AddRow("tkt-1", 5, "dine_in", nil, "pos", "no onions", "open", now, now))

	// Items for tkt-1
	mock.ExpectQuery("FROM order_items").
		WithArgs("tkt-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "product_name", "quantity", "notes", "kds_status", "course"}).
			AddRow("item-1", "Burger", 2, "", "pending", 1))

	m := &Module{db: db, hub: NewHub()}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/kds/tickets", nil)
	req = withTenantID(req, "tenant-1")
	w := httptest.NewRecorder()
	m.handleListTickets(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", w.Code, w.Body.String())
	}
	var tickets []KDSTicket
	json.NewDecoder(w.Body).Decode(&tickets)
	if len(tickets) != 1 {
		t.Fatalf("want 1 ticket, got %d", len(tickets))
	}
	if tickets[0].ID != "tkt-1" {
		t.Errorf("want id=tkt-1, got %s", tickets[0].ID)
	}
	if tickets[0].OrderNumber != 5 {
		t.Errorf("want order_number=5, got %d", tickets[0].OrderNumber)
	}
	if len(tickets[0].Items) != 1 {
		t.Fatalf("want 1 item, got %d", len(tickets[0].Items))
	}
	if tickets[0].Items[0].ProductName != "Burger" {
		t.Errorf("want product_name=Burger, got %s", tickets[0].Items[0].ProductName)
	}
	if tickets[0].Items[0].KDSStatus != "pending" {
		t.Errorf("want kds_status=pending, got %s", tickets[0].Items[0].KDSStatus)
	}
}

func TestHandleListTickets_TableNumberParsed(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	now := time.Now()
	tableNum := int64(7)
	mock.ExpectQuery("FROM tickets t").
		WithArgs("tenant-1").
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "order_number", "order_type", "table_id",
			"channel", "notes", "status", "opened_at", "updated_at",
		}).AddRow("tkt-2", 1, "dine_in", tableNum, "pos", "", "open", now, now))

	// Items for tkt-2 (empty)
	mock.ExpectQuery("FROM order_items").
		WithArgs("tkt-2").
		WillReturnRows(sqlmock.NewRows([]string{"id", "product_name", "quantity", "notes", "kds_status", "course"}))

	m := &Module{db: db, hub: NewHub()}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/kds/tickets", nil)
	req = withTenantID(req, "tenant-1")
	w := httptest.NewRecorder()
	m.handleListTickets(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}
	var tickets []KDSTicket
	json.NewDecoder(w.Body).Decode(&tickets)
	if len(tickets) != 1 {
		t.Fatalf("want 1 ticket, got %d", len(tickets))
	}
	if tickets[0].TableNumber == nil {
		t.Fatal("expected non-nil table_number")
	}
	if *tickets[0].TableNumber != 7 {
		t.Errorf("want table_number=7, got %d", *tickets[0].TableNumber)
	}
}

// ---------------------------------------------------------------------------
// handleUpdateItemStatus
// ---------------------------------------------------------------------------

func TestHandleUpdateItemStatus_NoTenant(t *testing.T) {
	m := &Module{hub: NewHub()}
	req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/items/item-1/status", nil)
	req.SetPathValue("id", "item-1")
	w := httptest.NewRecorder()
	m.handleUpdateItemStatus(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("want 401, got %d", w.Code)
	}
	assertErrorCode(t, w, "UNAUTHORIZED")
}

func TestHandleUpdateItemStatus_MissingID(t *testing.T) {
	m := &Module{hub: NewHub()}
	req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/items//status",
		bytes.NewBufferString(`{"status":"ready"}`))
	req = withTenantID(req, "tenant-1")
	// PathValue("id") returns "" when not set
	w := httptest.NewRecorder()
	m.handleUpdateItemStatus(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "MISSING_ID")
}

func TestHandleUpdateItemStatus_InvalidBody(t *testing.T) {
	m := &Module{hub: NewHub()}
	req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/items/item-1/status",
		bytes.NewBufferString("not-json"))
	req = withTenantID(req, "tenant-1")
	req.SetPathValue("id", "item-1")
	w := httptest.NewRecorder()
	m.handleUpdateItemStatus(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "INVALID_BODY")
}

func TestHandleUpdateItemStatus_InvalidStatus(t *testing.T) {
	invalidStatuses := []string{"", "pending", "done", "cancelled", "READY"}
	for _, status := range invalidStatuses {
		m := &Module{hub: NewHub()}
		body := map[string]string{"status": status}
		b, _ := json.Marshal(body)
		req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/items/item-1/status", bytes.NewReader(b))
		req = withTenantID(req, "tenant-1")
		req.SetPathValue("id", "item-1")
		w := httptest.NewRecorder()
		m.handleUpdateItemStatus(w, req)
		if w.Code != http.StatusBadRequest {
			t.Errorf("status=%q: want 400, got %d", status, w.Code)
		}
		assertErrorCode(t, w, "INVALID_STATUS")
	}
}

func TestHandleUpdateItemStatus_ValidStatuses(t *testing.T) {
	validStatuses := []string{"preparing", "ready", "served"}
	for _, status := range validStatuses {
		db, mock, err := sqlmock.New()
		if err != nil {
			t.Fatal(err)
		}

		mock.ExpectExec("UPDATE order_items").
			WillReturnResult(sqlmock.NewResult(1, 1))

		m := &Module{db: db, hub: NewHub()}
		body := map[string]string{"status": status}
		b, _ := json.Marshal(body)
		req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/items/item-1/status", bytes.NewReader(b))
		req = withTenantID(req, "tenant-1")
		req.SetPathValue("id", "item-1")
		w := httptest.NewRecorder()
		m.handleUpdateItemStatus(w, req)

		if w.Code != http.StatusOK {
			t.Errorf("status=%s: want 200, got %d: %s", status, w.Code, w.Body.String())
		}
		var resp map[string]string
		json.NewDecoder(w.Body).Decode(&resp)
		if resp["status"] != status {
			t.Errorf("status=%s: response status mismatch, got %s", status, resp["status"])
		}
		if resp["item_id"] != "item-1" {
			t.Errorf("status=%s: want item_id=item-1, got %s", status, resp["item_id"])
		}
		db.Close()
	}
}

func TestHandleUpdateItemStatus_NotFound(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectExec("UPDATE order_items").
		WillReturnResult(sqlmock.NewResult(0, 0)) // 0 rows affected

	m := &Module{db: db, hub: NewHub()}
	body := map[string]string{"status": "ready"}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/items/nonexistent/status", bytes.NewReader(b))
	req = withTenantID(req, "tenant-1")
	req.SetPathValue("id", "nonexistent")
	w := httptest.NewRecorder()
	m.handleUpdateItemStatus(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("want 404, got %d", w.Code)
	}
	assertErrorCode(t, w, "NOT_FOUND")
}

// ---------------------------------------------------------------------------
// handleUpdateTicketStatus
// ---------------------------------------------------------------------------

func TestHandleUpdateTicketStatus_NoTenant(t *testing.T) {
	m := &Module{hub: NewHub()}
	req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/tickets/tkt-1/status", nil)
	req.SetPathValue("id", "tkt-1")
	w := httptest.NewRecorder()
	m.handleUpdateTicketStatus(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("want 401, got %d", w.Code)
	}
	assertErrorCode(t, w, "UNAUTHORIZED")
}

func TestHandleUpdateTicketStatus_MissingID(t *testing.T) {
	m := &Module{hub: NewHub()}
	body := map[string]string{"status": "preparing"}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/tickets//status", bytes.NewReader(b))
	req = withTenantID(req, "tenant-1")
	// PathValue("id") returns "" when not set
	w := httptest.NewRecorder()
	m.handleUpdateTicketStatus(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "MISSING_ID")
}

func TestHandleUpdateTicketStatus_InvalidBody(t *testing.T) {
	m := &Module{hub: NewHub()}
	req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/tickets/tkt-1/status",
		bytes.NewBufferString("!!!not-json"))
	req = withTenantID(req, "tenant-1")
	req.SetPathValue("id", "tkt-1")
	w := httptest.NewRecorder()
	m.handleUpdateTicketStatus(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", w.Code)
	}
}

func TestHandleUpdateTicketStatus_Success(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectExec("UPDATE order_items").
		WillReturnResult(sqlmock.NewResult(3, 3))

	m := &Module{db: db, hub: NewHub()}
	body := map[string]string{"status": "preparing"}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/tickets/tkt-1/status", bytes.NewReader(b))
	req = withTenantID(req, "tenant-1")
	req.SetPathValue("id", "tkt-1")
	w := httptest.NewRecorder()
	m.handleUpdateTicketStatus(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp map[string]string
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["ticket_id"] != "tkt-1" {
		t.Errorf("want ticket_id=tkt-1, got %s", resp["ticket_id"])
	}
	if resp["status"] != "preparing" {
		t.Errorf("want status=preparing, got %s", resp["status"])
	}
}

func TestHandleUpdateTicketStatus_FullyServed(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectExec("UPDATE order_items").
		WillReturnResult(sqlmock.NewResult(5, 5))

	m := &Module{db: db, hub: NewHub()}
	body := map[string]string{"status": "fully_served"}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPut, "/api/v1/kds/tickets/tkt-99/status", bytes.NewReader(b))
	req = withTenantID(req, "tenant-1")
	req.SetPathValue("id", "tkt-99")
	w := httptest.NewRecorder()
	m.handleUpdateTicketStatus(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("want 200, got %d", w.Code)
	}
}
