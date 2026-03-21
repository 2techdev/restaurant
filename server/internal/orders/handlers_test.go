package orders

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandleListOrders_ReturnsOK(t *testing.T) {
	m := &Module{}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
	w := httptest.NewRecorder()
	m.handleListOrders(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("want 200, got %d", w.Code)
	}

	var resp map[string]any
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if _, ok := resp["data"]; !ok {
		t.Error("expected 'data' field in paginated response")
	}
	if _, ok := resp["has_more"]; !ok {
		t.Error("expected 'has_more' field in paginated response")
	}
}

func TestHandleListOrders_AcceptsQueryParams(t *testing.T) {
	m := &Module{}
	req := httptest.NewRequest(http.MethodGet,
		"/api/v1/orders?status=open&date_from=2024-01-01&date_to=2024-01-31", nil)
	w := httptest.NewRecorder()
	m.handleListOrders(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("want 200 even with query params, got %d", w.Code)
	}
}

func TestHandleListOrders_EmptyData(t *testing.T) {
	m := &Module{}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders", nil)
	w := httptest.NewRecorder()
	m.handleListOrders(w, req)

	var resp map[string]any
	json.NewDecoder(w.Body).Decode(&resp)

	// data should be an empty array, not null
	data, ok := resp["data"]
	if !ok {
		t.Fatal("missing data field")
	}
	if data == nil {
		t.Error("data should be an empty array, not null")
	}
}

func TestHandleGetOrder_ReturnsStub(t *testing.T) {
	m := &Module{}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders/order-123", nil)
	req.SetPathValue("id", "order-123")
	w := httptest.NewRecorder()
	m.handleGetOrder(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("want 200, got %d", w.Code)
	}

	var resp map[string]any
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if _, ok := resp["ticket"]; !ok {
		t.Error("expected 'ticket' field in response")
	}
	if _, ok := resp["items"]; !ok {
		t.Error("expected 'items' field in response")
	}
	if _, ok := resp["bills"]; !ok {
		t.Error("expected 'bills' field in response")
	}
	if _, ok := resp["payments"]; !ok {
		t.Error("expected 'payments' field in response")
	}
}

func TestHandleGetOrder_DifferentIDs(t *testing.T) {
	ids := []string{"order-1", "order-abc", "550e8400-e29b-41d4-a716-446655440000"}
	for _, id := range ids {
		m := &Module{}
		req := httptest.NewRequest(http.MethodGet, "/api/v1/orders/"+id, nil)
		req.SetPathValue("id", id)
		w := httptest.NewRecorder()
		m.handleGetOrder(w, req)
		if w.Code != http.StatusOK {
			t.Errorf("id=%s: want 200, got %d", id, w.Code)
		}
	}
}

func TestHandleOrderSummary_ReturnsZeros(t *testing.T) {
	m := &Module{}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders/summary", nil)
	w := httptest.NewRecorder()
	m.handleOrderSummary(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("want 200, got %d", w.Code)
	}

	var resp map[string]any
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}

	fields := []string{"total_orders", "total_revenue", "average_order", "orders_by_type", "orders_by_status"}
	for _, field := range fields {
		if _, ok := resp[field]; !ok {
			t.Errorf("expected field %q in summary response", field)
		}
	}
}

func TestHandleOrderSummary_ZeroValues(t *testing.T) {
	m := &Module{}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders/summary", nil)
	w := httptest.NewRecorder()
	m.handleOrderSummary(w, req)

	var resp map[string]any
	json.NewDecoder(w.Body).Decode(&resp)

	// Stub implementation returns 0 for numeric fields
	if resp["total_orders"] != float64(0) {
		t.Errorf("want total_orders=0, got %v", resp["total_orders"])
	}
	if resp["total_revenue"] != float64(0) {
		t.Errorf("want total_revenue=0, got %v", resp["total_revenue"])
	}
}
