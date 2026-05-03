package receipt_templates

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

func resolveTenant(r *http.Request) string {
	if t := middleware.GetTenantID(r.Context()); t != "" {
		return t
	}
	return r.URL.Query().Get("tenant_id")
}

// GET /api/v1/receipt-templates  (?type=kitchen_ticket|customer_receipt|z_report)
func (m *Module) handleList(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	typeFilter := strings.TrimSpace(r.URL.Query().Get("type"))
	if typeFilter != "" && !validTemplateType(typeFilter) {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR",
			"type must be one of kitchen_ticket|customer_receipt|z_report")
		return
	}
	args := []any{tenantID}
	q := `
		SELECT id, tenant_id, name, template_type, language, width_mm, is_default,
		       COALESCE(header,''), body_format, COALESCE(footer,''),
		       paper_cut, open_drawer, copies, created_at, updated_at
		FROM receipt_templates
		WHERE tenant_id = $1`
	if typeFilter != "" {
		q += ` AND template_type = $2`
		args = append(args, typeFilter)
	}
	q += ` ORDER BY template_type, is_default DESC, name ASC`
	rows, err := m.db.QueryContext(r.Context(), q, args...)
	if err != nil {
		slog.Error("receipt_templates: list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list templates")
		return
	}
	defer rows.Close()
	out := make([]Template, 0)
	for rows.Next() {
		t, err := scanRow(rows)
		if err != nil {
			continue
		}
		out = append(out, t)
	}
	response.Paginated(w, out, "", false)
}

// GET /api/v1/receipt-templates/{id}
func (m *Module) handleGet(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	row := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, name, template_type, language, width_mm, is_default,
		       COALESCE(header,''), body_format, COALESCE(footer,''),
		       paper_cut, open_drawer, copies, created_at, updated_at
		FROM receipt_templates
		WHERE id = $1 AND tenant_id = $2
	`, id, tenantID)
	t, err := scanRow(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Template not found")
		return
	}
	if err != nil {
		slog.Error("receipt_templates: get", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load template")
		return
	}
	response.JSON(w, http.StatusOK, t)
}

// POST /api/v1/receipt-templates
func (m *Module) handleCreate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	var req upsertReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if err := validateUpsert(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "tx begin failed")
		return
	}
	defer tx.Rollback()

	if req.IsDefault {
		// Clear any existing default for this (tenant, language, template_type) —
		// partial unique index would otherwise reject the insert.
		if _, err := tx.ExecContext(r.Context(), `
			UPDATE receipt_templates SET is_default = false, updated_at = NOW()
			WHERE tenant_id = $1 AND language = $2 AND template_type = $3 AND is_default = true
		`, tenantID, req.Language, req.TemplateType); err != nil {
			slog.Error("receipt_templates: clear default", "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to clear existing default")
			return
		}
	}

	id := uuid.New()
	now := time.Now().UTC()
	paperCut := true
	if req.PaperCut != nil {
		paperCut = *req.PaperCut
	}
	openDrawer := false
	if req.OpenDrawer != nil {
		openDrawer = *req.OpenDrawer
	}
	copies := 1
	if req.Copies != nil && *req.Copies >= 1 && *req.Copies <= 5 {
		copies = *req.Copies
	}

	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO receipt_templates (id, tenant_id, name, template_type, language, width_mm, is_default,
		                               header, body_format, footer, paper_cut, open_drawer, copies,
		                               created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$14)
	`, id, tenantID, req.Name, req.TemplateType, req.Language, req.WidthMM, req.IsDefault,
		req.Header, req.BodyFormat, req.Footer, paperCut, openDrawer, copies, now)
	if err != nil {
		if isUniqueViolation(err) {
			response.Error(w, http.StatusConflict, "CONFLICT", "Template name already in use")
			return
		}
		slog.Error("receipt_templates: create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create template")
		return
	}
	if err := tx.Commit(); err != nil {
		slog.Error("receipt_templates: commit", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}

	response.Created(w, Template{
		ID: id, TenantID: tenantID, Name: req.Name, TemplateType: req.TemplateType,
		Language: req.Language, WidthMM: req.WidthMM, IsDefault: req.IsDefault,
		Header: req.Header, BodyFormat: req.BodyFormat, Footer: req.Footer,
		PaperCut: paperCut, OpenDrawer: openDrawer, Copies: copies,
		CreatedAt: now, UpdatedAt: now,
	})
}

// PUT /api/v1/receipt-templates/{id}
func (m *Module) handleUpdate(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	var req upsertReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	if err := validateUpsert(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "tx begin failed")
		return
	}
	defer tx.Rollback()

	if req.IsDefault {
		if _, err := tx.ExecContext(r.Context(), `
			UPDATE receipt_templates SET is_default = false, updated_at = NOW()
			WHERE tenant_id = $1 AND language = $2 AND template_type = $3
			  AND is_default = true AND id <> $4
		`, tenantID, req.Language, req.TemplateType, id); err != nil {
			slog.Error("receipt_templates: clear default", "error", err)
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to clear existing default")
			return
		}
	}

	paperCut := true
	if req.PaperCut != nil {
		paperCut = *req.PaperCut
	}
	openDrawer := false
	if req.OpenDrawer != nil {
		openDrawer = *req.OpenDrawer
	}
	copies := 1
	if req.Copies != nil && *req.Copies >= 1 && *req.Copies <= 5 {
		copies = *req.Copies
	}

	res, err := tx.ExecContext(r.Context(), `
		UPDATE receipt_templates SET
			name = $3, template_type = $4, language = $5, width_mm = $6, is_default = $7,
			header = $8, body_format = $9, footer = $10,
			paper_cut = $11, open_drawer = $12, copies = $13,
			updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2
	`, id, tenantID, req.Name, req.TemplateType, req.Language, req.WidthMM, req.IsDefault,
		req.Header, req.BodyFormat, req.Footer, paperCut, openDrawer, copies)
	if err != nil {
		if isUniqueViolation(err) {
			response.Error(w, http.StatusConflict, "CONFLICT", "Template name already in use")
			return
		}
		slog.Error("receipt_templates: update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update template")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Template not found")
		return
	}
	if err := tx.Commit(); err != nil {
		slog.Error("receipt_templates: commit", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"id": id, "status": "updated"})
}

