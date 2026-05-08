package menu

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"strings"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// importFromTokenRequest is the body for POST /api/v1/menu/import-from-token.
//
// Token format: 7 chars total, "[A-Z2-9]{3}-[A-Z2-9]{3}" (matches Reservation
// generator — Crockford-Base32 minus ambiguous I/O/0/1).
type importFromTokenRequest struct {
	Token   string `json:"token"`
	BaseURL string `json:"baseUrl,omitempty"` // dev/staging override
	Mode    string `json:"mode,omitempty"`    // "merge" (default) | "replace"
	DryRun  bool   `json:"dryRun,omitempty"`
}

// tokenRe enforces the magic-link token shape. Crockford-Base32 alphabet
// without the ambiguous I, L, O, U, 0, 1 — same set Reservation issues.
var tokenRe = regexp.MustCompile(`^[A-HJ-KM-NP-TV-Z2-9]{3}-[A-HJ-KM-NP-TV-Z2-9]{3}$`)

// importFromTokenResponse is the wire format. preview is always populated
// (preview-mode AND apply-mode return the diff). applied=true iff a real
// sync_events row was written.
type importFromTokenResponse struct {
	Success     bool          `json:"success"`
	Applied     bool          `json:"applied"`
	DryRun      bool          `json:"dryRun"`
	Skipped     bool          `json:"skipped,omitempty"`
	TenantID    string        `json:"tenantId"`
	LinkedAt    string        `json:"linkedAt,omitempty"`
	SyncEventID string        `json:"syncEventId,omitempty"`
	Preview     ImportPreview `json:"preview"`
	Warnings    []string      `json:"warnings,omitempty"`
}

// handleImportFromToken pulls a menu snapshot from Reservation by magic-link
// token and applies it to the caller's tenant. Admin-only.
//
// POST /api/v1/menu/import-from-token
func (m *Module) handleImportFromToken(w http.ResponseWriter, r *http.Request) {
	tenantID := middleware.GetTenantID(r.Context())
	if tenantID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Tenant context required")
		return
	}
	role := middleware.GetRole(r.Context())
	if role != "admin" && role != "owner" {
		response.Error(w, http.StatusForbidden, "FORBIDDEN", "Only admin/owner can import a remote menu")
		return
	}

	var req importFromTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}
	req.Token = strings.ToUpper(strings.TrimSpace(req.Token))
	if req.Token == "" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "token is required")
		return
	}
	if !tokenRe.MatchString(req.Token) {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "token must match XXX-XXX (Crockford-Base32)")
		return
	}
	if req.Mode == "" {
		req.Mode = "merge"
	}
	if req.Mode != "merge" {
		response.Error(w, http.StatusBadRequest, "VALIDATION_ERROR", "mode='replace' is not supported in Aşama 1")
		return
	}

	client, err := NewGastroHubClient()
	if err != nil {
		slog.Error("menu: gastrohub client init", "error", err)
		response.Error(w, http.StatusInternalServerError, "CONFIG_ERROR", "Magic-link import is not configured (missing GASTROCORE_SERVICE_SECRET)")
		return
	}
	if req.BaseURL != "" {
		client = client.withBaseURL(req.BaseURL)
	}

	env, err := client.fetchSnapshotByToken(r.Context(), req.Token)
	if err != nil {
		var ce *ClientError
		if errors.As(err, &ce) {
			response.Error(w, ce.Status, ce.Code, ce.Message)
			return
		}
		slog.Error("menu: fetch snapshot", "error", err)
		response.Error(w, http.StatusBadGateway, "UPSTREAM_ERROR", "Failed to fetch snapshot from Reservation")
		return
	}

	if err := validateSnapshot(env); err != nil {
		slog.Warn("menu: snapshot validation failed", "error", err)
		response.Error(w, http.StatusUnprocessableEntity, "INVALID_SNAPSHOT", err.Error())
		return
	}

	fallbackBase := strings.TrimRight(strings.TrimSpace(req.BaseURL), "/")
	if fallbackBase == "" {
		fallbackBase = client.baseURL
	}

	res, err := m.applyImport(r.Context(), tenantID, req.Token, env, req.Mode, req.DryRun, fallbackBase)
	if err != nil {
		slog.Error("menu: apply import", "error", err, "tenant", tenantID, "token", req.Token)
		response.Error(w, http.StatusInternalServerError, "APPLY_FAILED", "Failed to apply menu snapshot")
		return
	}

	out := importFromTokenResponse{
		Success:  true,
		Applied:  !req.DryRun,
		DryRun:   req.DryRun,
		Skipped:  res.Skipped,
		TenantID: tenantID,
		Preview:  res.Preview,
	}
	if !req.DryRun {
		out.SyncEventID = res.SyncEventID
		out.LinkedAt = env.GeneratedAt
	}
	if res.Preview.Summary.ModifiersSkipped > 0 {
		out.Warnings = append(out.Warnings,
			"modifier_crud_skipped: modifier groups/options were read-only (CRUD lands in Aşama 2)")
	}
	if res.Skipped {
		out.Warnings = append(out.Warnings,
			"idempotent_replay: identical payload was previously applied; no DB writes performed")
	}

	response.JSON(w, http.StatusOK, out)
}
