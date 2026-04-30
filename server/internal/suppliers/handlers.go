package suppliers

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
	"github.com/gastrocore/server/internal/shared/uuid"
)

type Supplier struct {
	ID          string    `json:"id"`
	TenantID    string    `json:"tenant_id"`
	Name        string    `json:"name"`
	ContactName *string   `json:"contact_name,omitempty"`
	Email       *string   `json:"email,omitempty"`
	Phone       *string   `json:"phone,omitempty"`
	Address     *string   `json:"address,omitempty"`
	Notes       *string   `json:"notes,omitempty"`
	IsActive    bool      `json:"is_active"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type upsertReq struct {
	Name        string  `json:"name"`
	ContactName *string `json:"contact_name"`
	Email       *string `json:"email"`
	Phone       *string `json:"phone"`
	Address     *string `json:"address"`
	Notes       *string `json:"notes"`
	IsActive    *bool   `json:"is_active"`
}

func resolveTenant(r *http.Request) string {
	if t := middleware.GetTenantID(r.Context()); t != "" {
		return t
	}
	return r.URL.Query().Get("tenant_id")
}

// GET /api/v1/suppliers
func (m *Module) handleList(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, name, contact_name, email, phone, address, notes,
		       is_active, created_at, updated_at
		FROM suppliers
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY name ASC
	`, tenantID)
	if err != nil {
		slog.Error("suppliers: list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list suppliers")
		return
	}
	defer rows.Close()

	out := make([]Supplier, 0)
	for rows.Next() {
		s, err := scanRow(rows)
		if err != nil {
			continue
		}
		out = append(out, s)
	}
	response.Paginated(w, out, "", false)
}

// GET /api/v1/suppliers/{id}
func (m *Module) handleGet(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	row := m.db.QueryRowContext(r.Context(), `
		SELECT id, tenant_id, name, contact_name, email, phone, address, notes,
		       is_active, created_at, updated_at
		FROM suppliers
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	s, err := scanRow(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Supplier not found")
		return
	}
	if err != nil {
		slog.Error("suppliers: get", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load supplier")
		return
	}
	response.JSON(w, http.StatusOK, s)
}

// POST /api/v1/suppliers
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
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "name required")
		return
	}
	id := uuid.New()
	now := time.Now().UTC()
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}
	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO suppliers (id, tenant_id, name, contact_name, email, phone, address, notes,
		                      is_active, created_at, updated_at, is_deleted)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$10,false)
	`, id, tenantID, req.Name,
		nullableString(req.ContactName), nullableString(req.Email), nullableString(req.Phone),
		nullableString(req.Address), nullableString(req.Notes), isActive, now)
	if err != nil {
		slog.Error("suppliers: create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create supplier")
		return
	}
	response.Created(w, Supplier{
		ID: id, TenantID: tenantID, Name: req.Name,
		ContactName: req.ContactName, Email: req.Email, Phone: req.Phone,
		Address: req.Address, Notes: req.Notes, IsActive: isActive,
		CreatedAt: now, UpdatedAt: now,
	})
}

// PUT /api/v1/suppliers/{id}
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
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE suppliers SET
			name = CASE WHEN $3 = '' THEN name ELSE $3 END,
			contact_name = $4,
			email = $5,
			phone = $6,
			address = $7,
			notes = $8,
			is_active = COALESCE($9, is_active),
			updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID, req.Name,
		nullableString(req.ContactName), nullableString(req.Email), nullableString(req.Phone),
		nullableString(req.Address), nullableString(req.Notes), req.IsActive)
	if err != nil {
		slog.Error("suppliers: update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update supplier")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Supplier not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"id": id, "status": "updated"})
}

// DELETE /api/v1/suppliers/{id} (soft)
func (m *Module) handleDelete(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	id := r.PathValue("id")
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE suppliers SET is_deleted = true, updated_at = NOW()
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	if err != nil {
		slog.Error("suppliers: delete", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete supplier")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Supplier not found")
		return
	}
	response.NoContent(w)
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanRow(s rowScanner) (Supplier, error) {
	var sp Supplier
	var contactName, email, phone, address, notes sql.NullString
	if err := s.Scan(&sp.ID, &sp.TenantID, &sp.Name, &contactName, &email, &phone,
		&address, &notes, &sp.IsActive, &sp.CreatedAt, &sp.UpdatedAt); err != nil {
		return sp, err
	}
	if contactName.Valid {
		v := contactName.String
		sp.ContactName = &v
	}
	if email.Valid {
		v := email.String
		sp.Email = &v
	}
	if phone.Valid {
		v := phone.String
		sp.Phone = &v
	}
	if address.Valid {
		v := address.String
		sp.Address = &v
	}
	if notes.Valid {
		v := notes.String
		sp.Notes = &v
	}
	return sp, nil
}

func nullableString(s *string) any {
	if s == nil || *s == "" {
		return nil
	}
	return *s
}
