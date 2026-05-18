package crm

import (
	"bytes"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

// ── Marketing campaigns CRUD ─────────────────────────────────────────────────

const campaignColumns = `
	id, tenant_id, segment_id, name, channel, subject, body_html, body_text,
	template_key, scheduled_at, sent_at, status,
	sent_count, opened_count, clicked_count, converted_count,
	created_by, created_at, updated_at, is_deleted
`

// handleListCampaigns returns marketing campaigns for the current tenant.
// GET /api/v1/crm/campaigns
func (m *Module) handleListCampaigns(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT `+campaignColumns+`
		FROM marketing_campaigns
		WHERE tenant_id = $1 AND is_deleted = false
		ORDER BY created_at DESC
		LIMIT 200
	`, tenantID)
	if err != nil {
		slog.Error("crm: list campaigns", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to query campaigns")
		return
	}
	defer rows.Close()

	out := make([]MarketingCampaign, 0)
	for rows.Next() {
		c, err := scanCampaign(rows)
		if err != nil {
			continue
		}
		out = append(out, c)
	}
	response.JSON(w, http.StatusOK, map[string]any{"campaigns": out})
}

// handleGetCampaign returns a single campaign.
// GET /api/v1/crm/campaigns/{id}
func (m *Module) handleGetCampaign(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	row := m.db.QueryRowContext(r.Context(), `
		SELECT `+campaignColumns+`
		FROM marketing_campaigns
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	c, err := scanCampaign(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "not_found", "campaign not found")
		return
	}
	if err != nil {
		slog.Error("crm: get campaign", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to get campaign")
		return
	}
	response.JSON(w, http.StatusOK, c)
}

// handleCreateCampaign creates a campaign in draft status.
// POST /api/v1/crm/campaigns
func (m *Module) handleCreateCampaign(w http.ResponseWriter, r *http.Request) {
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	var req CreateCampaignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}
	if req.ID == "" {
		response.Error(w, http.StatusBadRequest, "validation_error", "id required")
		return
	}
	if req.Name == "" {
		response.Error(w, http.StatusBadRequest, "validation_error", "name required")
		return
	}
	if req.Channel == "" {
		req.Channel = "email"
	}
	if req.Channel != "email" && req.Channel != "sms" && req.Channel != "push" {
		response.Error(w, http.StatusBadRequest, "validation_error", "channel must be email|sms|push")
		return
	}

	createdBy := middleware.GetUserID(r.Context())
	now := time.Now().UTC()
	status := "draft"
	if req.ScheduledAt != nil && req.ScheduledAt.After(now) {
		status = "scheduled"
	}

	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO marketing_campaigns
		    (id, tenant_id, segment_id, name, channel, subject, body_html, body_text,
		     template_key, scheduled_at, status, created_by, created_at, updated_at, is_deleted)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$13,false)
		ON CONFLICT (id) DO NOTHING
	`, req.ID, tenantID, req.SegmentID, req.Name, req.Channel,
		req.Subject, req.BodyHTML, req.BodyText, req.TemplateKey,
		req.ScheduledAt, status, sqlNullStr(createdBy), now,
	)
	if err != nil {
		slog.Error("crm: create campaign", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to create campaign")
		return
	}

	out := MarketingCampaign{
		ID:          req.ID,
		TenantID:    tenantID,
		SegmentID:   req.SegmentID,
		Name:        req.Name,
		Channel:     req.Channel,
		Subject:     req.Subject,
		BodyHTML:    req.BodyHTML,
		BodyText:    req.BodyText,
		TemplateKey: req.TemplateKey,
		ScheduledAt: req.ScheduledAt,
		Status:      status,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if createdBy != "" {
		out.CreatedBy = &createdBy
	}
	response.Created(w, out)
}

// handleUpdateCampaign updates a campaign (only allowed while status='draft' or 'scheduled').
// PUT /api/v1/crm/campaigns/{id}
func (m *Module) handleUpdateCampaign(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	var req UpdateCampaignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "invalid_body", "invalid JSON")
		return
	}

	now := time.Now().UTC()
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE marketing_campaigns
		SET name         = COALESCE($3, name),
		    segment_id   = COALESCE($4, segment_id),
		    channel      = COALESCE($5, channel),
		    subject      = COALESCE($6, subject),
		    body_html    = COALESCE($7, body_html),
		    body_text    = COALESCE($8, body_text),
		    template_key = COALESCE($9, template_key),
		    scheduled_at = COALESCE($10, scheduled_at),
		    status       = COALESCE($11, status),
		    updated_at   = $12
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
		  AND status IN ('draft', 'scheduled')
	`, id, tenantID,
		req.Name, req.SegmentID, req.Channel, req.Subject,
		req.BodyHTML, req.BodyText, req.TemplateKey, req.ScheduledAt, req.Status, now,
	)
	if err != nil {
		slog.Error("crm: update campaign", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to update campaign")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "not_found_or_immutable",
			"campaign not found or already sent")
		return
	}
	response.NoContent(w)
}

