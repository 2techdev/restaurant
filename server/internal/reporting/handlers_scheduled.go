package reporting

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
	"github.com/lib/pq"
)

type scheduledDTO struct {
	ID              string                 `json:"id"`
	TenantID        string                 `json:"tenant_id"`
	Name            string                 `json:"name"`
	ReportType      string                 `json:"report_type"`
	ScheduleCron    string                 `json:"schedule_cron"`
	Recipients      []string               `json:"recipients_emails"`
	Format          string                 `json:"format"`
	Filters         map[string]any         `json:"filters"`
	Locale          string                 `json:"locale"`
	IsActive        bool                   `json:"is_active"`
	LastSentAt      *time.Time             `json:"last_sent_at,omitempty"`
	LastStatus      string                 `json:"last_status,omitempty"`
	NextRunAt       *time.Time             `json:"next_run_at,omitempty"`
	CreatedAt       time.Time              `json:"created_at"`
	UpdatedAt       time.Time              `json:"updated_at"`
}

// GET /api/v1/reporting/scheduled
func (m *Module) handleScheduledList(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, report_type, schedule_cron,
		       recipients_emails, format, filters_jsonb, locale,
		       is_active, last_sent_at, last_status, next_run_at,
		       created_at, updated_at
		  FROM scheduled_reports
		 WHERE tenant_id = $1
		 ORDER BY created_at DESC
	`, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list scheduled reports")
		return
	}
	defer rows.Close()
	out := make([]scheduledDTO, 0)
	for rows.Next() {
		var d scheduledDTO
		var raw []byte
		var lastSent sql.NullTime
		var lastStatus sql.NullString
		var nextRun sql.NullTime
		if err := rows.Scan(
			&d.ID, &d.TenantID, &d.Name, &d.ReportType, &d.ScheduleCron,
			pq.Array(&d.Recipients), &d.Format, &raw, &d.Locale,
			&d.IsActive, &lastSent, &lastStatus, &nextRun,
			&d.CreatedAt, &d.UpdatedAt,
		); err != nil {
			continue
		}
		_ = json.Unmarshal(raw, &d.Filters)
		if lastSent.Valid {
			t := lastSent.Time
			d.LastSentAt = &t
		}
		if lastStatus.Valid {
			d.LastStatus = lastStatus.String
		}
		if nextRun.Valid {
			t := nextRun.Time
			d.NextRunAt = &t
		}
		out = append(out, d)
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}

type scheduledUpsertReq struct {
	Name         string         `json:"name"`
	ReportType   string         `json:"report_type"`
	ScheduleCron string         `json:"schedule_cron"`
	Recipients   []string       `json:"recipients_emails"`
	Format       string         `json:"format"`
	Filters      map[string]any `json:"filters"`
	Locale       string         `json:"locale"`
	IsActive     *bool          `json:"is_active"`
}

var validReportTypes = map[string]bool{
	"daily_digest":      true,
	"sales_summary":     true,
	"hourly_sales":      true,
	"staff_performance": true,
	"inventory_health":  true,
	"customer_activity": true,
}

var validFormats = map[string]bool{"html": true, "pdf": true, "csv": true}
var validLocales = map[string]bool{"tr": true, "de": true, "en": true, "fr": true, "it": true}

func (m *Module) validateScheduled(req scheduledUpsertReq) (string, bool) {
	if strings.TrimSpace(req.Name) == "" {
		return "name required", false
	}
	if !validReportTypes[req.ReportType] {
		return "invalid report_type", false
	}
	if _, err := parseCron(req.ScheduleCron); err != nil {
		return "invalid schedule_cron: " + err.Error(), false
	}
	if req.Format == "" {
		req.Format = "html"
	}
	if !validFormats[req.Format] {
		return "invalid format", false
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

// POST /api/v1/reporting/scheduled
func (m *Module) handleScheduledCreate(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	var req scheduledUpsertReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.Format == "" {
		req.Format = "html"
	}
	if req.Locale == "" {
		req.Locale = "tr"
	}
	if msg, ok := m.validateScheduled(req); !ok {
		response.Error(w, http.StatusBadRequest, "VALIDATION", msg)
		return
	}
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	id := uuid.New()
	filtersJSON, _ := json.Marshal(req.Filters)
	if len(filtersJSON) == 0 {
		filtersJSON = []byte("{}")
	}

	// Pre-compute next_run_at so the scheduler can pick it up immediately.
	var nextRun *time.Time
	if expr, err := parseCron(req.ScheduleCron); err == nil {
		n := expr.Next(time.Now())
		if !n.IsZero() {
			nextRun = &n
		}
	}

	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO scheduled_reports
			(id, tenant_id, name, report_type, schedule_cron, recipients_emails,
			 format, filters_jsonb, locale, is_active, next_run_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
	`, id, tenantID, req.Name, req.ReportType, req.ScheduleCron,
		pq.Array(req.Recipients), req.Format, filtersJSON, req.Locale,
		isActive, nextRun)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	response.JSON(w, http.StatusCreated, map[string]any{"id": id})
}

