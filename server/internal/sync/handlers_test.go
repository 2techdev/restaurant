package sync

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// ---------------------------------------------------------------------------
// Mock store
// ---------------------------------------------------------------------------

type mockStore struct {
	savedEvents  []SyncEvent
	fetchResult  []SyncEvent
	fetchErr     error
	countResult  int
	upsertErr    error
	lastPush     *time.Time
	lastPull     *time.Time
	getCursorErr error
}

func (m *mockStore) SaveEvents(_ context.Context, events []SyncEvent) error {
	m.savedEvents = append(m.savedEvents, events...)
	return nil
}

func (m *mockStore) FetchEventsSince(_ context.Context, _, _, _ string, _ int) ([]SyncEvent, error) {
	return m.fetchResult, m.fetchErr
}

func (m *mockStore) CountPendingForDevice(_ context.Context, _, _, _ string) (int, error) {
	return m.countResult, nil
}

func (m *mockStore) UpsertDeviceCursor(_ context.Context, _, _ string, _, _ bool) error {
	return m.upsertErr
}

func (m *mockStore) GetDeviceCursor(_ context.Context, _, _ string) (*time.Time, *time.Time, error) {
	return m.lastPush, m.lastPull, m.getCursorErr
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

func newTestModule(s Store) *Module {
	return &Module{store: s, hub: newHub()}
}

// ---------------------------------------------------------------------------
// handlePush tests
// ---------------------------------------------------------------------------

func TestHandlePush_AcceptsValidBatch(t *testing.T) {
	ms := &mockStore{}
	mod := newTestModule(ms)

	body := PushRequest{
		DeviceID: "dev-1",
		TenantID: "tenant-1",
		Events: []SyncEvent{
			{ID: "evt-1", TableName: "tickets", RecordID: "tkt-1", Operation: "insert"},
			{ID: "evt-2", TableName: "tickets", RecordID: "tkt-2", Operation: "update"},
		},
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	mod.handlePush(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp PushResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if resp.Accepted != 2 {
		t.Errorf("expected accepted=2, got %d", resp.Accepted)
	}
	if resp.Rejected != 0 {
		t.Errorf("expected rejected=0, got %d", resp.Rejected)
	}
	if len(ms.savedEvents) != 2 {
		t.Errorf("expected 2 saved events, got %d", len(ms.savedEvents))
	}
}

func TestHandlePush_EmptyBatchReturnsZero(t *testing.T) {
	ms := &mockStore{}
	mod := newTestModule(ms)

	body := PushRequest{DeviceID: "dev-1", TenantID: "tenant-1", Events: nil}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	mod.handlePush(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var resp PushResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Accepted != 0 {
		t.Errorf("expected 0 accepted for empty batch, got %d", resp.Accepted)
	}
}

func TestHandlePush_MissingDeviceID(t *testing.T) {
	ms := &mockStore{}
	mod := newTestModule(ms)

	body := PushRequest{TenantID: "tenant-1", Events: []SyncEvent{{ID: "e1"}}}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	mod.handlePush(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestHandlePush_InvalidBody(t *testing.T) {
	mod := newTestModule(&mockStore{})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync/push", bytes.NewReader([]byte("not json")))
	w := httptest.NewRecorder()
	mod.handlePush(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for invalid JSON, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// handlePull tests
// ---------------------------------------------------------------------------

func TestHandlePull_ReturnsEvents(t *testing.T) {
	now := time.Now().UTC()
	ms := &mockStore{
		fetchResult: []SyncEvent{
			{ID: "e1", TableName: "products", RecordID: "p1", Operation: "insert", ReceivedAt: now},
		},
	}
	mod := newTestModule(ms)

	req := httptest.NewRequest(http.MethodGet,
		"/api/v1/sync/pull?device_id=dev-1&tenant_id=tenant-1&cursor=", nil)
	w := httptest.NewRecorder()

	mod.handlePull(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp PullResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Events) != 1 {
		t.Errorf("expected 1 event, got %d", len(resp.Events))
	}
	if resp.HasMore {
		t.Error("expected has_more=false")
	}
}

func TestHandlePull_HasMoreWhenOverLimit(t *testing.T) {
	events := make([]SyncEvent, defaultPageSize+1)
	for i := range events {
		events[i] = SyncEvent{ID: "e", ReceivedAt: time.Now()}
	}
	ms := &mockStore{fetchResult: events}
	mod := newTestModule(ms)

	req := httptest.NewRequest(http.MethodGet,
		"/api/v1/sync/pull?device_id=dev-1&tenant_id=tenant-1", nil)
	w := httptest.NewRecorder()

	mod.handlePull(w, req)

	var resp PullResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if !resp.HasMore {
		t.Error("expected has_more=true when server returns limit+1 events")
	}
	if len(resp.Events) != defaultPageSize {
		t.Errorf("expected %d events, got %d", defaultPageSize, len(resp.Events))
	}
}

func TestHandlePull_MissingParams(t *testing.T) {
	mod := newTestModule(&mockStore{})
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/pull?device_id=dev-1", nil)
	w := httptest.NewRecorder()
	mod.handlePull(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// handleRegisterDevice tests
// ---------------------------------------------------------------------------

func TestHandleRegisterDevice_Success(t *testing.T) {
	ms := &mockStore{}
	mod := newTestModule(ms)

	body := map[string]string{
		"device_id":   "pos-001",
		"tenant_id":   "tenant-42",
		"device_name": "Main POS",
		"device_type": "pos",
	}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices/register", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	mod.handleRegisterDevice(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp map[string]any
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["registered"] != true {
		t.Errorf("expected registered=true, got %v", resp["registered"])
	}
	if resp["device_id"] != "pos-001" {
		t.Errorf("expected device_id=pos-001, got %v", resp["device_id"])
	}
}

func TestHandleRegisterDevice_MissingTenantID(t *testing.T) {
	mod := newTestModule(&mockStore{})
	body := map[string]string{"device_id": "dev-1"}
	b, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices/register", bytes.NewReader(b))
	w := httptest.NewRecorder()
	mod.handleRegisterDevice(w, req)
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

// ---------------------------------------------------------------------------
// Hub tests
// ---------------------------------------------------------------------------

func TestHub_NotifyTenantSkipsSender(t *testing.T) {
	hub := newHub()

	received := make(chan []byte, 4)
	c1 := &client{deviceID: "sender", tenantID: "t1", send: make(chan []byte, 4)}
	c2 := &client{deviceID: "receiver", tenantID: "t1", send: received}

	hub.register(c1)
	hub.register(c2)

	hub.NotifyTenant("t1", "sender", 3)

	select {
	case msg := <-received:
		var notif WSNotification
		if err := json.Unmarshal(msg, &notif); err != nil {
			t.Fatal(err)
		}
		if notif.Count != 3 {
			t.Errorf("expected count=3, got %d", notif.Count)
		}
		if notif.Type != "new_events" {
			t.Errorf("expected type=new_events, got %s", notif.Type)
		}
	default:
		t.Error("expected receiver to get notification")
	}

	// Sender should NOT receive anything.
	select {
	case <-c1.send:
		t.Error("sender should not receive its own notification")
	default:
	}
}

func TestHub_NotifyTenantSkipsOtherTenants(t *testing.T) {
	hub := newHub()
	c1 := &client{deviceID: "d1", tenantID: "tenant-A", send: make(chan []byte, 4)}
	c2 := &client{deviceID: "d2", tenantID: "tenant-B", send: make(chan []byte, 4)}
	hub.register(c1)
	hub.register(c2)

	hub.NotifyTenant("tenant-A", "nobody", 1)

	select {
	case <-c2.send:
		t.Error("cross-tenant notification should not be delivered")
	default:
	}
}

func TestHub_RegisterReplacesOldConnection(t *testing.T) {
	hub := newHub()
	old := &client{deviceID: "dev-1", tenantID: "t1", send: make(chan []byte, 1)}
	hub.register(old)

	fresh := &client{deviceID: "dev-1", tenantID: "t1", send: make(chan []byte, 1)}
	hub.register(fresh)

	hub.mu.RLock()
	current := hub.clients["dev-1"]
	hub.mu.RUnlock()

	if current != fresh {
		t.Error("expected fresh client to replace old one")
	}
}

// ---------------------------------------------------------------------------
// handleStatus tests
// ---------------------------------------------------------------------------

func TestHandleStatus_ReturnsOK(t *testing.T) {
	ms := &mockStore{countResult: 5}
	mod := newTestModule(ms)

	req := httptest.NewRequest(http.MethodGet,
		"/api/v1/sync/status?device_id=dev-1&tenant_id=tenant-1", nil)
	w := httptest.NewRecorder()

	mod.handleStatus(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp SyncStatusResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Status != "behind" {
		t.Errorf("expected status=behind (5 pending), got %s", resp.Status)
	}
}
