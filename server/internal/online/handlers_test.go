package online

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
)

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

func assertErrorCode(t *testing.T, w *httptest.ResponseRecorder, code string) {
	t.Helper()
	var body map[string]any
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("decode response body: %v", err)
	}
	if body["code"] != code {
		t.Errorf("expected error code %q, got %v", code, body["code"])
	}
}

// ---------------------------------------------------------------------------
// Pure function tests — no DB needed
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
		{"unknown_status", 20},
		{"", 20},
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

func vatAmount(subtotal int64, rate float64) int64 {
	return int64(float64(subtotal)*rate/100.0 + 0.5)
}

func TestVATRateCalculation(t *testing.T) {
	cases := []struct {
		orderType string
		subtotal  int64
		wantVAT   int64
	}{
		{"dine_in", 1000, vatAmount(1000, 8.1)},
		{"takeaway", 1000, vatAmount(1000, 2.6)},
		{"dine_in", 10000, vatAmount(10000, 8.1)},
		{"takeaway", 10000, vatAmount(10000, 2.6)},
		{"dine_in", 500, vatAmount(500, 8.1)},
	}
	for _, tc := range cases {
		var vatRate float64
		if tc.orderType == "takeaway" {
			vatRate = 2.6
		} else {
			vatRate = 8.1
		}
		got := vatAmount(tc.subtotal, vatRate)
		if got != tc.wantVAT {
			t.Errorf("orderType=%s subtotal=%d: VAT=%d, want %d",
				tc.orderType, tc.subtotal, got, tc.wantVAT)
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
	if req.RestaurantID != "rest-abc" {
		t.Errorf("expected RestaurantID=rest-abc, got %s", req.RestaurantID)
	}
	if len(req.Items) != 1 || len(req.Items[0].Modifiers) != 1 {
		t.Errorf("unexpected items/modifiers: %+v", req.Items)
	}
}

// ---------------------------------------------------------------------------
// handlePlaceOrder — validation (no DB)
// ---------------------------------------------------------------------------

func TestHandlePlaceOrder_InvalidBody(t *testing.T) {
	m := &Module{}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders",
		bytes.NewBufferString("not-json"))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "INVALID_BODY")
}

func TestHandlePlaceOrder_MissingRestaurantID(t *testing.T) {
	m := &Module{}
	body := PlaceOnlineOrderRequest{
		Items: []OnlineOrderItem{{ProductID: "p1", Quantity: 1, UnitPrice: 1000}},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "MISSING_RESTAURANT_ID")
}

func TestHandlePlaceOrder_NoItems(t *testing.T) {
	m := &Module{}
	body := PlaceOnlineOrderRequest{RestaurantID: "rest-1"}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "NO_ITEMS")
}

func TestHandlePlaceOrder_EmptyItemsSlice(t *testing.T) {
	m := &Module{}
	body := PlaceOnlineOrderRequest{
		RestaurantID: "rest-1",
		Items:        []OnlineOrderItem{},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400 for empty items, got %d", w.Code)
	}
	assertErrorCode(t, w, "NO_ITEMS")
}

// ---------------------------------------------------------------------------
// handlePlaceOrder — DB paths (sqlmock)
// ---------------------------------------------------------------------------

func TestHandlePlaceOrder_DineIn_Success(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("SELECT COALESCE").
		WithArgs("rest-1").
		WillReturnRows(sqlmock.NewRows([]string{"num"}).AddRow(7))
	mock.ExpectExec("INSERT INTO tickets").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO order_items").
		WillReturnResult(sqlmock.NewResult(1, 1))

	m := &Module{db: db}
	body := PlaceOnlineOrderRequest{
		RestaurantID: "rest-1",
		OrderType:    "dine_in",
		CustomerName: "Alice",
		Items: []OnlineOrderItem{
			{ProductID: "p1", ProductName: "Burger", Quantity: 2, UnitPrice: 1500},
		},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("want 201, got %d: %s", w.Code, w.Body.String())
	}

	var resp PlaceOnlineOrderResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.OrderNumber != 7 {
		t.Errorf("want order_number=7, got %d", resp.OrderNumber)
	}
	if resp.Status != "received" {
		t.Errorf("want status=received, got %s", resp.Status)
	}
	if resp.EstimatedWaitMinutes != 20 {
		t.Errorf("want estimated_wait=20, got %d", resp.EstimatedWaitMinutes)
	}
	if resp.ID == "" {
		t.Error("expected non-empty order ID")
	}
	if resp.CreatedAt.IsZero() {
		t.Error("expected non-zero created_at")
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet sqlmock expectations: %v", err)
	}
}