// PUT /api/v1/reporting/scheduled/{id}
func (m *Module) handleScheduledUpdate(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	var req scheduledUpsertReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON body")
		return
	}
	if req.Format == "" {
		req.Format = "html"
	}
	if req.Locale == "" {
		req.Locale = "tr"
	}
	if msg, ok := m.validateScheduled(req); !ok {
		response.Error(w, http.StatusBadRequest, "VALIDATION", msg)
		return
	}
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	filtersJSON, _ := json.Marshal(req.Filters)
	if len(filtersJSON) == 0 {
		filtersJSON = []byte("{}")
	}
	var nextRun *time.Time
	if expr, err := parseCron(req.ScheduleCron); err == nil {
		n := expr.Next(time.Now())
		if !n.IsZero() {
			nextRun = &n
		}
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE scheduled_reports
		   SET name = $3, report_type = $4, schedule_cron = $5,
		       recipients_emails = $6, format = $7, filters_jsonb = $8,
		       locale = $9, is_active = $10, next_run_at = $11,
		       updated_at = NOW()
		 WHERE id = $1 AND tenant_id = $2
	`, id, tenantID, req.Name, req.ReportType, req.ScheduleCron,
		pq.Array(req.Recipients), req.Format, filtersJSON, req.Locale,
		isActive, nextRun)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Scheduled report not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// DELETE /api/v1/reporting/scheduled/{id}
func (m *Module) handleScheduledDelete(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	res, err := m.db.ExecContext(r.Context(), `
		DELETE FROM scheduled_reports WHERE id = $1 AND tenant_id = $2
	`, id, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Scheduled report not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// POST /api/v1/reporting/scheduled/{id}/send-now
//
// Renders and dispatches the report synchronously, then writes a log row
// with trigger_source='manual'. Returns the log id for client convenience.
func (m *Module) handleScheduledSendNow(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	id := r.PathValue("id")
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	row, err := m.scheduledFromID(r.Context(), id, tenantID)
	if errors.Is(err, errNotFound) {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Scheduled report not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	m.sendScheduled(r.Context(), row, "manual")
	response.JSON(w, http.StatusOK, map[string]any{"status": "dispatched", "recipients": row.Recipients})
}

// GET /api/v1/reporting/logs?limit=50
func (m *Module) handleReportLogs(w http.ResponseWriter, r *http.Request) {
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
		SELECT id, scheduled_report_id, report_type, sent_at, sent_to_emails,
		       sent_recipients_count, status, COALESCE(error_message,''),
		       duration_ms, trigger_source
		  FROM report_logs
		 WHERE tenant_id = $1
		 ORDER BY sent_at DESC
		 LIMIT $2
	`, tenantID, limit)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	defer rows.Close()
	type logRow struct {
		ID               string    `json:"id"`
		ScheduledID      *string   `json:"scheduled_report_id,omitempty"`
		ReportType       string    `json:"report_type"`
		SentAt           time.Time `json:"sent_at"`
		SentTo           []string  `json:"sent_to_emails"`
		RecipientCount   int       `json:"sent_recipients_count"`
		Status           string    `json:"status"`
		ErrorMessage     string    `json:"error_message,omitempty"`
		DurationMs       int       `json:"duration_ms,omitempty"`
		TriggerSource    string    `json:"trigger_source"`
	}
	out := make([]logRow, 0, limit)
	for rows.Next() {
		var l logRow
		var sid sql.NullString
		if err := rows.Scan(
			&l.ID, &sid, &l.ReportType, &l.SentAt, pq.Array(&l.SentTo),
			&l.RecipientCount, &l.Status, &l.ErrorMessage,
			&l.DurationMs, &l.TriggerSource,
		); err == nil {
			if sid.Valid {
				v := sid.String
				l.ScheduledID = &v
			}
			out = append(out, l)
		}
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}

// GET /api/v1/reporting/digest/preview?date=YYYY-MM-DD&locale=tr
//
// Renders the daily digest HTML without sending. Useful for the backoffice
// "preview" before subscribing.
func (m *Module) handleDigestPreview(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	dateStr := r.URL.Query().Get("date")
	locale := r.URL.Query().Get("locale")
	if locale == "" {
		locale = "tr"
	}
	day := time.Now().AddDate(0, 0, -1)
	if dateStr != "" {
		if t, err := time.Parse("2006-01-02", dateStr); err == nil {
			day = t
		}
	}
	d, err := m.LoadDigest(r.Context(), tenantID, day)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DIGEST_ERROR", err.Error())
		return
	}
	subj, body, err := m.RenderDigest(d, locale)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "RENDER_ERROR", err.Error())
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("X-Subject", subj)
	_, _ = w.Write([]byte(body))
}

