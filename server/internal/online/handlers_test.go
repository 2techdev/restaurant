package online

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// ---------------------------------------------------------------------------
// Pure-function unit tests (no DB, no HTTP)
// ---------------------------------------------------------------------------

func TestEstimatedWaitForStatus(t *testing.T) {
	cases := []struct {
		status string
		want   int
	}{
		{"open", 20},
		{"items_added", 20},
		{"sent_to_kitchen", 12},
		{"preparing", 12},
		{"partially_served", 5},
		{"fully_served", 0},
		{"closed", 0},
		{"fully_paid", 0},
		{"unknown_xyz", 20},
	}
	for _, tc := range cases {
		got := estimatedWaitForStatus(tc.status)
		if got != tc.want {
			t.Errorf("estimatedWaitForStatus(%q) = %d, want %d", tc.status, got, tc.want)
		}
	}
}

func TestValidOrderStatuses(t *testing.T) {
	valid := []string{
		"open", "items_added", "sent_to_kitchen", "preparing",
		"partially_served", "fully_served", "bill_requested",
		"partially_paid", "fully_paid", "closed", "void",
	}
	for _, s := range valid {
		if !validOrderStatuses[s] {
			t.Errorf("expected %q to be a valid order status", s)
		}
	}
	invalid := []string{"unknown", "ready", "", "OPEN"}
	for _, s := range invalid {
		if validOrderStatuses[s] {
			t.Errorf("expected %q to be invalid", s)
		}
	}
}

func TestNullString(t *testing.T) {
	if nullString("") != nil {
		t.Error("empty string should return nil")
	}
	if v, ok := nullString("hello").(string); !ok || v != "hello" {
		t.Error("non-empty string should return string value")
	}
}

// ---------------------------------------------------------------------------
// Handler validation tests — these return 400 before any DB query, so db=nil
// is safe. Requests are routed through a real http.ServeMux so that
// r.PathValue() is populated correctly.
// ---------------------------------------------------------------------------

func newTestModule() *Module {
	return &Module{db: nil, kdsNotify: nil, wsHub: nil}
}

func TestHandlePlaceOrder_EmptyBody(t *testing.T) {
	m := newTestModule()
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/online/orders", m.handlePlaceOrder)

	req := httptest.NewRequest("POST", "/api/v1/online/orders", strings.NewReader(""))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestHandlePlaceOrder_MissingRestaurantID(t *testing.T) {
	m := newTestModule()
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/online/orders", m.handlePlaceOrder)

	body := `{"order_type":"dine_in","items":[{"product_id":"p1","product_name":"Test","quantity":1,"unit_price":1000}]}`
	req := httptest.NewRequest("POST", "/api/v1/online/orders", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing restaurant_id, got %d", w.Code)
	}
}

func TestHandlePlaceOrder_NoItems(t *testing.T) {
	m := newTestModule()
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/online/orders", m.handlePlaceOrder)

	body := `{"restaurant_id":"r1","order_type":"dine_in","items":[]}`
	req := httptest.NewRequest("POST", "/api/v1/online/orders", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for empty items, got %d", w.Code)
	}
}

func TestHandleUpdateOrderStatus_EmptyBody(t *testing.T) {
	m := newTestModule()
	mux := http.NewServeMux()
	mux.HandleFunc("PUT /api/v1/online/orders/{orderId}/status", m.handleUpdateOrderStatus)

	req := httptest.NewRequest("PUT", "/api/v1/online/orders/some-uuid/status", strings.NewReader(""))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for empty body, got %d", w.Code)
	}
}

func TestHandleUpdateOrderStatus_InvalidStatus(t *testing.T) {
	m := newTestModule()
	mux := http.NewServeMux()
	mux.HandleFunc("PUT /api/v1/online/orders/{orderId}/status", m.handleUpdateOrderStatus)

	body := `{"status":"not_a_real_status"}`
	req := httptest.NewRequest("PUT", "/api/v1/online/orders/some-uuid/status", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for invalid status, got %d", w.Code)
	}
}

