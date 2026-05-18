package tasks

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

// resolveTenant mirrors the pattern used elsewhere — JWT first, then
// ?tenant_id= fallback for the admin/cron tooling.
func resolveTenant(r *http.Request) string {
	if t := middleware.GetTenantID(r.Context()); uuid.IsValid(t) {
		return t
	}
	if q := r.URL.Query().Get("tenant_id"); uuid.IsValid(q) {
		return q
	}
	return ""
}

func resolveUser(r *http.Request) string {
	if u := middleware.GetUserID(r.Context()); uuid.IsValid(u) {
		return u
	}
	if q := r.URL.Query().Get("user_id"); uuid.IsValid(q) {
		return q
	}
	return ""
}

// ---------------------------------------------------------------------------
// Templates — CRUD
// ---------------------------------------------------------------------------

const templateColumns = `
	id, tenant_id, name, name_jsonb,
	description, description_jsonb,
	category, schedule_cron, items_jsonb,
	is_active, created_by_user_id,
	created_at, updated_at`

// templateColumnsT mirrors [templateColumns] but with the `t.` alias so
// it can sit alongside `instanceColumns` (`i.`) inside a join without
// Postgres flagging ambiguous column names like `id` / `tenant_id`.
const templateColumnsT = `
	t.id, t.tenant_id, t.name, t.name_jsonb,
	t.description, t.description_jsonb,
	t.category, t.schedule_cron, t.items_jsonb,
	t.is_active, t.created_by_user_id,
	t.created_at, t.updated_at`

