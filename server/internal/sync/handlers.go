package sync

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

const defaultPageSize = 100
const maxPageSize = 500

// handlePush receives a batch of sync events from a device.
// POST /api/v1/sync/push
func (m *Module) handlePush(w http.ResponseWriter, r *http.Request) {
	var req PushRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.DeviceID == "" || req.TenantID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_FIELDS", "device_id and tenant_id are required")
		return
	}

	if len(req.Events) == 0 {
		response.JSON(w, http.StatusOK, PushResponse{Accepted: 0})
		return
	}

	// Stamp tenant/device onto each event (trust client IDs for now).
	for i := range req.Events {
		req.Events[i].TenantID = req.TenantID
		req.Events[i].DeviceID = req.DeviceID
		if req.Events[i].CreatedAt.IsZero() {
			req.Events[i].CreatedAt = time.Now().UTC()
		}
	}

	if err := m.store.SaveEvents(r.Context(), req.Events); err != nil {
		slog.Error("sync push: save events failed", "error", err, "device", req.DeviceID)
		response.Error(w, http.StatusInternalServerError, "STORE_ERROR", "Failed to save events")
		return
	}

	_ = m.store.UpsertDeviceCursor(r.Context(), req.DeviceID, req.TenantID, true, false)

	// Notify other connected devices via WebSocket.
	m.hub.NotifyTenant(req.TenantID, req.DeviceID, len(req.Events))

	response.JSON(w, http.StatusOK, PushResponse{
		Accepted: len(req.Events),
		Rejected: 0,
	})
}

// handlePull returns events after cursor for the requesting device.
// GET /api/v1/sync/pull?cursor=<rfc3339nano>&device_id=<id>&tenant_id=<id>&limit=<n>
func (m *Module) handlePull(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("device_id")
	tenantID := r.URL.Query().Get("tenant_id")
	cursor := r.URL.Query().Get("cursor")

	if deviceID == "" || tenantID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_FIELDS", "device_id and tenant_id are required")
		return
	}

	limit := defaultPageSize
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= maxPageSize {
			limit = n
		}
	}

	events, err := m.store.FetchEventsSince(r.Context(), tenantID, deviceID, cursor, limit+1)
	if err != nil {
		slog.Error("sync pull: fetch failed", "error", err, "device", deviceID)
		response.Error(w, http.StatusInternalServerError, "FETCH_ERROR", "Failed to fetch events")
		return
	}

	hasMore := len(events) > limit
	if hasMore {
		events = events[:limit]
	}

	var newCursor string
	if len(events) > 0 {
		newCursor = events[len(events)-1].ReceivedAt.UTC().Format(time.RFC3339Nano)
	} else {
		newCursor = cursor
	}

	_ = m.store.UpsertDeviceCursor(r.Context(), deviceID, tenantID, false, true)

	response.JSON(w, http.StatusOK, PullResponse{
		Events:  events,
		Cursor:  newCursor,
		HasMore: hasMore,
	})
}

// handleStatus returns sync health info for a device.
// GET /api/v1/sync/status?device_id=<id>&tenant_id=<id>&cursor=<cursor>
func (m *Module) handleStatus(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("device_id")
	tenantID := r.URL.Query().Get("tenant_id")
	cursor := r.URL.Query().Get("cursor")

	if deviceID == "" || tenantID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_FIELDS", "device_id and tenant_id are required")
		return
	}

	lastPush, lastPull, err := m.store.GetDeviceCursor(r.Context(), deviceID, tenantID)
	if err != nil {
		slog.Error("sync status: get cursor failed", "error", err)
	}

	pending, err := m.store.CountPendingForDevice(r.Context(), tenantID, deviceID, cursor)
	if err != nil {
		slog.Error("sync status: count failed", "error", err)
	}

	status := "synced"
	if pending > 0 {
		status = "behind"
	}

	response.JSON(w, http.StatusOK, SyncStatusResponse{
		DeviceID:       deviceID,
		TenantID:       tenantID,
		LastPushAt:     lastPush,
		LastPullAt:     lastPull,
		PendingForPull: pending,
		Status:         status,
	})
}

// handleRegisterDevice registers (or re-registers) a POS/KDS device for sync.
// POST /api/v1/devices/register
//
// Body: { "device_id": "...", "tenant_id": "...", "device_name": "...", "device_type": "pos" }
// Returns: { "device_id": "...", "tenant_id": "...", "registered": true }
func (m *Module) handleRegisterDevice(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID   string `json:"device_id"`
		TenantID   string `json:"tenant_id"`
		DeviceName string `json:"device_name"`
		DeviceType string `json:"device_type"` // pos, kds, kiosk, waiter
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.DeviceID == "" || req.TenantID == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_FIELDS", "device_id and tenant_id are required")
		return
	}

	// Ensure the device has an entry in sync_device_cursors.
	// UpsertDeviceCursor with push=false, pull=false simply creates the row.
	if err := m.store.UpsertDeviceCursor(r.Context(), req.DeviceID, req.TenantID, false, false); err != nil {
		slog.Error("register device: upsert cursor failed", "error", err, "device", req.DeviceID)
		response.Error(w, http.StatusInternalServerError, "STORE_ERROR", "Failed to register device")
		return
	}

	slog.Info("device registered", "device", req.DeviceID, "tenant", req.TenantID, "type", req.DeviceType)

	response.JSON(w, http.StatusOK, map[string]any{
		"device_id":  req.DeviceID,
		"tenant_id":  req.TenantID,
		"registered": true,
	})
}

// Legacy aliases for backward compatibility.
func (m *Module) handleUpload(w http.ResponseWriter, r *http.Request)   { m.handlePush(w, r) }
func (m *Module) handleDownload(w http.ResponseWriter, r *http.Request) { m.handlePull(w, r) }
func (m *Module) handleSeed(w http.ResponseWriter, r *http.Request) {
	response.JSON(w, http.StatusOK, map[string]any{
		"entities": map[string]any{},
		"cursor":   "",
	})
}
