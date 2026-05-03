// Package receipt_templates exposes /api/v1/receipt-templates — Swiss
// MWST-compliant printable receipt layouts. Templates are tenant-scoped, with
// a partial-unique constraint guaranteeing one default per (tenant, language).
//
// The /test-print endpoint renders a server-side preview using the same
// substitution engine the POS replicates locally. Real ESC/POS dispatch happens
// on the POS device — the backoffice path is preview-only.
package receipt_templates

import (
	"database/sql"
	"net/http"
)

type Module struct {
	db *sql.DB
}

func NewModule(db *sql.DB) *Module {
	return &Module{db: db}
}

func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/receipt-templates", m.handleList)
	mux.HandleFunc("POST /api/v1/receipt-templates", m.handleCreate)
	// tenant-info MUST be registered before /{id} so the literal segment matches.
	// http.ServeMux gives priority to literal patterns over wildcards in 1.22+.
	mux.HandleFunc("GET /api/v1/receipt-templates/tenant-info", m.handleTenantInfoGet)
	mux.HandleFunc("PUT /api/v1/receipt-templates/tenant-info", m.handleTenantInfoUpdate)
	mux.HandleFunc("GET /api/v1/receipt-templates/{id}", m.handleGet)
	mux.HandleFunc("PUT /api/v1/receipt-templates/{id}", m.handleUpdate)
	mux.HandleFunc("DELETE /api/v1/receipt-templates/{id}", m.handleDelete)
	mux.HandleFunc("POST /api/v1/receipt-templates/{id}/test-print", m.handleTestPrint)
	// POS-facing sync endpoint — JWT or X-API-Key auth (handler-internal).
	mux.HandleFunc("GET /api/v1/receipt-templates/sync/{tenantId}", m.handleSync)
}
