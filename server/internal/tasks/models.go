// Package tasks implements the HACCP digital-checklist module:
// templates → scheduled instances → operator submission → alerts.
//
// The schema lives in migration 039_haccp_tasks; this package exposes a
// REST surface under /api/v1/tasks plus a background cron evaluator that
// materialises instances from templates every few minutes.
package tasks

import (
	"encoding/json"
	"time"
)

// TaskTemplate is the operator-authored definition of a recurring
// checklist (e.g. "Sabah Açılış"). The `Items` payload is intentionally
// schemaless on the storage side — see [TemplateItem] for the loose
// shape we accept.
type TaskTemplate struct {
	ID                       string          `json:"id"`
	TenantID                 string          `json:"tenant_id"`
	Name                     string          `json:"name"`
	NameJSONB                json.RawMessage `json:"name_jsonb,omitempty"`
	Description              *string         `json:"description,omitempty"`
	DescriptionJSONB         json.RawMessage `json:"description_jsonb,omitempty"`
	Category                 string          `json:"category"`
	ScheduleCron             string          `json:"schedule_cron"`
	Items                    json.RawMessage `json:"items_jsonb"`
	IsActive                 bool            `json:"is_active"`
	CreatedByUserID          *string         `json:"created_by_user_id,omitempty"`
	CreatedAt                time.Time       `json:"created_at"`
	UpdatedAt                time.Time       `json:"updated_at"`
}

// TemplateItem mirrors the shape we expect inside `items_jsonb`. The
// cron + complete handlers never decode the whole array — they treat it
// as opaque bytes — but this type documents the contract for callers.
type TemplateItem struct {
	ID         string          `json:"id"`
	Type       string          `json:"type"` // checkbox | number | temperature | photo | signature | text
	Label      json.RawMessage `json:"label"`
	Required   bool            `json:"required"`
	Validation *ItemValidation `json:"validation,omitempty"`
}

// ItemValidation expresses an allowed range for numeric / temperature
// items. When `Min` and `Max` are both set, the complete handler raises
// an `out_of_range` alert if the submitted value falls outside.
type ItemValidation struct {
	Min  *float64 `json:"min,omitempty"`
	Max  *float64 `json:"max,omitempty"`
	Unit *string  `json:"unit,omitempty"` // "C", "%", etc — informational
}

// TaskInstance is a single scheduled occurrence of a template. Created
// by [Module.runCronTick]; closed by [Module.handleComplete] which sets
// `Status=completed` and writes the items payload.
type TaskInstance struct {
	ID                  string          `json:"id"`
	TemplateID          string          `json:"template_id"`
	TenantID            string          `json:"tenant_id"`
	ScheduledFor        time.Time       `json:"scheduled_for"`
	Status              string          `json:"status"`
	ItemsData           json.RawMessage `json:"items_data_jsonb"`
	CompletedAt         *time.Time      `json:"completed_at,omitempty"`
	CompletedByUserID   *string         `json:"completed_by_user_id,omitempty"`
	CorrectionNotes     json.RawMessage `json:"correction_notes,omitempty"`
	IsLocked            bool            `json:"is_locked"`
	CreatedAt           time.Time       `json:"created_at"`
	UpdatedAt           time.Time       `json:"updated_at"`

	// Hydrated on the GET /today response so the POS client can render
	// without a second roundtrip. Empty on list-only endpoints.
	Template *TaskTemplate `json:"template,omitempty"`
}

// ItemSubmission is one cell in a complete-instance payload. The handler
// validates type-specific fields after binding.
type ItemSubmission struct {
	ItemID   string  `json:"item_id"`
	Value    string  `json:"value"`              // type-dependent: "true", "5.4", "Ali", …
	Notes    *string `json:"notes,omitempty"`
	PhotoURL *string `json:"photo_url,omitempty"`
}

// TaskAlert is an out-of-band issue surfaced to the operator: a missing
// or late instance, an out-of-range reading, a validation failure.
type TaskAlert struct {
	ID               string     `json:"id"`
	InstanceID       string     `json:"instance_id"`
	TenantID         string     `json:"tenant_id"`
	ItemID           *string    `json:"item_id,omitempty"`
	AlertType        string     `json:"alert_type"`
	Message          string     `json:"message"`
	Severity         string     `json:"severity"`
	ResolvedAt       *time.Time `json:"resolved_at,omitempty"`
	ResolvedByUserID *string    `json:"resolved_by_user_id,omitempty"`
	ResolutionNote   *string    `json:"resolution_note,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
}

// CorrectionNote is appended to TaskInstance.CorrectionNotes after the
// instance is locked. The original items payload stays untouched —
// regulators see the original reading plus the operator's annotation.
type CorrectionNote struct {
	At     time.Time `json:"at"`
	UserID string    `json:"user_id"`
	Note   string    `json:"note"`
}