func (m *Module) handleListTemplates(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	query := `SELECT ` + templateColumns + `
		FROM task_templates
		WHERE tenant_id = $1 AND is_deleted = FALSE
		ORDER BY category, name`
	rows, err := m.db.QueryContext(r.Context(), query, tenantID)
	if err != nil {
		slog.Error("tasks: list templates", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list templates")
		return
	}
	defer rows.Close()
	out := []TaskTemplate{}
	for rows.Next() {
		t, err := scanTemplate(rows)
		if err != nil {
			slog.Error("tasks: scan template", "error", err)
			continue
		}
		out = append(out, t)
	}
	response.Paginated(w, out, "", false)
}

type templatePayload struct {
	Name             string          `json:"name"`
	NameJSONB        json.RawMessage `json:"name_jsonb,omitempty"`
	Description      *string         `json:"description,omitempty"`
	DescriptionJSONB json.RawMessage `json:"description_jsonb,omitempty"`
	Category         string          `json:"category"`
	ScheduleCron     string          `json:"schedule_cron"`
	Items            json.RawMessage `json:"items_jsonb"`
	IsActive         *bool           `json:"is_active,omitempty"`
}

func validateTemplatePayload(p *templatePayload) error {
	if strings.TrimSpace(p.Name) == "" {
		return errors.New("name is required")
	}
	switch p.Category {
	case "", "opening", "closing", "temperature", "cleaning", "delivery", "custom":
		if p.Category == "" {
			p.Category = "custom"
		}
	default:
		return fmt.Errorf("invalid category %q", p.Category)
	}
	if strings.TrimSpace(p.ScheduleCron) == "" {
		p.ScheduleCron = "0 6 * * *"
	}
	if _, err := parseCron(p.ScheduleCron); err != nil {
		return fmt.Errorf("invalid schedule_cron: %w", err)
	}
	if len(p.Items) == 0 {
		p.Items = json.RawMessage("[]")
	}
	if len(p.NameJSONB) == 0 {
		p.NameJSONB = json.RawMessage("{}")
	}
	if len(p.DescriptionJSONB) == 0 {
		p.DescriptionJSONB = json.RawMessage("{}")
	}
	return nil
}

func (m *Module) handleCreateTemplate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var p templatePayload
	if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", err.Error())
		return
	}
	if err := validateTemplatePayload(&p); err != nil {
		response.Error(w, http.StatusBadRequest, "VALIDATION", err.Error())
		return
	}
	active := true
	if p.IsActive != nil {
		active = *p.IsActive
	}
	id := uuid.New()
	var createdBy sql.NullString
	if u := resolveUser(r); u != "" {
		createdBy = sql.NullString{String: u, Valid: true}
	}
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO task_templates
		    (id, tenant_id, name, name_jsonb, description, description_jsonb,
		     category, schedule_cron, items_jsonb, is_active, created_by_user_id)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
	`, id, tenantID, p.Name, []byte(p.NameJSONB),
		p.Description, []byte(p.DescriptionJSONB),
		p.Category, p.ScheduleCron, []byte(p.Items),
		active, createdBy,
	)
	if err != nil {
		slog.Error("tasks: insert template", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	t, err := m.fetchTemplate(r.Context(), tenantID, id)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	response.Created(w, t)
}

func (m *Module) handleGetTemplate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Bad template id")
		return
	}
	t, err := m.fetchTemplate(r.Context(), tenantID, id)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Template not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	response.JSON(w, http.StatusOK, t)
}

func (m *Module) fetchTemplate(ctx context.Context, tenantID, id string) (TaskTemplate, error) {
	row := m.db.QueryRowContext(ctx, `SELECT `+templateColumns+`
		FROM task_templates WHERE id=$1 AND tenant_id=$2 AND is_deleted=FALSE`,
		id, tenantID)
	return scanTemplate(row)
}

func (m *Module) handleUpdateTemplate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Bad template id")
		return
	}
	var p templatePayload
	if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", err.Error())
		return
	}
	if err := validateTemplatePayload(&p); err != nil {
		response.Error(w, http.StatusBadRequest, "VALIDATION", err.Error())
		return
	}
	active := true
	if p.IsActive != nil {
		active = *p.IsActive
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE task_templates SET
		    name=$1, name_jsonb=$2,
		    description=$3, description_jsonb=$4,
		    category=$5, schedule_cron=$6, items_jsonb=$7,
		    is_active=$8, updated_at=NOW()
		WHERE id=$9 AND tenant_id=$10 AND is_deleted=FALSE
	`, p.Name, []byte(p.NameJSONB),
		p.Description, []byte(p.DescriptionJSONB),
		p.Category, p.ScheduleCron, []byte(p.Items),
		active, id, tenantID,
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Template not found")
		return
	}
	t, err := m.fetchTemplate(r.Context(), tenantID, id)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	response.JSON(w, http.StatusOK, t)
}

func (m *Module) handleDeleteTemplate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Bad template id")
		return
	}
	res, err := m.db.ExecContext(r.Context(),
		`UPDATE task_templates SET is_deleted=TRUE, is_active=FALSE, updated_at=NOW()
		 WHERE id=$1 AND tenant_id=$2`, id, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Template not found")
		return
	}
	response.NoContent(w)
}

// ---------------------------------------------------------------------------
// Instances — read + complete
// ---------------------------------------------------------------------------

const instanceColumns = `
	i.id, i.template_id, i.tenant_id, i.scheduled_for, i.status,
	i.items_data_jsonb, i.completed_at, i.completed_by_user_id,
	i.correction_notes, i.is_locked, i.created_at, i.updated_at`

func scanInstance(s interface{ Scan(...any) error }) (TaskInstance, error) {
	var inst TaskInstance
	var items, corrections sql.NullString
	var completedAt sql.NullTime
	var completedBy sql.NullString
	err := s.Scan(
		&inst.ID, &inst.TemplateID, &inst.TenantID,
		&inst.ScheduledFor, &inst.Status,
		&items, &completedAt, &completedBy,
		&corrections, &inst.IsLocked,
		&inst.CreatedAt, &inst.UpdatedAt,
	)
	if err != nil {
		return inst, err
	}
	if items.Valid {
		inst.ItemsData = []byte(items.String)
	} else {
		inst.ItemsData = []byte("[]")
	}
	if corrections.Valid {
		inst.CorrectionNotes = []byte(corrections.String)
	} else {
		inst.CorrectionNotes = []byte("[]")
	}
	if completedAt.Valid {
		t := completedAt.Time
		inst.CompletedAt = &t
	}
	if completedBy.Valid {
		inst.CompletedByUserID = &completedBy.String
	}
	return inst, nil
}

