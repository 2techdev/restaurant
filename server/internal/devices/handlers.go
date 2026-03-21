package devices

import (
	"encoding/json"
	"net/http"

	"github.com/gastrocore/server/internal/shared/response"
)

// handleListDevices returns all registered devices for the tenant.
// GET /api/v1/devices
func (m *Module) handleListDevices(w http.ResponseWriter, r *http.Request) {
	// TODO: Extract tenant_id from context
	// TODO: Query devices with optional status filter

	response.JSON(w, http.StatusOK, []Device{})
}

// handleRegisterDevice registers a new POS device.
// POST /api/v1/devices
func (m *Module) handleRegisterDevice(w http.ResponseWriter, r *http.Request) {
	var req Device
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	// TODO: Validate required fields
	// TODO: Check license allows another device
	// TODO: Generate device ID and token
	// TODO: Insert into database

	response.Created(w, req)
}

// handleGetDevice returns a single device's details.
// GET /api/v1/devices/{id}
func (m *Module) handleGetDevice(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	_ = id

	// TODO: Fetch device by ID and tenant
	// TODO: Include last heartbeat info

	response.JSON(w, http.StatusOK, Device{})
}

// handleUpdateCapabilities updates a device's reported capabilities.
// PUT /api/v1/devices/{id}/capabilities
func (m *Module) handleUpdateCapabilities(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	_ = id

	var caps DeviceCapabilities
	if err := json.NewDecoder(r.Body).Decode(&caps); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	// TODO: Update device capabilities in database

	response.JSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// handleHeartbeat records a device health ping.
// POST /api/v1/devices/{id}/heartbeat
func (m *Module) handleHeartbeat(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	_ = id

	// TODO: Update last_seen_at for the device
	// TODO: Optionally accept device metrics (battery, disk, etc.)

	response.JSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