// DELETE /api/v1/receipt-templates/{id}
func (m *Module) handleDelete(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	res, err := m.db.ExecContext(r.Context(), `
		DELETE FROM receipt_templates WHERE id = $1 AND tenant_id = $2 AND is_default = false
	`, id, tenantID)
	if err != nil {
		slog.Error("receipt_templates: delete", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete template")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusBadRequest, "DEFAULT_OR_MISSING", "Template not found or is default (cannot delete)")
		return
	}
	response.NoContent(w)
}

// POST /api/v1/receipt-templates/{id}/test-print
// Returns the resolved text (server-side render) for preview.
// Real ESC/POS dispatch happens on the POS device; the backoffice path
// is a sanity-check + variable substitution preview.
func (m *Module) handleTestPrint(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")

	row := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, name, template_type, language, width_mm, is_default,
		       COALESCE(header,''), body_format, COALESCE(footer,''),
		       paper_cut, open_drawer, copies, created_at, updated_at
		FROM receipt_templates
		WHERE id = $1 AND tenant_id = $2
	`, id, tenantID)
	tpl, err := scanRow(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Template not found")
		return
	}
	if err != nil {
		slog.Error("receipt_templates: test-print load", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load template")
		return
	}

	// Pull tenant CH fields for a realistic preview.
	var tName, tAddress, tPhone, tUID, tIBAN, tWebsite sql.NullString
	if err := m.db.QueryRowContext(r.Context(), `
		SELECT name, address, phone, uid_nummer, iban, website
		FROM tenants WHERE id = $1
	`, tenantID).Scan(&tName, &tAddress, &tPhone, &tUID, &tIBAN, &tWebsite); err != nil && err != sql.ErrNoRows {
		slog.Warn("receipt_templates: tenant fetch", "error", err)
	}

	var req TestPrintReq
	_ = json.NewDecoder(r.Body).Decode(&req) // body is optional

	ctx := SampleData(
		nullStr(tName), nullStr(tAddress), nullStr(tUID),
		nullStr(tIBAN), nullStr(tWebsite), nullStr(tPhone),
	)
	if req.Sample != nil {
		// Operator override (e.g. richer item list during editing).
		ctx = *req.Sample
		if len(ctx.Items) == 0 {
			ctx.Items = SampleData("", "", "", "", "", "").Items
		}
	}

	text := Render(tpl, ctx)
	response.JSON(w, http.StatusOK, RenderResp{
		Text:     text,
		WidthMM:  tpl.WidthMM,
		Language: tpl.Language,
	})
}

// ----- helpers ---------------------------------------------------------------

type rowScanner interface {
	Scan(dest ...any) error
}

func scanRow(s rowScanner) (Template, error) {
	var t Template
	if err := s.Scan(
		&t.ID, &t.TenantID, &t.Name, &t.TemplateType, &t.Language, &t.WidthMM, &t.IsDefault,
		&t.Header, &t.BodyFormat, &t.Footer,
		&t.PaperCut, &t.OpenDrawer, &t.Copies,
		&t.CreatedAt, &t.UpdatedAt,
	); err != nil {
		return t, err
	}
	return t, nil
}

func validTemplateType(s string) bool {
	switch s {
	case "kitchen_ticket", "customer_receipt", "z_report":
		return true
	}
	return false
}

func validateUpsert(req *upsertReq) error {
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		return errMsg("name required")
	}
	req.TemplateType = strings.TrimSpace(req.TemplateType)
	if req.TemplateType == "" {
		req.TemplateType = "customer_receipt"
	}
	if !validTemplateType(req.TemplateType) {
		return errMsg("template_type must be one of kitchen_ticket|customer_receipt|z_report")
	}
	if req.Language == "" {
		req.Language = "de"
	}
	switch req.Language {
	case "de", "fr", "it", "en", "tr":
	default:
		return errMsg("language must be one of de|fr|it|en|tr")
	}
	if req.WidthMM != 58 && req.WidthMM != 80 {
		req.WidthMM = 80
	}
	if strings.TrimSpace(req.BodyFormat) == "" {
		return errMsg("body_format required")
	}
	return nil
}

type errMsg string

func (e errMsg) Error() string { return string(e) }

func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "duplicate key") ||
		strings.Contains(msg, "unique constraint") ||
		strings.Contains(msg, "23505")
}

func nullStr(s sql.NullString) string {
	if s.Valid {
		return s.String
	}
	return ""
}