// handleToday returns instances scheduled for the calendar day in the
// server's local TZ — pending + in_progress, so the POS app can render
// the operator's outstanding list at a glance.
func (m *Module) handleToday(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	now := time.Now()
	dayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	dayEnd := dayStart.Add(24 * time.Hour)

	// Join template so we can hydrate the name/category for the POS UI
	// without a second round-trip.
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT `+instanceColumns+`,
		       `+templateColumnsT+`
		FROM task_instances i
		JOIN task_templates t ON t.id = i.template_id
		WHERE i.tenant_id = $1
		  AND i.scheduled_for >= $2 AND i.scheduled_for < $3
		ORDER BY i.scheduled_for ASC
	`, tenantID, dayStart, dayEnd)
	if err != nil {
		slog.Error("tasks: today query", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	defer rows.Close()

	out := []TaskInstance{}
	for rows.Next() {
		// Use a custom scan because we need both instance + template
		// columns out of the same row.
		var inst TaskInstance
		var items, corrections sql.NullString
		var completedAt sql.NullTime
		var completedBy sql.NullString
		var tpl TaskTemplate
		var nameJSONB, descJSONB, tplItems sql.NullString
		var desc sql.NullString
		var createdBy sql.NullString
		err := rows.Scan(
			&inst.ID, &inst.TemplateID, &inst.TenantID,
			&inst.ScheduledFor, &inst.Status,
			&items, &completedAt, &completedBy,
			&corrections, &inst.IsLocked,
			&inst.CreatedAt, &inst.UpdatedAt,

			&tpl.ID, &tpl.TenantID, &tpl.Name, &nameJSONB,
			&desc, &descJSONB,
			&tpl.Category, &tpl.ScheduleCron, &tplItems,
			&tpl.IsActive, &createdBy,
			&tpl.CreatedAt, &tpl.UpdatedAt,
		)
		if err != nil {
			slog.Error("tasks: today scan", "error", err)
			continue
		}
		if items.Valid {
			inst.ItemsData = []byte(items.String)
		} else {
			inst.ItemsData = []byte("[]")
		}
		if corrections.Valid {
			inst.CorrectionNotes = []byte(corrections.String)
		} else {
			inst.CorrectionNotes = []byte("[]")
		}
		if completedAt.Valid {
			t := completedAt.Time
			inst.CompletedAt = &t
		}
		if completedBy.Valid {
			inst.CompletedByUserID = &completedBy.String
		}
		if nameJSONB.Valid {
			tpl.NameJSONB = []byte(nameJSONB.String)
		}
		if descJSONB.Valid {
			tpl.DescriptionJSONB = []byte(descJSONB.String)
		}
		if desc.Valid {
			tpl.Description = &desc.String
		}
		if tplItems.Valid {
			tpl.Items = []byte(tplItems.String)
		} else {
			tpl.Items = []byte("[]")
		}
		if createdBy.Valid {
			tpl.CreatedByUserID = &createdBy.String
		}
		inst.Template = &tpl
		out = append(out, inst)
	}
	response.Paginated(w, out, "", false)
}

// handleListInstances accepts optional ?status, ?from, ?to, ?template_id.
func (m *Module) handleListInstances(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	args := []any{tenantID}
	query := `SELECT ` + instanceColumns + `
		FROM task_instances i
		WHERE i.tenant_id = $1`
	if s := r.URL.Query().Get("status"); s != "" {
		args = append(args, s)
		query += fmt.Sprintf(" AND i.status = $%d", len(args))
	}
	if tpl := r.URL.Query().Get("template_id"); uuid.IsValid(tpl) {
		args = append(args, tpl)
		query += fmt.Sprintf(" AND i.template_id = $%d", len(args))
	}
	if from := r.URL.Query().Get("from"); from != "" {
		if t, err := time.Parse(time.RFC3339, from); err == nil {
			args = append(args, t)
			query += fmt.Sprintf(" AND i.scheduled_for >= $%d", len(args))
		}
	}
	if to := r.URL.Query().Get("to"); to != "" {
		if t, err := time.Parse(time.RFC3339, to); err == nil {
			args = append(args, t)
			query += fmt.Sprintf(" AND i.scheduled_for < $%d", len(args))
		}
	}
	query += " ORDER BY i.scheduled_for DESC LIMIT 500"
	rows, err := m.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	defer rows.Close()
	out := []TaskInstance{}
	for rows.Next() {
		inst, err := scanInstance(rows)
		if err != nil {
			continue
		}
		out = append(out, inst)
	}
	response.Paginated(w, out, "", false)
}

func (m *Module) handleGetInstance(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Bad instance id")
		return
	}
	row := m.db.QueryRowContext(r.Context(),
		`SELECT `+instanceColumns+` FROM task_instances i WHERE i.id=$1 AND i.tenant_id=$2`,
		id, tenantID)
	inst, err := scanInstance(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Instance not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	response.JSON(w, http.StatusOK, inst)
}

type completePayload struct {
	Items []ItemSubmission `json:"items"`
}

// handleComplete is the operator-facing submission endpoint. It also
// runs the template's validation rules to raise out_of_range alerts in
// the same transaction.
//
// HACCP rule: once status='completed' the items_data is immutable. We
// enforce this by refusing the request when is_locked = TRUE.
func (m *Module) handleComplete(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Bad instance id")
		return
	}
	var body completePayload
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", err.Error())
		return
	}

	// Pull the instance + template in one shot so we can validate against
	// the template's allowed-range items.
	row := m.db.QueryRowContext(r.Context(), `
		SELECT i.is_locked, t.items_jsonb, t.name
		FROM task_instances i
		JOIN task_templates t ON t.id = i.template_id
		WHERE i.id=$1 AND i.tenant_id=$2
	`, id, tenantID)
	var isLocked bool
	var itemsBytes sql.NullString
	var tplName string
	if err := row.Scan(&isLocked, &itemsBytes, &tplName); err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Instance not found")
		return
	} else if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	if isLocked {
		response.Error(w, http.StatusConflict, "LOCKED",
			"Instance already completed; submit a correction instead")
		return
	}

	// Decode template items to enforce required + range validation.
	var items []TemplateItem
	if itemsBytes.Valid {
		_ = json.Unmarshal([]byte(itemsBytes.String), &items)
	}
	submitted := map[string]ItemSubmission{}
	for _, s := range body.Items {
		submitted[s.ItemID] = s
	}
	for _, it := range items {
		if it.Required {
			s, ok := submitted[it.ID]
			if !ok || strings.TrimSpace(s.Value) == "" {
				response.Error(w, http.StatusBadRequest, "VALIDATION",
					fmt.Sprintf("missing required item %s", it.ID))
				return
			}
		}
	}

	// Range checks → alert rows. Computed before opening a tx so we
	// only INSERT alerts when validation succeeded structurally.
	type rangeBreach struct {
		itemID, message string
	}
	var breaches []rangeBreach
	for _, it := range items {
		if it.Validation == nil || (it.Validation.Min == nil && it.Validation.Max == nil) {
			continue
		}
		s, ok := submitted[it.ID]
		if !ok {
			continue
		}
		val, err := strconv.ParseFloat(strings.ReplaceAll(s.Value, ",", "."), 64)
		if err != nil {
			continue
		}
		if it.Validation.Min != nil && val < *it.Validation.Min {
			breaches = append(breaches, rangeBreach{
				itemID:  it.ID,
				message: fmt.Sprintf("%s: %v below allowed minimum %v", tplName, val, *it.Validation.Min),
			})
			continue
		}
		if it.Validation.Max != nil && val > *it.Validation.Max {
			breaches = append(breaches, rangeBreach{
				itemID:  it.ID,
				message: fmt.Sprintf("%s: %v above allowed maximum %v", tplName, val, *it.Validation.Max),
			})
		}
	}

	itemsJSON, err := json.Marshal(body.Items)
	if err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", err.Error())
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	var completedBy sql.NullString
	if u := resolveUser(r); u != "" {
		completedBy = sql.NullString{String: u, Valid: true}
	}
	_, err = tx.ExecContext(r.Context(), `
		UPDATE task_instances SET
		    items_data_jsonb=$1,
		    status='completed',
		    completed_at=NOW(),
		    completed_by_user_id=$2,
		    is_locked=TRUE,
		    updated_at=NOW()
		WHERE id=$3 AND tenant_id=$4 AND is_locked=FALSE
	`, itemsJSON, completedBy, id, tenantID)
	if err != nil {
		_ = tx.Rollback()
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	for _, b := range breaches {
		_, err := tx.ExecContext(r.Context(), `
			INSERT INTO task_alerts (instance_id, tenant_id, item_id, alert_type, message, severity)
			VALUES ($1, $2, $3, 'out_of_range', $4, 'critical')
		`, id, tenantID, b.itemID, b.message)
		if err != nil {
			_ = tx.Rollback()
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
			return
		}
	}
	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}

	row2 := m.db.QueryRowContext(r.Context(),
		`SELECT `+instanceColumns+` FROM task_instances i WHERE i.id=$1`, id)
	inst, _ := scanInstance(row2)
	response.JSON(w, http.StatusOK, map[string]any{
		"instance":    inst,
		"alerts_open": len(breaches),
	})
}

type correctionPayload struct {
	Note string `json:"note"`
}

// handleCorrection appends a correction note to a locked instance —
// the only post-completion mutation HACCP allows.
func (m *Module) handleCorrection(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Bad instance id")
		return
	}
	var body correctionPayload
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", err.Error())
		return
	}
	note := strings.TrimSpace(body.Note)
	if note == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "note is required")
		return
	}
	userID := resolveUser(r)
	entry := CorrectionNote{
		At:     time.Now().UTC(),
		UserID: userID,
		Note:   note,
	}
	entryJSON, _ := json.Marshal(entry)
	// jsonb || jsonb appends to the existing array; the column always
	// contains a JSON array (default '[]').
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE task_instances
		   SET correction_notes = correction_notes || $1::jsonb,
		       updated_at = NOW()
		 WHERE id=$2 AND tenant_id=$3
	`, "["+string(entryJSON)+"]", id, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Instance not found")
		return
	}
	response.NoContent(w)
}

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------

