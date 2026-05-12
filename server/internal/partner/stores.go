package partner

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// Store is the operator-facing alias for `tenants`.
type storeDTO struct {
	ID               string     `json:"id"`
	Name             string     `json:"name"`
	StoreCode        *string    `json:"store_code,omitempty"`
	BrandID          string     `json:"brand_id"`
	BrandName        string     `json:"brand_name,omitempty"`
	CountryCode      *string    `json:"country_code,omitempty"`
	Address          *string    `json:"address,omitempty"`
	Phone            *string    `json:"phone,omitempty"`
	Email            *string    `json:"email,omitempty"`
	CurrentEditionID *string    `json:"current_edition_id,omitempty"`
	IsOpen           bool       `json:"is_open"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
}

func (m *Module) handleStoreList(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, ""); !ok {
		return
	}
	brand := r.URL.Query().Get("brand_id")
	q := `
		SELECT t.id, t.name, t.store_code, t.organization_id, o.name,
		       t.country_code, t.address, t.phone, t.email,
		       t.current_edition_id::text, COALESCE(t.is_open,false),
		       t.created_at, t.updated_at
		  FROM tenants t
		  JOIN organizations o ON o.id = t.organization_id
		 WHERE COALESCE(t.is_deleted,false)=false`
	args := []any{}
	if brand != "" {
		q += " AND t.organization_id = $1"
		args = append(args, brand)
	}
	q += " ORDER BY t.created_at DESC"
	rows, err := m.db.QueryContext(r.Context(), q, args...)
	if err != nil {
		slog.Error("partner: store list", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list stores")
		return
	}
	defer rows.Close()
	out := []storeDTO{}
	for rows.Next() {
		var s storeDTO
		var code, country, addr, phone, email, edition sql.NullString
		if err := rows.Scan(&s.ID, &s.Name, &code, &s.BrandID, &s.BrandName,
			&country, &addr, &phone, &email, &edition, &s.IsOpen,
			&s.CreatedAt, &s.UpdatedAt); err != nil {
			continue
		}
		s.StoreCode = nullToPtr(code)
		s.CountryCode = nullToPtr(country)
		s.Address = nullToPtr(addr)
		s.Phone = nullToPtr(phone)
		s.Email = nullToPtr(email)
		s.CurrentEditionID = nullToPtr(edition)
		out = append(out, s)
	}
	response.JSON(w, http.StatusOK, map[string]any{"data": out})
}

type storeUpsertRequest struct {
	Name             string  `json:"name"`
	BrandID          string  `json:"brand_id"`
	StoreCode        *string `json:"store_code,omitempty"`
	CountryCode      *string `json:"country_code,omitempty"`
	Address          *string `json:"address,omitempty"`
	Phone            *string `json:"phone,omitempty"`
	Email            *string `json:"email,omitempty"`
	CurrentEditionID *string `json:"current_edition_id,omitempty"`
	IsOpen           *bool   `json:"is_open,omitempty"`
}

func (m *Module) handleStoreCreate(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "MANAGER"); !ok {
		return
	}
	var req storeUpsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" || req.BrandID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION", "Name and brand_id required")
		return
	}
	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "tx begin")
		return
	}
	defer tx.Rollback()

	var id string
	err = tx.QueryRowContext(r.Context(), `
		INSERT INTO tenants (name, organization_id, store_code, country_code,
		                     address, phone, email, current_edition_id,
		                     currency_code, default_tax_rate, is_open)
		VALUES ($1, $2, NULLIF($3,''), COALESCE(NULLIF($4,''), 'CH'),
		        NULLIF($5,''), NULLIF($6,''), NULLIF($7,''),
		        NULLIF($8,'')::uuid,
		        'CHF', 8.1, COALESCE($9, true))
		RETURNING id
	`,
		req.Name, req.BrandID,
		deref(req.StoreCode), deref(req.CountryCode),
		deref(req.Address), deref(req.Phone), deref(req.Email),
		deref(req.CurrentEditionID), req.IsOpen,
	).Scan(&id)
	if err != nil {
		slog.Error("partner: store create", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to create store")
		return
	}
	// Wire the brand→store membership row so HQ-chain queries pick it up.
	_, err = tx.ExecContext(r.Context(), `
		INSERT INTO organization_memberships (organization_id, tenant_id, joined_at, is_master)
		VALUES ($1, $2, NOW(), false)
		ON CONFLICT (organization_id, tenant_id) DO NOTHING
	`, req.BrandID, id)
	if err != nil {
		slog.Error("partner: store membership", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to link store")
		return
	}
	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "tx commit")
		return
	}
	response.JSON(w, http.StatusCreated, map[string]string{"id": id, "name": req.Name})
}

func (m *Module) handleStoreGet(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, ""); !ok {
		return
	}
	id := r.PathValue("id")
	var s storeDTO
	var code, country, addr, phone, email, edition sql.NullString
	err := m.db.QueryRowContext(r.Context(), `
		SELECT t.id, t.name, t.store_code, t.organization_id, o.name,
		       t.country_code, t.address, t.phone, t.email,
		       t.current_edition_id::text, COALESCE(t.is_open,false),
		       t.created_at, t.updated_at
		  FROM tenants t
		  JOIN organizations o ON o.id = t.organization_id
		 WHERE t.id = $1 AND COALESCE(t.is_deleted,false)=false
	`, id).Scan(&s.ID, &s.Name, &code, &s.BrandID, &s.BrandName,
		&country, &addr, &phone, &email, &edition, &s.IsOpen,
		&s.CreatedAt, &s.UpdatedAt)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load")
		return
	}
	s.StoreCode = nullToPtr(code)
	s.CountryCode = nullToPtr(country)
	s.Address = nullToPtr(addr)
	s.Phone = nullToPtr(phone)
	s.Email = nullToPtr(email)
	s.CurrentEditionID = nullToPtr(edition)
	response.JSON(w, http.StatusOK, s)
}

func (m *Module) handleStoreUpdate(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "MANAGER"); !ok {
		return
	}
	id := r.PathValue("id")
	var req storeUpsertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}
	res, err := m.db.ExecContext(r.Context(), `
		UPDATE tenants SET
		  name              = COALESCE(NULLIF($2,''),      name),
		  store_code        = COALESCE(NULLIF($3,''),      store_code),
		  country_code      = COALESCE(NULLIF($4,''),      country_code),
		  address           = COALESCE(NULLIF($5,''),      address),
		  phone             = COALESCE(NULLIF($6,''),      phone),
		  email             = COALESCE(NULLIF($7,''),      email),
		  current_edition_id= COALESCE(NULLIF($8,'')::uuid, current_edition_id),
		  is_open           = COALESCE($9, is_open),
		  updated_at        = NOW()
		WHERE id = $1 AND COALESCE(is_deleted,false)=false
	`, id,
		strings.TrimSpace(req.Name),
		deref(req.StoreCode), deref(req.CountryCode),
		deref(req.Address), deref(req.Phone), deref(req.Email),
		deref(req.CurrentEditionID), req.IsOpen)
	if err != nil {
		slog.Error("partner: store update", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to update")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func (m *Module) handleStoreDelete(w http.ResponseWriter, r *http.Request) {
	if _, ok := m.requirePartner(w, r, "OPERATOR"); !ok {
		return
	}
	id := r.PathValue("id")
	res, err := m.db.ExecContext(r.Context(),
		`UPDATE tenants SET is_deleted=true, updated_at=NOW() WHERE id=$1 AND COALESCE(is_deleted,false)=false`, id)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to delete")
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Store not found")
		return
	}
	response.JSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func nullToPtr(n sql.NullString) *string {
	if !n.Valid {
		return nil
	}
	s := n.String
	return &s
}
