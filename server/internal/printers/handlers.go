package printers

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"net"
	"net/http"
	"strconv"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// handleListPrinters returns every printer row for the store (primary + backup).
// GET /api/v1/stores/{id}/printers
func (m *Module) handleListPrinters(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	rows, err := m.db.QueryContext(r.Context(), `
		SELECT id, tenant_id, store_id, target, name, type, ip, port,
		       usb_path, paper_width, enabled, is_backup, created_at, updated_at
		FROM printer_configs
		WHERE tenant_id = $1 AND store_id = $2 AND is_deleted = FALSE
		ORDER BY target, is_backup, name
	`, tenantID, storeID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to list printers")
		return
	}
	defer rows.Close()

	out := make([]PrinterConfig, 0)
	for rows.Next() {
		var p PrinterConfig
		if err := rows.Scan(
			&p.ID, &p.TenantID, &p.StoreID, &p.Target, &p.Name, &p.Type,
			&p.IP, &p.Port, &p.USBPath, &p.PaperWidth, &p.Enabled, &p.IsBackup,
			&p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			continue
		}
		out = append(out, p)
	}

	response.JSON(w, http.StatusOK, StorePrintersPayload{StoreID: storeID, Printers: out})
}

// handleReplacePrinters replaces the full printer set for a store in one
// transaction. The client sends the whole list; we soft-delete everything
// currently present for this store and insert the new set. This keeps the
// client-side logic simple (no per-row PATCH/DELETE choreography).
//
// PUT /api/v1/stores/{id}/printers
func (m *Module) handleReplacePrinters(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	storeID := r.PathValue("id")
	if storeID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id is required")
		return
	}

	var body StorePrintersPayload
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	if err := validatePrinters(body.Printers); err != nil {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	tx, err := m.db.BeginTx(r.Context(), nil)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to begin transaction")
		return
	}
	defer tx.Rollback() //nolint:errcheck

	if _, err := tx.ExecContext(r.Context(), `
		UPDATE printer_configs
		SET is_deleted = TRUE, updated_at = NOW()
		WHERE tenant_id = $1 AND store_id = $2 AND is_deleted = FALSE
	`, tenantID, storeID); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to clear existing printers")
		return
	}

	now := time.Now().UTC()
	out := make([]PrinterConfig, 0, len(body.Printers))
	for _, p := range body.Printers {
		if p.ID == "" {
			p.ID = newID()
		}
		if p.Type == "" {
			p.Type = "ethernet"
		}
		if p.Port == 0 {
			p.Port = 9100
		}
		if p.PaperWidth == "" {
			p.PaperWidth = "80mm"
		}

		if _, err := tx.ExecContext(r.Context(), `
			INSERT INTO printer_configs
			    (id, tenant_id, store_id, target, name, type, ip, port,
			     usb_path, paper_width, enabled, is_backup, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
		`, p.ID, tenantID, storeID, p.Target, p.Name, p.Type, p.IP, p.Port,
			p.USBPath, p.PaperWidth, p.Enabled, p.IsBackup, now, now,
		); err != nil {
			response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to insert printer: "+err.Error())
			return
		}

		p.TenantID = tenantID
		p.StoreID = storeID
		p.CreatedAt = now
		p.UpdatedAt = now
		out = append(out, p)
	}

	if err := tx.Commit(); err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to commit")
		return
	}

	response.JSON(w, http.StatusOK, StorePrintersPayload{StoreID: storeID, Printers: out})
}

// handleTestPrint only ACKs — the actual print is fired by the POS client
// that receives the ACK, because the backend can't reach printers on the
// store LAN. Used by the backoffice "Test Print" button, which pushes the
// request through the store's POS app over the sync channel.
//
// Reason: opening a socket from cloud backend → store LAN printer requires
// a VPN / tunnel and is explicitly out of pilot scope.
//
// POST /api/v1/stores/{id}/printers/{pid}/test
func (m *Module) handleTestPrint(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Tenant context required")
		return
	}
	storeID := r.PathValue("id")
	printerID := r.PathValue("pid")
	if storeID == "" || printerID == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "store id and printer id are required")
		return
	}

	var exists bool
	err := m.db.QueryRowContext(r.Context(), `
		SELECT EXISTS(
			SELECT 1 FROM printer_configs
			WHERE id = $1 AND tenant_id = $2 AND store_id = $3 AND is_deleted = FALSE
		)`, printerID, tenantID, storeID).Scan(&exists)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to verify printer")
		return
	}
	if !exists {
		response.Error(w, http.StatusNotFound, "NOT_FOUND", "Printer not found")
		return
	}

	// TODO: push a "test_print" event through the sync hub to the store's POS
	// client, which will call EscPosPrinterService.testPrint() locally and
	// report back. For pilot, we return accepted and rely on the POS client
	// polling pending commands.
	response.JSON(w, http.StatusAccepted, map[string]any{
		"status":     "queued",
		"printer_id": printerID,
	})
}

// ── Helpers ────────────────────────────────────────────────────────────

func newID() string {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 16)
	}
	return "prn_" + hex.EncodeToString(b)
}

func validatePrinters(printers []PrinterConfig) error {
	// Track (target, isBackup) to ensure at most one primary + one backup
	// per target inside the incoming payload (DB enforces it too, but the
	// DB error isn't user-friendly).
	seen := map[string]bool{}
	for i, p := range printers {
		switch p.Target {
		case "kitchen", "bar", "receipt":
		default:
			return &validationError{msg: "printers[" + strconv.Itoa(i) + "]: invalid target"}
		}
		switch p.Type {
		case "", "ethernet", "usb":
		default:
			return &validationError{msg: "printers[" + strconv.Itoa(i) + "]: invalid type"}
		}
		if p.Type != "usb" {
			if p.IP == "" {
				return &validationError{msg: "printers[" + strconv.Itoa(i) + "]: ip is required for ethernet"}
			}
			if net.ParseIP(p.IP) == nil {
				return &validationError{msg: "printers[" + strconv.Itoa(i) + "]: invalid ip"}
			}
			if p.Port < 1 || p.Port > 65535 {
				return &validationError{msg: "printers[" + strconv.Itoa(i) + "]: port out of range"}
			}
		}
		key := p.Target + ":"
		if p.IsBackup {
			key += "backup"
		} else {
			key += "primary"
		}
		if seen[key] {
			return &validationError{msg: "duplicate printer for " + key}
		}
		seen[key] = true
	}
	return nil
}

type validationError struct{ msg string }

func (e *validationError) Error() string { return e.msg }

// Guard against unused-import warnings on slim builds.
var _ = sql.ErrNoRows
