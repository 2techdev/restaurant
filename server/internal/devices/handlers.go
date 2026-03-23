package devices

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// handleListDevices returns all registered devices for the tenant.
// GET /api/v1/devices
func (m *Module) handleListDevices(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	statusFilter := r.URL.Query().Get("status")

	query := `
		SELECT id, tenant_id, device_name, device_type, status,
		       COALESCE(app_version,''), COALESCE(os_version,''),
		       capabilities, last_seen_at, created_at, updated_at
		FROM device_registrations
		WHERE tenant_id = $1 AND is_deleted = FALSE`

	args := []any{tenantID}
	if statusFilter != "" {
		query += " AND status = $2"
		args = append(args, statusFilter)
	}
	query += " ORDER BY created_at DESC"

	rows, err := m.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list devices")
		return
	}
	defer rows.Close()

	devices := make([]Device, 0)
	for rows.Next() {
		var d Device
		var capsJSON []byte
		var lastSeen sql.NullTime
		if err := rows.Scan(
			&d.ID, &d.TenantID, &d.Name, &d.DeviceType, &d.Status,
			&d.AppVersion, &d.OSVersion,
			&capsJSON, &lastSeen,
			&d.CreatedAt, &d.UpdatedAt,
		); err != nil {
			continue
		}
		if lastSeen.Valid {
			t := lastSeen.Time
			d.LastSeenAt = &t
		}
		if len(capsJSON) > 0 {
			var caps DeviceCapabilities
			if json.Unmarshal(capsJSON, &caps) == nil {
				d.Capabilities = &caps
			}
		}
		devices = append(devices, d)
	}

	response.JSON(w, http.StatusOK, devices)
}

// handleRegisterDevice registers a new POS device.
// POST /api/v1/devices
func (m *Module) handleRegisterDevice(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}

	var req struct {
		Name       string             `json:"name"`
		DeviceType string             `json:"device_type"`
		AppVersion string             `json:"app_version"`
		OSVersion  string             `json:"os_version"`
		Caps       *DeviceCapabilities `json:"capabilities"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name is required")
		return
	}
	if req.DeviceType == "" {
		req.DeviceType = "pos"
	}

	capsJSON := []byte("{}")
	if req.Caps != nil {
		if b, err := json.Marshal(req.Caps); err == nil {
			capsJSON = b
		}
	}

	// Generate a simple token hash placeholder (real token issued via auth module)
	tokenHash := "managed-by-auth"

	var d Device
	var lastSeen sql.NullTime
	err := m.db.QueryRowContext(r.Context(), `
		INSERT INTO device_registrations
		    (tenant_id, device_name, device_type, token_hash, status, app_version, os_version, capabilities)
		VALUES ($1, $2, $3, $4, 'active', $5, $6, $7)
		RETURNING id, tenant_id, device_name, device_type, status,
		          COALESCE(app_version,''), COALESCE(os_version,''),
		          capabilities, last_seen_at, created_at, updated_at
	`, tenantID, req.Name, req.DeviceType, tokenHash,
		req.AppVersion, req.OSVersion, capsJSON,
	).Scan(
		&d.ID, &d.TenantID, &d.Name, &d.DeviceType, &d.Status,
		&d.AppVersion, &d.OSVersion,
		&capsJSON, &lastSeen,
		&d.CreatedAt, &d.UpdatedAt,
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to register device")
		return
	}
	if lastSeen.Valid {
		t := lastSeen.Time
		d.LastSeenAt = &t
	}
	if len(capsJSON) > 0 {
		var caps DeviceCapabilities
		if json.Unmarshal(capsJSON, &caps) == nil {
			d.Capabilities = &caps
		}
	}

	response.Created(w, d)
}

// handleGetDevice returns a single device's details.
// GET /api/v1/devices/{id}
func (m *Module) handleGetDevice(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	deviceID := r.PathValue("id")
	if deviceID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "device id is required")
		return
	}

	var d Device
	var capsJSON []byte
	var lastSeen sql.NullTime

	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, device_name, device_type, status,
		       COALESCE(app_version,''), COALESCE(os_version,''),
		       capabilities, last_seen_at, created_at, updated_at
		FROM device_registrations
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = FALSE
	`, deviceID, tenantID).Scan(
		&d.ID, &d.TenantID, &d.Name, &d.DeviceType, &d.Status,
		&d.AppVersion, &d.OSVersion,
		&capsJSON, &lastSeen,
		&d.CreatedAt, &d.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Device not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to fetch device")
		return
	}
	if lastSeen.Valid {
		t := lastSeen.Time
		d.LastSeenAt = &t
	}
	if len(capsJSON) > 0 {
		var caps DeviceCapabilities
		if json.Unmarshal(capsJSON, &caps) == nil {
			d.Capabilities = &caps
		}
	}

	response.JSON(w, http.StatusOK, d)
}

// handleUpdateCapabilities updates a device's reported capabilities.
// PUT /api/v1/devices/{id}/capabilities
func (m *Module) handleUpdateCapabilities(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	deviceID := r.PathValue("id")
	if deviceID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "device id is required")
		return
	}

	var caps DeviceCapabilities
	if err := json.NewDecoder(r.Body).Decode(&caps); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	capsJSON, err := json.Marshal(caps)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to encode capabilities")
		return
	}

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE device_registrations
		SET capabilities = $3, updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = FALSE
	`, deviceID, tenantID, capsJSON)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update capabilities")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Device not found")
		return
	}

	response.JSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// handleHeartbeat records a device health ping.
// POST /api/v1/devices/{id}/heartbeat
func (m *Module) handleHeartbeat(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	deviceID := r.PathValue("id")
	if deviceID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "device id is required")
		return
	}

	// Optionally accept app/os version updates from device
	var body struct {
		AppVersion string `json:"app_version"`
		OSVersion  string `json:"os_version"`
	}
	json.NewDecoder(r.Body).Decode(&body) //nolint: ignore decode error - body is optional

	now := time.Now()

	result, err := m.db.ExecContext(r.Context(), `
		UPDATE device_registrations
		SET last_seen_at = $3,
		    app_version  = CASE WHEN $4 != '' THEN $4 ELSE app_version END,
		    os_version   = CASE WHEN $5 != '' THEN $5 ELSE os_version  END,
		    updated_at   = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = FALSE
	`, deviceID, tenantID, now, body.AppVersion, body.OSVersion)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to record heartbeat")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Device not found")
		return
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"status":      "ok",
		"last_seen_at": now,
	})
}
