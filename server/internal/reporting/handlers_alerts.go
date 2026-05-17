package reporting

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
	"github.com/lib/pq"
)

type alertDTO struct {
	ID              string                 `json:"id"`
	TenantID        string                 `json:"tenant_id"`
	Name            string                 `json:"name"`
	AlertType       string                 `json:"alert_type"`
	Threshold       map[string]any         `json:"threshold"`
	Recipients      []string               `json:"recipients_emails"`
	CooldownMinutes int                    `json:"cooldown_minutes"`
	Locale          string                 `json:"locale"`
	IsActive        bool                   `json:"is_active"`
	LastTriggeredAt *time.Time             `json:"last_triggered_at,omitempty"`
	LastValue       *float64               `json:"last_value,omitempty"`
	CreatedAt       time.Time              `json:"created_at"`
	UpdatedAt       time.Time              `json:"updated_at"`
}

type alertUpsertReq struct {
	Name            string         `json:"name"`
	AlertType       string         `json:"alert_type"`
	Threshold       map[string]any `json:"threshold"`
	Recipients      []string       `json:"recipients_emails"`
	CooldownMinutes *int           `json:"cooldown_minutes"`
	Locale          string         `json:"locale"`
	IsActive        *bool          `json:"is_active"`
}

var validAlertTypes = map[string]bool{
	"sales_drop":       true,
	"stockout_count":   true,
	"online_ack_delay": true,
	"revenue_target":   true,
	"refund_spike":     true,
	"failed_payments":  true,
}

func validateAlert(req alertUpsertReq) (string, bool) {
	if strings.TrimSpace(req.Name) == "" {
		return "name required", false
	}
	if !validAlertTypes[req.AlertType] {
		return "invalid alert_type", false
	}
	if req.Locale == "" {
		req.Locale = "tr"
	}
	if !validLocales[req.Locale] {
		return "invalid locale", false
	}
	for _, e := range req.Recipients {
		if !strings.Contains(e, "@") {
			return "invalid recipient: " + e, false
		}
	}
	return "", true
}

// GET /api/v1/reporting/alerts
func (m *Module) handleAlertList(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, alert_type, threshold_jsonb,
		       recipients_emails, cooldown_minutes, locale,
		       is_active, last_triggered_at, last_value,
		       created_at, updated_at
		  FROM threshold_alerts
		 WHERE tenant_id = $1
		 ORDER BY created_at DESC
	`, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list alerts")
		return
	}
	defer rows.Close()
	out := make([]alertDTO, 0)
	for rows.Next() {
		var d alertDTO
		var raw []byte
		var lastTrig sql.NullTime
		var lastVal sql.NullFloat64
		if err := rows.Scan(
			&d.ID, &d.TenantID, &d.Name, &d.AlertType, &raw,
			pq.Array(&d.Recipients), &d.CooldownMinutes, &d.Locale,
			&d.IsActive, &lastTrig, &lastVal,
			&d.CreatedAt, &d.UpdatedAt,
		); err != nil {
			continue
		}
		_ = json.Unmarshal(raw, &d.Threshold)
		if lastTrig.Valid {
			t := lastTrig.Time
			d.LastTriggeredAt = &t
		}
		if lastVal.Valid {
			v := lastVal.Float64
			d.LastValue = &v
		}
		out = append(out, d)
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}

// POST /api/v1/reporting/alerts
func (m *Module) handleAlertCreate(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	var req alertUpsertReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.Locale == "" {
		req.Locale = "tr"
	}
	if msg, ok := validateAlert(req); !ok {
		response.Error(w, http.StatusBadRequest, "VALIDATION", msg)
		return
	}
	cooldown := 60
	if req.CooldownMinutes != nil {
		cooldown = *req.CooldownMinutes
	}
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	thresholdJSON, _ := json.Marshal(req.Threshold)
	if len(thresholdJSON) == 0 {
		thresholdJSON = []byte("{}")
	}
	id := uuid.New()
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO threshold_alerts
			(id, tenant_id, name, alert_type, threshold_jsonb,
			 recipients_emails, cooldown_minutes, locale, is_active)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
	`, id, tenantID, req.Name, req.AlertType, thresholdJSON,
		pq.Array(req.Recipients), cooldown, req.Locale, isActive)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	response.JSON(w, http.StatusCreated, map[string]any{"id": id})
}

