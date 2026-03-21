// Package qrbill implements Swiss QR-Bill generation endpoints.
//
// Endpoint:
//
//	POST /api/invoices/qrbill  — generate QR-Bill data for a payment slip
//
// Authentication: JWT required (applied via middleware in main.go).
package qrbill

import "net/http"

// Module is the QR-Bill module.
type Module struct{}

// NewModule creates the QR-Bill module.
func NewModule() *Module { return &Module{} }

// RegisterRoutes registers QR-Bill endpoints on the given mux.
// The caller is responsible for wrapping with auth middleware if required.
func (m *Module) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/invoices/qrbill", m.handleGenerateQRBill)
}