// handleDeleteCampaign soft-deletes a campaign.
// DELETE /api/v1/crm/campaigns/{id}
func (m *Module) handleDeleteCampaign(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	now := time.Now().UTC()
	result, err := m.db.ExecContext(r.Context(), `
		UPDATE marketing_campaigns SET is_deleted = true, updated_at = $3
		WHERE id = $1 AND tenant_id = $2
	`, id, tenantID, now)
	if err != nil {
		slog.Error("crm: delete campaign", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to delete campaign")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		response.Error(w, http.StatusNotFound, "not_found", "campaign not found")
		return
	}
	response.NoContent(w)
}

// handleSendCampaign materialises recipients from the linked segment and
// (best-effort) hands each email to SendGrid. When SENDGRID_API_KEY is unset
// the campaign still moves through 'sending' → 'sent', the recipient rows
// land with sent_at = now(), and the body is logged at slog.Info — useful
// for local pilot demos before real keys are wired.
//
// POST /api/v1/crm/campaigns/{id}/send
func (m *Module) handleSendCampaign(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}

	// Load campaign + segment definition.
	row := m.db.QueryRowContext(r.Context(), `
		SELECT `+campaignColumns+`
		FROM marketing_campaigns
		WHERE id = $1 AND tenant_id = $2 AND is_deleted = false
	`, id, tenantID)
	camp, err := scanCampaign(row)
	if err == sql.ErrNoRows {
		response.Error(w, http.StatusNotFound, "not_found", "campaign not found")
		return
	}
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to load campaign")
		return
	}
	if camp.Status == "sent" || camp.Status == "sending" {
		response.Error(w, http.StatusConflict, "already_sent", "campaign already in flight")
		return
	}

	// Resolve target audience.
	var targets []Customer
	if camp.SegmentID != nil && *camp.SegmentID != "" {
		var defJSON []byte
		if err := m.db.QueryRowContext(r.Context(),
			`SELECT definition FROM customer_segments WHERE id = $1 AND tenant_id = $2 AND is_deleted = false`,
			*camp.SegmentID, tenantID,
		).Scan(&defJSON); err != nil {
			response.Error(w, http.StatusBadRequest, "segment_not_found", "segment unavailable")
			return
		}
		var def SegmentDefinition
		if err := json.Unmarshal(defJSON, &def); err != nil {
			response.Error(w, http.StatusInternalServerError, "invalid_definition", err.Error())
			return
		}
		targets, err = m.listSegmentMembers(r.Context(), tenantID, def, 5000)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "db_error", err.Error())
			return
		}
	} else {
		// No segment — broadcast to every customer with the required contact field.
		targets, err = m.listSegmentMembers(r.Context(), tenantID, SegmentDefinition{}, 5000)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "db_error", err.Error())
			return
		}
	}

	// Move to 'sending'.
	_, _ = m.db.ExecContext(r.Context(),
		`UPDATE marketing_campaigns SET status = 'sending', updated_at = now() WHERE id = $1`, id)

	sendOK := 0
	sendFail := 0
	now := time.Now().UTC()
	for _, cust := range targets {
		// Channel-aware contact check.
		var contact string
		switch camp.Channel {
		case "email":
			if cust.Email != nil && strings.Contains(*cust.Email, "@") {
				contact = *cust.Email
			}
		case "sms":
			if cust.Phone != nil && *cust.Phone != "" {
				contact = *cust.Phone
			}
		case "push":
			// push tokens not yet stored; treat every customer as a no-op success.
			contact = cust.ID
		}
		if contact == "" {
			_ = m.insertRecipient(r.Context(), randHex(8), camp, cust, now, "no_contact")
			sendFail++
			continue
		}

		var sendErr string
		if camp.Channel == "email" {
			if err := sendEmail(r.Context(), camp, cust, contact); err != nil {
				sendErr = err.Error()
			}
		}

		if sendErr != "" {
			_ = m.insertRecipient(r.Context(), randHex(8), camp, cust, now, sendErr)
			sendFail++
			continue
		}
		_ = m.insertRecipient(r.Context(), randHex(8), camp, cust, now, "")
		sendOK++
	}

	finalStatus := "sent"
	if sendOK == 0 && sendFail > 0 {
		finalStatus = "failed"
	}
	_, _ = m.db.ExecContext(r.Context(), `
		UPDATE marketing_campaigns
		SET status = $2, sent_count = $3, sent_at = $4, updated_at = $4
		WHERE id = $1
	`, id, finalStatus, sendOK, now)

	response.JSON(w, http.StatusOK, map[string]any{
		"campaign_id": id,
		"status":      finalStatus,
		"recipients":  len(targets),
		"sent":        sendOK,
		"failed":      sendFail,
	})
}