// PUT /api/v1/reporting/alerts/{id}
func (m *Module) handleAlertUpdate(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	var req alertUpsertReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.Locale == "" {
		req.Locale = "tr"
	}
	if msg, ok := validateAlert(req); !ok {
		response.Error(w, http.StatusBadRequest, "VALIDATION", msg)
		return
	}
	cooldown := 60
	if req.CooldownMinutes != nil {
		cooldown = *req.CooldownMinutes
	}
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	thresholdJSON, _ := json.Marshal(req.Threshold)
	if len(thresholdJSON) == 0 {
		thresholdJSON = []byte("{}")
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE threshold_alerts
		   SET name = $3, alert_type = $4, threshold_jsonb = $5,
		       recipients_emails = $6, cooldown_minutes = $7,
		       locale = $8, is_active = $9, updated_at = NOW()
		 WHERE id = $1 AND tenant_id = $2
	`, id, tenantID, req.Name, req.AlertType, thresholdJSON,
		pq.Array(req.Recipients), cooldown, req.Locale, isActive)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Alert not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /api/v1/reporting/alerts/{id}
func (m *Module) handleAlertDelete(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	res, err := m.db.ExecContext(r.Context(), `
		DELETE FROM threshold_alerts WHERE id = $1 AND tenant_id = $2
	`, id, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Alert not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// POST /api/v1/reporting/alerts/{id}/test
//
// Forces an evaluation now and bypasses the cooldown so the operator can
// validate "does this fire?" without waiting.
func (m *Module) handleAlertTest(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	var a alertRow
	err := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, name, alert_type, threshold_jsonb,
		       recipients_emails, cooldown_minutes, locale, last_triggered_at
		  FROM threshold_alerts
		 WHERE id = $1 AND tenant_id = $2
	`, id, tenantID).Scan(
		&a.ID, &a.TenantID, &a.Name, &a.AlertType, &a.ThresholdJSON,
		pq.Array(&a.Recipients), &a.CooldownMinutes, &a.Locale, &a.LastTriggeredAt,
	)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Alert not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	// Bypass cooldown by clearing LastTriggeredAt for the in-memory copy.
	a.LastTriggeredAt = sql.NullTime{}
	m.evaluateOne(r.Context(), a, time.Now())
	response.JSON(w, http.StatusOK, map[string]any{"status": "evaluated"})
}

// GET /api/v1/reporting/alerts/logs?limit=50
func (m *Module) handleAlertLogs(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	limit := 50
	if s := r.URL.Query().Get("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, alert_id, triggered_at, value, COALESCE(message,''),
		       sent_to, status, COALESCE(error_message,'')
		  FROM alert_logs
		 WHERE tenant_id = $1
		 ORDER BY triggered_at DESC
		 LIMIT $2
	`, tenantID, limit)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	defer rows.Close()
	type logRow struct {
		ID           string    `json:"id"`
		AlertID      *string   `json:"alert_id,omitempty"`
		TriggeredAt  time.Time `json:"triggered_at"`
		Value        *float64  `json:"value,omitempty"`
		Message      string    `json:"message"`
		SentTo       []string  `json:"sent_to"`
		Status       string    `json:"status"`
		ErrorMessage string    `json:"error_message,omitempty"`
	}
	out := make([]logRow, 0, limit)
	for rows.Next() {
		var l logRow
		var aid sql.NullString
		var val sql.NullFloat64
		if err := rows.Scan(
			&l.ID, &aid, &l.TriggeredAt, &val, &l.Message,
			pq.Array(&l.SentTo), &l.Status, &l.ErrorMessage,
		); err == nil {
			if aid.Valid {
				v := aid.String
				l.AlertID = &v
			}
			if val.Valid {
				v := val.Float64
				l.Value = &v
			}
			out = append(out, l)
		}
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}