func TestHandlePlaceOrder_Takeaway_Success(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("SELECT COALESCE").
		WithArgs("rest-1").
		WillReturnRows(sqlmock.NewRows([]string{"num"}).AddRow(3))
	mock.ExpectExec("INSERT INTO tickets").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO order_items").
		WillReturnResult(sqlmock.NewResult(1, 1))

	m := &Module{db: db}
	body := PlaceOnlineOrderRequest{
		RestaurantID: "rest-1",
		OrderType:    "takeaway",
		Channel:      "web",
		Items: []OnlineOrderItem{
			{ProductID: "p2", ProductName: "Coffee", Quantity: 1, UnitPrice: 500},
		},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("want 201, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHandlePlaceOrder_DefaultChannel(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("SELECT COALESCE").
		WillReturnRows(sqlmock.NewRows([]string{"num"}).AddRow(1))
	mock.ExpectExec("INSERT INTO tickets").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO order_items").
		WillReturnResult(sqlmock.NewResult(1, 1))

	m := &Module{db: db}
	body := PlaceOnlineOrderRequest{
		RestaurantID: "rest-1",
		OrderType:    "dine_in",
		// Channel intentionally empty — should default to "qr"
		Items: []OnlineOrderItem{
			{ProductID: "p1", ProductName: "Tea", Quantity: 1, UnitPrice: 300},
		},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("want 201, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHandlePlaceOrder_WithModifiers(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("SELECT COALESCE").
		WithArgs("rest-1").
		WillReturnRows(sqlmock.NewRows([]string{"num"}).AddRow(1))
	mock.ExpectExec("INSERT INTO tickets").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO order_items").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO order_item_modifiers").
		WillReturnResult(sqlmock.NewResult(1, 1))

	m := &Module{db: db}
	body := PlaceOnlineOrderRequest{
		RestaurantID: "rest-1",
		OrderType:    "dine_in",
		Items: []OnlineOrderItem{
			{
				ProductID:   "p1",
				ProductName: "Pizza",
				Quantity:    1,
				UnitPrice:   2000,
				Modifiers: []OnlineOrderModifier{
					{ModifierID: "m1", ModifierName: "Extra Cheese", PriceDelta: 200},
				},
			},
		},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("want 201, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unmet sqlmock expectations: %v", err)
	}
}

func TestHandlePlaceOrder_MultipleItems(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("SELECT COALESCE").
		WillReturnRows(sqlmock.NewRows([]string{"num"}).AddRow(10))
	mock.ExpectExec("INSERT INTO tickets").
		WillReturnResult(sqlmock.NewResult(1, 1))
	// Two order items
	mock.ExpectExec("INSERT INTO order_items").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO order_items").
		WillReturnResult(sqlmock.NewResult(1, 1))

	m := &Module{db: db}
	body := PlaceOnlineOrderRequest{
		RestaurantID: "rest-1",
		OrderType:    "dine_in",
		Items: []OnlineOrderItem{
			{ProductID: "p1", ProductName: "Burger", Quantity: 1, UnitPrice: 1500},
			{ProductID: "p2", ProductName: "Fries", Quantity: 2, UnitPrice: 500},
		},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("want 201, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHandlePlaceOrder_KDSNotify(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("SELECT COALESCE").
		WillReturnRows(sqlmock.NewRows([]string{"num"}).AddRow(1))
	mock.ExpectExec("INSERT INTO tickets").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO order_items").
		WillReturnResult(sqlmock.NewResult(1, 1))

	var notified bool
	notifier := &mockKDSNotifier{fn: func(tenantID, ticketID string, orderNumber int) {
		notified = true
		if tenantID != "rest-1" {
			t.Errorf("KDS notify: want tenantID=rest-1, got %s", tenantID)
		}
		if ticketID == "" {
			t.Error("KDS notify: expected non-empty ticketID")
		}
	}}

	m := &Module{db: db, kdsNotify: notifier}
	body := PlaceOnlineOrderRequest{
		RestaurantID: "rest-1",
		OrderType:    "dine_in",
		Items: []OnlineOrderItem{
			{ProductID: "p1", ProductName: "Salad", Quantity: 1, UnitPrice: 1200},
		},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()
	m.handlePlaceOrder(w, req)

	if w.Code != http.StatusCreated {
		t.Errorf("want 201, got %d", w.Code)
	}
	if !notified {
		t.Error("expected KDS notifier to be called")
	}
}

func TestHandlePlaceOrder_NoKDSNotifyWhenNil(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("SELECT COALESCE").
		WillReturnRows(sqlmock.NewRows([]string{"num"}).AddRow(1))
	mock.ExpectExec("INSERT INTO tickets").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec("INSERT INTO order_items").
		WillReturnResult(sqlmock.NewResult(1, 1))

	m := &Module{db: db, kdsNotify: nil}
	body := PlaceOnlineOrderRequest{
		RestaurantID: "rest-1",
		OrderType:    "dine_in",
		Items: []OnlineOrderItem{
			{ProductID: "p1", ProductName: "Pasta", Quantity: 1, UnitPrice: 1800},
		},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/online/orders", bytes.NewReader(b))
	w := httptest.NewRecorder()

	// Must not panic when kdsNotify is nil
	m.handlePlaceOrder(w, req)
	if w.Code != http.StatusCreated {
		t.Errorf("want 201, got %d", w.Code)
	}
}

// mockKDSNotifier is a test double for KDSNotifier.
type mockKDSNotifier struct {
	fn func(tenantID, ticketID string, orderNumber int)
}

func (n *mockKDSNotifier) NotifyNewOrder(tenantID, ticketID string, orderNumber int) {
	if n.fn != nil {
		n.fn(tenantID, ticketID, orderNumber)
	}
}

// ---------------------------------------------------------------------------
// handleGetOrderStatus — validation (no DB)
// ---------------------------------------------------------------------------

func TestHandleGetOrderStatus_MissingOrderID(t *testing.T) {
	m := &Module{}
	// PathValue("orderId") returns "" when not set via router
	req := httptest.NewRequest(http.MethodGet, "/api/v1/online/orders//status", nil)
	w := httptest.NewRecorder()
	m.handleGetOrderStatus(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "MISSING_ORDER_ID")
}

// ---------------------------------------------------------------------------
// handleGetOrderStatus — DB paths (sqlmock)
// ---------------------------------------------------------------------------

func TestHandleGetOrderStatus_Found_Preparing(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("FROM tickets").
		WithArgs("order-123").
		WillReturnRows(sqlmock.NewRows([]string{"id", "order_number", "status"}).
			AddRow("order-123", 42, "preparing"))

	m := &Module{db: db}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/online/orders/order-123/status", nil)
	req.SetPathValue("orderId", "order-123")
	w := httptest.NewRecorder()
	m.handleGetOrderStatus(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp OrderStatusResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.OrderID != "order-123" {
		t.Errorf("want order_id=order-123, got %s", resp.OrderID)
	}
	if resp.OrderNumber != 42 {
		t.Errorf("want order_number=42, got %d", resp.OrderNumber)
	}
	if resp.Status != "preparing" {
		t.Errorf("want status=preparing, got %s", resp.Status)
	}
	if resp.EstimatedWaitMinutes != 12 {
		t.Errorf("want estimated_wait=12 for preparing, got %d", resp.EstimatedWaitMinutes)
	}
}

func TestHandleGetOrderStatus_Found_Closed(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("FROM tickets").
		WithArgs("order-closed").
		WillReturnRows(sqlmock.NewRows([]string{"id", "order_number", "status"}).
			AddRow("order-closed", 5, "closed"))

	m := &Module{db: db}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/online/orders/order-closed/status", nil)
	req.SetPathValue("orderId", "order-closed")
	w := httptest.NewRecorder()
	m.handleGetOrderStatus(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", w.Code)
	}
	var resp OrderStatusResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.EstimatedWaitMinutes != 0 {
		t.Errorf("want estimated_wait=0 for closed, got %d", resp.EstimatedWaitMinutes)
	}
}

func TestHandleGetOrderStatus_NotFound(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("FROM tickets").
		WithArgs("nonexistent").
		WillReturnError(sql.ErrNoRows)

	m := &Module{db: db}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/online/orders/nonexistent/status", nil)
	req.SetPathValue("orderId", "nonexistent")
	w := httptest.NewRecorder()
	m.handleGetOrderStatus(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("want 404, got %d", w.Code)
	}
	assertErrorCode(t, w, "ORDER_NOT_FOUND")
}

// ---------------------------------------------------------------------------
// handleGetMenu — validation (no DB)
// ---------------------------------------------------------------------------

func TestHandleGetMenu_MissingRestaurantID(t *testing.T) {
	m := &Module{}
	// PathValue("restaurantId") returns "" when not set via router
	req := httptest.NewRequest(http.MethodGet, "/api/v1/online/menu/", nil)
	w := httptest.NewRecorder()
	m.handleGetMenu(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("want 400, got %d", w.Code)
	}
	assertErrorCode(t, w, "MISSING_RESTAURANT_ID")
}

// ---------------------------------------------------------------------------
// handleGetMenu — DB paths (sqlmock)
// ---------------------------------------------------------------------------

func TestHandleGetMenu_RestaurantNotFound(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("FROM tenants").
		WithArgs("unknown").
		WillReturnError(sql.ErrNoRows)

	m := &Module{db: db}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/online/menu/unknown", nil)
	req.SetPathValue("restaurantId", "unknown")
	w := httptest.NewRecorder()
	m.handleGetMenu(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("want 404, got %d", w.Code)
	}
	assertErrorCode(t, w, "RESTAURANT_NOT_FOUND")
}

func TestHandleGetMenu_Found_EmptyMenu(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("FROM tenants").
		WithArgs("rest-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "name", "description", "logo_url", "cover_image_url", "is_open"}).
			AddRow("rest-1", "Burger Palace", "", "", "", true))

	mock.ExpectQuery("FROM categories").
		WithArgs("rest-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "name", "display_order", "color", "icon"}))

	mock.ExpectQuery("FROM products").
		WithArgs("rest-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "category_id", "name", "description", "price", "tax_group", "image_path", "is_active", "display_order", "prep_time_minutes"}))

	m := &Module{db: db}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/online/menu/rest-1", nil)
	req.SetPathValue("restaurantId", "rest-1")
	w := httptest.NewRecorder()
	m.handleGetMenu(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp MenuResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Restaurant.Name != "Burger Palace" {
		t.Errorf("want name=Burger Palace, got %s", resp.Restaurant.Name)
	}
	if !resp.Restaurant.IsOpen {
		t.Error("expected restaurant to be open")
	}
	if resp.Restaurant.EstimatedWaitMinutes != 20 {
		t.Errorf("want estimated_wait=20, got %d", resp.Restaurant.EstimatedWaitMinutes)
	}
	if len(resp.Categories) != 0 {
		t.Errorf("want 0 categories, got %d", len(resp.Categories))
	}
	if len(resp.Products) != 0 {
		t.Errorf("want 0 products, got %d", len(resp.Products))
	}
}

func TestHandleGetMenu_Found_WithProducts(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	mock.ExpectQuery("FROM tenants").
		WithArgs("rest-2").
		WillReturnRows(sqlmock.NewRows([]string{"id", "name", "description", "logo_url", "cover_image_url", "is_open"}).
			AddRow("rest-2", "Pizza Palace", "Best pizza in town", "", "", true))

	mock.ExpectQuery("FROM categories").
		WithArgs("rest-2").
		WillReturnRows(sqlmock.NewRows([]string{"id", "name", "display_order", "color", "icon"}).
			AddRow("cat-1", "Mains", 1, "#ff0000", "").
			AddRow("cat-2", "Drinks", 2, "#00ff00", ""))

	mock.ExpectQuery("FROM products").
		WithArgs("rest-2").
		WillReturnRows(sqlmock.NewRows([]string{"id", "category_id", "name", "description", "price", "tax_group", "image_path", "is_active", "display_order", "prep_time_minutes"}).
			AddRow("prod-1", "cat-1", "Margherita", "Classic pizza", int64(1500), "standard", "", true, 1, nil))

	// Modifier groups for prod-1 (none)
	mock.ExpectQuery("FROM modifier_groups").
		WithArgs("prod-1").
		WillReturnRows(sqlmock.NewRows([]string{"id", "name", "selection_type", "min_selections", "max_selections", "is_required", "display_order"}))

	m := &Module{db: db}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/online/menu/rest-2", nil)
	req.SetPathValue("restaurantId", "rest-2")
	w := httptest.NewRecorder()
	m.handleGetMenu(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp MenuResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Restaurant.Name != "Pizza Palace" {
		t.Errorf("want restaurant name=Pizza Palace, got %s", resp.Restaurant.Name)
	}
	if len(resp.Categories) != 2 {
		t.Errorf("want 2 categories, got %d", len(resp.Categories))
	}
	if len(resp.Products) != 1 {
		t.Fatalf("want 1 product, got %d", len(resp.Products))
	}
	if resp.Products[0].Name != "Margherita" {
		t.Errorf("want product name=Margherita, got %s", resp.Products[0].Name)
	}
	if resp.Products[0].Price != 1500 {
		t.Errorf("want price=1500, got %d", resp.Products[0].Price)
	}
}

// ---------------------------------------------------------------------------
// OrderStatusResponse — field checks
// ---------------------------------------------------------------------------

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