// handleCampaignStats returns derived stats for a campaign.
// GET /api/v1/crm/campaigns/{id}/stats
func (m *Module) handleCampaignStats(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	var stats CampaignStats
	stats.CampaignID = id

	row := m.db.QueryRowContext(r.Context(), `
		SELECT status,
		       COUNT(*) AS total,
		       COUNT(*) FILTER (WHERE sent_at IS NOT NULL) AS sent,
		       COUNT(*) FILTER (WHERE opened_at IS NOT NULL) AS opened,
		       COUNT(*) FILTER (WHERE clicked_at IS NOT NULL) AS clicked,
		       COUNT(*) FILTER (WHERE converted_order_id IS NOT NULL) AS converted
		FROM marketing_campaigns c
		LEFT JOIN marketing_campaign_recipients r ON r.campaign_id = c.id
		WHERE c.id = $1 AND c.tenant_id = $2 AND c.is_deleted = false
		GROUP BY c.status
	`, id, tenantID)
	if err := row.Scan(&stats.Status, &stats.Recipients, &stats.SentCount,
		&stats.OpenedCount, &stats.ClickedCount, &stats.ConvertedCount); err != nil {
		if err == sql.ErrNoRows {
			response.Error(w, http.StatusNotFound, "not_found", "campaign not found")
			return
		}
		slog.Error("crm: campaign stats", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to load stats")
		return
	}
	if stats.SentCount > 0 {
		stats.OpenRate = float64(stats.OpenedCount) / float64(stats.SentCount)
		stats.ClickRate = float64(stats.ClickedCount) / float64(stats.SentCount)
		stats.ConversionRate = float64(stats.ConvertedCount) / float64(stats.SentCount)
	}
	response.JSON(w, http.StatusOK, stats)
}

// handleCampaignRecipients returns the recipient log for a campaign.
// GET /api/v1/crm/campaigns/{id}/recipients?limit=
func (m *Module) handleCampaignRecipients(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	tenantID := resolveTenant(r)
	if tenantID == "" {
		response.Error(w, http.StatusBadRequest, "missing_tenant", "tenant_id required")
		return
	}
	limit := 200
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 && n <= 2000 {
			limit = n
		}
	}
	rows, err := m.db.QueryContext(r.Context(), `
		SELECT r.id, r.campaign_id, r.customer_id, r.tenant_id,
		       r.sent_at, r.opened_at, r.clicked_at, r.converted_order_id, r.error, r.created_at,
		       c.name, c.email
		FROM marketing_campaign_recipients r
		JOIN customers c ON c.id = r.customer_id
		WHERE r.campaign_id = $1 AND r.tenant_id = $2
		ORDER BY r.created_at DESC
		LIMIT $3
	`, id, tenantID, limit)
	if err != nil {
		slog.Error("crm: list recipients", "error", err)
		response.Error(w, http.StatusInternalServerError, "db_error", "failed to query recipients")
		return
	}
	defer rows.Close()

	out := make([]CampaignRecipient, 0)
	for rows.Next() {
		var rec CampaignRecipient
		var sentAt, openedAt, clickedAt sql.NullTime
		var convOrderID, errStr, custName, custEmail sql.NullString
		if err := rows.Scan(
			&rec.ID, &rec.CampaignID, &rec.CustomerID, &rec.TenantID,
			&sentAt, &openedAt, &clickedAt, &convOrderID, &errStr, &rec.CreatedAt,
			&custName, &custEmail,
		); err != nil {
			continue
		}
		if sentAt.Valid {
			rec.SentAt = &sentAt.Time
		}
		if openedAt.Valid {
			rec.OpenedAt = &openedAt.Time
		}
		if clickedAt.Valid {
			rec.ClickedAt = &clickedAt.Time
		}
		if convOrderID.Valid {
			rec.ConvertedOrderID = &convOrderID.String
		}
		if errStr.Valid {
			rec.Error = &errStr.String
		}
		if custName.Valid {
			rec.CustomerName = &custName.String
		}
		if custEmail.Valid {
			rec.CustomerEmail = &custEmail.String
		}
		out = append(out, rec)
	}
	response.JSON(w, http.StatusOK, map[string]any{
		"campaign_id": id,
		"count":       len(out),
		"recipients":  out,
	})
}