func (m *Module) handleListAlerts(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	onlyOpen := r.URL.Query().Get("status") != "all"
	query := `SELECT id, instance_id, tenant_id, item_id, alert_type, message,
		severity, resolved_at, resolved_by_user_id, resolution_note, created_at
		FROM task_alerts WHERE tenant_id=$1`
	if onlyOpen {
		query += " AND resolved_at IS NULL"
	}
	query += " ORDER BY created_at DESC LIMIT 200"
	rows, err := m.db.QueryContext(r.Context(), query, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	defer rows.Close()
	out := []TaskAlert{}
	for rows.Next() {
		var a TaskAlert
		var itemID, resolvedBy, resolutionNote sql.NullString
		var resolvedAt sql.NullTime
		if err := rows.Scan(&a.ID, &a.InstanceID, &a.TenantID, &itemID,
			&a.AlertType, &a.Message, &a.Severity,
			&resolvedAt, &resolvedBy, &resolutionNote, &a.CreatedAt); err != nil {
			continue
		}
		if itemID.Valid {
			a.ItemID = &itemID.String
		}
		if resolvedAt.Valid {
			t := resolvedAt.Time
			a.ResolvedAt = &t
		}
		if resolvedBy.Valid {
			a.ResolvedByUserID = &resolvedBy.String
		}
		if resolutionNote.Valid {
			a.ResolutionNote = &resolutionNote.String
		}
		out = append(out, a)
	}
	response.Paginated(w, out, "", false)
}

func (m *Module) handleResolveAlert(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	if !uuid.IsValid(id) {
		response.Error(w, http.StatusBadRequest, "INVALID_ID", "Bad alert id")
		return
	}
	var body struct {
		Note string `json:"note"`
	}
	_ = json.NewDecoder(r.Body).Decode(&body)
	var resolvedBy sql.NullString
	if u := resolveUser(r); u != "" {
		resolvedBy = sql.NullString{String: u, Valid: true}
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE task_alerts
		   SET resolved_at=NOW(), resolved_by_user_id=$1, resolution_note=$2
		 WHERE id=$3 AND tenant_id=$4 AND resolved_at IS NULL
	`, resolvedBy, body.Note, id, tenantID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Alert not found or already resolved")
		return
	}
	response.NoContent(w)
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

// handleReportSummary aggregates the last N days into a compact JSON
// blob for the backoffice dashboard card. Default 7 days; ?days=N.
func (m *Module) handleReportSummary(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	days := 7
	if d := r.URL.Query().Get("days"); d != "" {
		if n, err := strconv.Atoi(d); err == nil && n > 0 && n <= 90 {
			days = n
		}
	}
	since := time.Now().AddDate(0, 0, -days)

	// Single query: COUNT() FILTER variants give us per-status totals
	// without 4 round-trips.
	row := m.db.QueryRowContext(r.Context(), `
		SELECT
		  COUNT(*) FILTER (WHERE status='completed')             AS completed,
		  COUNT(*) FILTER (WHERE status='missed')                AS missed,
		  COUNT(*) FILTER (WHERE status IN ('pending','in_progress')) AS open,
		  COUNT(*)                                                AS total
		FROM task_instances
		WHERE tenant_id=$1 AND scheduled_for >= $2
	`, tenantID, since)
	var completed, missed, open, total int
	if err := row.Scan(&completed, &missed, &open, &total); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	rate := 0.0
	if total > 0 {
		rate = float64(completed) / float64(total)
	}

	// Open alerts grouped by type for the warning banner.
	alertRows, err := m.db.QueryContext(r.Context(), `
		SELECT alert_type, COUNT(*) FROM task_alerts
		WHERE tenant_id=$1 AND resolved_at IS NULL AND created_at >= $2
		GROUP BY alert_type
	`, tenantID, since)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", err.Error())
		return
	}
	defer alertRows.Close()
	alertsByType := map[string]int{}
	for alertRows.Next() {
		var k string
		var v int
		if err := alertRows.Scan(&k, &v); err == nil {
			alertsByType[k] = v
		}
	}

	response.JSON(w, http.StatusOK, map[string]any{
		"window_days":      days,
		"total_instances":  total,
		"completed":        completed,
		"missed":           missed,
		"open":             open,
		"completion_rate":  rate,
		"alerts_by_type":   alertsByType,
	})
}

// handleCronTrigger lets ops force a tick from the API (also used by
// tests). Returns counts so the caller can see whether anything fired.
func (m *Module) handleCronTrigger(w http.ResponseWriter, r *http.Request) {
	// Allow either tenant context or the admin shared-secret header
	// some other modules accept; for now require the standard tenant.
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	now := time.Now().UTC()
	if err := m.materialiseDueInstances(r.Context(), now); err != nil {
		response.Error(w, http.StatusInternalServerError, "CRON", err.Error())
		return
	}
	if err := m.markMissedInstances(r.Context(), now); err != nil {
		response.Error(w, http.StatusInternalServerError, "CRON", err.Error())
		return
	}
	response.JSON(w, http.StatusOK, map[string]any{"ok": true, "now": now})
}