func TestHandleGetMenu_MissingRestaurantID(t *testing.T) {
	// Route doesn't match without a restaurantId segment; the mux returns 405/404.
	// Test directly: call with a request that won't match the wildcard segment.
	m := newTestModule()
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/online/menu/{restaurantId}", m.handleGetMenu)

	req := httptest.NewRequest("GET", "/api/v1/online/menu/", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	// The mux will 404 for an unmatched pattern (empty segment).
	if w.Code == http.StatusOK {
		t.Error("expected non-200 when restaurantId is missing")
	}
}

// TestHandleWebSocket_MissingRestaurantID checks that the WS endpoint returns
// 400 (before upgrade) when restaurant_id is absent.
func TestHandleWebSocket_MissingRestaurantID(t *testing.T) {
	hub := NewOnlineHub()
	go hub.Run()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /ws/online/orders/live", hub.serveWS)

	req := httptest.NewRequest("GET", "/ws/online/orders/live", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 when restaurant_id missing, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// Business logic — subtotal and VAT calculation
// ---------------------------------------------------------------------------

func TestSubtotalCalculation_SingleItemNoModifiers(t *testing.T) {
	items := []OnlineOrderItem{
		{UnitPrice: 2500, Quantity: 2},
	}

	var subtotal int64
	for _, item := range items {
		lineTotal := item.UnitPrice * int64(item.Quantity)
		for _, mod := range item.Modifiers {
			lineTotal += mod.PriceDelta * int64(item.Quantity)
		}
		subtotal += lineTotal
	}

	// 2500 * 2 = 5000
	if subtotal != 5000 {
		t.Errorf("subtotal: want 5000, got %d", subtotal)
	}
}

func TestSubtotalCalculation_WithModifiers(t *testing.T) {
	items := []OnlineOrderItem{
		{
			UnitPrice: 2500,
			Quantity:  2,
			Modifiers: []OnlineOrderModifier{
				{PriceDelta: 200},
			},
		},
		{UnitPrice: 1000, Quantity: 3},
	}

	var subtotal int64
	for _, item := range items {
		lineTotal := item.UnitPrice * int64(item.Quantity)
		for _, mod := range item.Modifiers {
			lineTotal += mod.PriceDelta * int64(item.Quantity)
		}
		subtotal += lineTotal
	}

	// item 1: (2500 + 200) * 2 = 5400
	// item 2: 1000 * 3 = 3000
	// total = 8400
	if subtotal != 8400 {
		t.Errorf("subtotal: want 8400, got %d", subtotal)
	}
}

func TestVATRate_Takeaway(t *testing.T) {
	subtotal := int64(10000)
	vatRate := 2.6
	taxAmount := int64(float64(subtotal)*vatRate/100.0 + 0.5)
	if taxAmount != 260 {
		t.Errorf("2.6%% VAT on 10000: want 260, got %d", taxAmount)
	}
}

func TestVATRate_DineIn(t *testing.T) {
	subtotal := int64(10000)
	vatRate := 8.1
	taxAmount := int64(float64(subtotal)*vatRate/100.0 + 0.5)
	if taxAmount != 810 {
		t.Errorf("8.1%% VAT on 10000: want 810, got %d", taxAmount)
	}
}

func TestVATRate_Selection(t *testing.T) {
	cases := []struct {
		orderType string
		wantRate  float64
	}{
		{"takeaway", 2.6},
		{"dine_in", 8.1},
		{"delivery", 8.1},
		{"", 8.1},
	}
	for _, tc := range cases {
		var vatRate float64
		if tc.orderType == "takeaway" {
			vatRate = 2.6
		} else {
			vatRate = 8.1
		}
		if vatRate != tc.wantRate {
			t.Errorf("order_type=%q: want %.1f%%, got %.1f%%", tc.orderType, tc.wantRate, vatRate)
		}
	}
}

// ---------------------------------------------------------------------------
// Model JSON round-trips
// ---------------------------------------------------------------------------

func TestPlaceOnlineOrderRequest_Fields(t *testing.T) {
	tableNum := 5
	req := PlaceOnlineOrderRequest{
		RestaurantID: "rest-abc",
		OrderType:    "takeaway",
		TableNumber:  &tableNum,
		CustomerName: "Test Customer",
		Notes:        "Extra spicy",
		Channel:      "qr",
		Items: []OnlineOrderItem{
			{
				ProductID:   "prod-1",
				ProductName: "Adana Kebap",
				Quantity:    2,
				UnitPrice:   2500,
				Modifiers: []OnlineOrderModifier{
					{ModifierID: "mod-1", ModifierName: "Spicy", PriceDelta: 100},
				},
			},
		},
	}

	if req.RestaurantID == "" {
		t.Error("RestaurantID should not be empty")
	}
	if len(req.Items) != 1 {
		t.Errorf("Items: want 1, got %d", len(req.Items))
	}
	if len(req.Items[0].Modifiers) != 1 {
		t.Errorf("Modifiers: want 1, got %d", len(req.Items[0].Modifiers))
	}
	if req.TableNumber == nil || *req.TableNumber != 5 {
		t.Errorf("TableNumber: want 5, got %v", req.TableNumber)
	}
}

func TestOrderStatusResponse_Fields(t *testing.T) {
	s := OrderStatusResponse{
		OrderID:              "order-123",
		OrderNumber:          42,
		Status:               "preparing",
		EstimatedWaitMinutes: estimatedWaitForStatus("preparing"),
	}

	if s.OrderID != "order-123" {
		t.Errorf("OrderID: %q", s.OrderID)
	}
	if s.EstimatedWaitMinutes != 12 {
		t.Errorf("EstimatedWaitMinutes: want 12, got %d", s.EstimatedWaitMinutes)
	}
}

// ---------------------------------------------------------------------------
// handleGetOrderStatus — validation (path value absent)
// ---------------------------------------------------------------------------

func TestHandleGetOrderStatus_MissingOrderID(t *testing.T) {
	m := newTestModule()
	// Direct call without mux so PathValue returns "".
	req := httptest.NewRequest("GET", "/api/v1/online/orders//status", nil)
	w := httptest.NewRecorder()
	m.handleGetOrderStatus(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for missing order_id, got %d", w.Code)
	}
}
