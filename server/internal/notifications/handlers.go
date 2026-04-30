package notifications

import (
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/shared/response"
)

type Prefs struct {
	UserID          string  `json:"user_id"`
	TenantID        string  `json:"tenant_id"`
	EmailEnabled    bool    `json:"email_enabled"`
	PushEnabled     bool    `json:"push_enabled"`
	SmsEnabled      bool    `json:"sms_enabled"`
	NewOrderAlerts  bool    `json:"new_order_alerts"`
	LowStockAlerts  bool    `json:"low_stock_alerts"`
	DailySummary    bool    `json:"daily_summary"`
	WeeklySummary   bool    `json:"weekly_summary"`
	FeedbackAlerts  bool    `json:"feedback_alerts"`
	QuietHoursStart *string `json:"quiet_hours_start,omitempty"`
	QuietHoursEnd   *string `json:"quiet_hours_end,omitempty"`
}

// defaultPrefs is what we return for users with no row yet — matches the
// column DEFAULTs in migration 016.
func defaultPrefs(userID, tenantID string) Prefs {
	return Prefs{
		UserID:         userID,
		TenantID:       tenantID,
		EmailEnabled:   true,
		PushEnabled:    true,
		SmsEnabled:     false,
		NewOrderAlerts: true,
		LowStockAlerts: true,
		DailySummary:   true,
		WeeklySummary:  false,
		FeedbackAlerts: true,
	}
}

// handleGet returns the calling user's notification preferences, falling back
// to system defaults when no row exists yet.
// GET /api/v1/notifications/prefs
func (m *Module) handleGet(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	tenantID := middleware.GetTenantID(r.Context())
	if userID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Not signed in")
		return
	}

	var p Prefs
	var quietStart, quietEnd sql.NullString
	err := m.db.QueryRowContext(r.Context(), `
		SELECT user_id, tenant_id, email_enabled, push_enabled, sms_enabled,
		       new_order_alerts, low_stock_alerts, daily_summary, weekly_summary,
		       feedback_alerts, quiet_hours_start, quiet_hours_end
		FROM notification_preferences WHERE user_id = $1
	`, userID).Scan(&p.UserID, &p.TenantID, &p.EmailEnabled, &p.PushEnabled, &p.SmsEnabled,
		&p.NewOrderAlerts, &p.LowStockAlerts, &p.DailySummary, &p.WeeklySummary,
		&p.FeedbackAlerts, &quietStart, &quietEnd)
	if err == sql.ErrNoRows {
		response.JSON(w, http.StatusOK, defaultPrefs(userID, tenantID))
		return
	}
	if err != nil {
		slog.Error("notifications: get", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to load prefs")
		return
	}
	if quietStart.Valid {
		v := quietStart.String
		p.QuietHoursStart = &v
	}
	if quietEnd.Valid {
		v := quietEnd.String
		p.QuietHoursEnd = &v
	}
	response.JSON(w, http.StatusOK, p)
}

// handlePut upserts the preferences row. Missing booleans default to the
// current row's values via COALESCE on a tri-state pointer.
// PUT /api/v1/notifications/prefs
func (m *Module) handlePut(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	tenantID := middleware.GetTenantID(r.Context())
	if userID == "" {
		response.Error(w, http.StatusUnauthorized, "UNAUTHORIZED", "Not signed in")
		return
	}

	var req struct {
		EmailEnabled    *bool   `json:"email_enabled"`
		PushEnabled     *bool   `json:"push_enabled"`
		SmsEnabled      *bool   `json:"sms_enabled"`
		NewOrderAlerts  *bool   `json:"new_order_alerts"`
		LowStockAlerts  *bool   `json:"low_stock_alerts"`
		DailySummary    *bool   `json:"daily_summary"`
		WeeklySummary   *bool   `json:"weekly_summary"`
		FeedbackAlerts  *bool   `json:"feedback_alerts"`
		QuietHoursStart *string `json:"quiet_hours_start"`
		QuietHoursEnd   *string `json:"quiet_hours_end"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid JSON")
		return
	}

	// Use defaults from current row (or system defaults) for unset fields.
	cur := defaultPrefs(userID, tenantID)
	_ = m.db.QueryRowContext(r.Context(), `
		SELECT email_enabled, push_enabled, sms_enabled, new_order_alerts,
		       low_stock_alerts, daily_summary, weekly_summary, feedback_alerts
		FROM notification_preferences WHERE user_id = $1
	`, userID).Scan(&cur.EmailEnabled, &cur.PushEnabled, &cur.SmsEnabled, &cur.NewOrderAlerts,
		&cur.LowStockAlerts, &cur.DailySummary, &cur.WeeklySummary, &cur.FeedbackAlerts)

	pick := func(p *bool, fallback bool) bool {
		if p != nil {
			return *p
		}
		return fallback
	}

	emailEnabled := pick(req.EmailEnabled, cur.EmailEnabled)
	pushEnabled := pick(req.PushEnabled, cur.PushEnabled)
	smsEnabled := pick(req.SmsEnabled, cur.SmsEnabled)
	newOrder := pick(req.NewOrderAlerts, cur.NewOrderAlerts)
	lowStock := pick(req.LowStockAlerts, cur.LowStockAlerts)
	daily := pick(req.DailySummary, cur.DailySummary)
	weekly := pick(req.WeeklySummary, cur.WeeklySummary)
	feedback := pick(req.FeedbackAlerts, cur.FeedbackAlerts)

	_, err := m.db.ExecContext(r.Context(), `
		INSERT INTO notification_preferences (user_id, tenant_id,
			email_enabled, push_enabled, sms_enabled,
			new_order_alerts, low_stock_alerts, daily_summary, weekly_summary,
			feedback_alerts, quiet_hours_start, quiet_hours_end, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,NOW())
		ON CONFLICT (user_id) DO UPDATE SET
			tenant_id        = EXCLUDED.tenant_id,
			email_enabled    = EXCLUDED.email_enabled,
			push_enabled     = EXCLUDED.push_enabled,
			sms_enabled      = EXCLUDED.sms_enabled,
			new_order_alerts = EXCLUDED.new_order_alerts,
			low_stock_alerts = EXCLUDED.low_stock_alerts,
			daily_summary    = EXCLUDED.daily_summary,
			weekly_summary   = EXCLUDED.weekly_summary,
			feedback_alerts  = EXCLUDED.feedback_alerts,
			quiet_hours_start = EXCLUDED.quiet_hours_start,
			quiet_hours_end   = EXCLUDED.quiet_hours_end,
			updated_at = NOW()
	`, userID, tenantID,
		emailEnabled, pushEnabled, smsEnabled,
		newOrder, lowStock, daily, weekly, feedback,
		nullableString(req.QuietHoursStart), nullableString(req.QuietHoursEnd))
	if err != nil {
		slog.Error("notifications: upsert", "error", err)
		response.Error(w, http.StatusInternalServerError, "DB_ERROR", "Failed to save prefs")
		return
	}

	response.JSON(w, http.StatusOK, Prefs{
		UserID: userID, TenantID: tenantID,
		EmailEnabled: emailEnabled, PushEnabled: pushEnabled, SmsEnabled: smsEnabled,
		NewOrderAlerts: newOrder, LowStockAlerts: lowStock,
		DailySummary: daily, WeeklySummary: weekly, FeedbackAlerts: feedback,
		QuietHoursStart: req.QuietHoursStart, QuietHoursEnd: req.QuietHoursEnd,
	})
}

func nullableString(s *string) any {
	if s == nil || *s == "" {
		return nil
	}
	return *s
}