// ── helpers ─────────────────────────────────────────────────────────────────

func scanCampaign(s rowScanner) (MarketingCampaign, error) {
	var c MarketingCampaign
	var segmentID, subject, bodyHTML, bodyText, templateKey, createdBy sql.NullString
	var scheduledAt, sentAt sql.NullTime
	if err := s.Scan(
		&c.ID, &c.TenantID, &segmentID, &c.Name, &c.Channel,
		&subject, &bodyHTML, &bodyText, &templateKey,
		&scheduledAt, &sentAt, &c.Status,
		&c.SentCount, &c.OpenedCount, &c.ClickedCount, &c.ConvertedCount,
		&createdBy, &c.CreatedAt, &c.UpdatedAt, &c.IsDeleted,
	); err != nil {
		return c, err
	}
	if segmentID.Valid {
		c.SegmentID = &segmentID.String
	}
	if subject.Valid {
		c.Subject = &subject.String
	}
	if bodyHTML.Valid {
		c.BodyHTML = &bodyHTML.String
	}
	if bodyText.Valid {
		c.BodyText = &bodyText.String
	}
	if templateKey.Valid {
		c.TemplateKey = &templateKey.String
	}
	if scheduledAt.Valid {
		c.ScheduledAt = &scheduledAt.Time
	}
	if sentAt.Valid {
		c.SentAt = &sentAt.Time
	}
	if createdBy.Valid {
		c.CreatedBy = &createdBy.String
	}
	return c, nil
}

func (m *Module) insertRecipient(ctx context.Context, id string, camp MarketingCampaign, cust Customer, sentAt time.Time, errStr string) error {
	if errStr == "" {
		_, err := m.db.ExecContext(ctx, `
			INSERT INTO marketing_campaign_recipients
			    (id, campaign_id, customer_id, tenant_id, sent_at, created_at)
			VALUES ($1,$2,$3,$4,$5,$5)
			ON CONFLICT (campaign_id, customer_id) DO NOTHING
		`, id, camp.ID, cust.ID, camp.TenantID, sentAt)
		return err
	}
	_, err := m.db.ExecContext(ctx, `
		INSERT INTO marketing_campaign_recipients
		    (id, campaign_id, customer_id, tenant_id, error, created_at)
		VALUES ($1,$2,$3,$4,$5,$6)
		ON CONFLICT (campaign_id, customer_id) DO NOTHING
	`, id, camp.ID, cust.ID, camp.TenantID, errStr, sentAt)
	return err
}

// sendEmail dispatches via SendGrid Web API v3 when SENDGRID_API_KEY + FROM
// are configured; otherwise logs the would-be send and returns nil so the
// pilot UI flows end-to-end without provider keys.
func sendEmail(ctx context.Context, camp MarketingCampaign, cust Customer, to string) error {
	apiKey := strings.TrimSpace(os.Getenv("SENDGRID_API_KEY"))
	from := strings.TrimSpace(os.Getenv("SENDGRID_FROM_EMAIL"))
	subject := ""
	if camp.Subject != nil {
		subject = *camp.Subject
	}
	bodyHTML := ""
	if camp.BodyHTML != nil {
		bodyHTML = *camp.BodyHTML
	}
	bodyText := ""
	if camp.BodyText != nil {
		bodyText = *camp.BodyText
	}

	if apiKey == "" || from == "" {
		slog.Info("crm: email stub (SENDGRID_API_KEY not set)",
			"campaign", camp.ID, "to", to, "subject", subject)
		return nil
	}

	payload := map[string]any{
		"personalizations": []map[string]any{{
			"to":      []map[string]string{{"email": to}},
			"subject": subject,
		}},
		"from":    map[string]string{"email": from},
		"content": []map[string]string{},
	}
	if bodyText != "" {
		payload["content"] = append(payload["content"].([]map[string]string),
			map[string]string{"type": "text/plain", "value": bodyText})
	}
	if bodyHTML != "" {
		payload["content"] = append(payload["content"].([]map[string]string),
			map[string]string{"type": "text/html", "value": bodyHTML})
	}
	if len(payload["content"].([]map[string]string)) == 0 {
		payload["content"] = []map[string]string{{"type": "text/plain", "value": "(empty)"}}
	}

	b, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.sendgrid.com/v3/mail/send", bytes.NewReader(b))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 15 * time.Second}
	res, err := client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode >= 300 {
		return fmt.Errorf("sendgrid http %d", res.StatusCode)
	}
	_ = cust // reserved for future per-customer template substitution
	return nil
}

func randHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
