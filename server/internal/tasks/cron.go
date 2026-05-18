package tasks

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// cronSchedule is a parsed 5-field CRON expression: minute, hour, day-of-
// month, month, day-of-week. We support `*`, fixed integers, `*/N` steps,
// `a-b` ranges and `a,b,c` lists — common enough to cover every default
// template without pulling in a dependency.
type cronSchedule struct {
	minute     []int
	hour       []int
	dayOfMonth []int
	month      []int
	dayOfWeek  []int
}

// parseCron turns "0 6 * * *" into a cronSchedule. Returns an error
// when the expression is malformed; the cron loop logs and skips the
// offending template rather than aborting the whole tick.
func parseCron(expr string) (cronSchedule, error) {
	parts := strings.Fields(strings.TrimSpace(expr))
	if len(parts) != 5 {
		return cronSchedule{}, fmt.Errorf("cron must have 5 fields, got %d", len(parts))
	}
	minute, err := parseField(parts[0], 0, 59)
	if err != nil {
		return cronSchedule{}, fmt.Errorf("minute: %w", err)
	}
	hour, err := parseField(parts[1], 0, 23)
	if err != nil {
		return cronSchedule{}, fmt.Errorf("hour: %w", err)
	}
	dom, err := parseField(parts[2], 1, 31)
	if err != nil {
		return cronSchedule{}, fmt.Errorf("day-of-month: %w", err)
	}
	mon, err := parseField(parts[3], 1, 12)
	if err != nil {
		return cronSchedule{}, fmt.Errorf("month: %w", err)
	}
	// day-of-week: 0 = Sunday, 6 = Saturday. We also accept 7 = Sunday.
	dow, err := parseField(parts[4], 0, 7)
	if err != nil {
		return cronSchedule{}, fmt.Errorf("day-of-week: %w", err)
	}
	// Normalise 7 → 0 so matching against time.Weekday() works directly.
	for i, v := range dow {
		if v == 7 {
			dow[i] = 0
		}
	}
	return cronSchedule{minute, hour, dom, mon, dow}, nil
}

// parseField handles one cron field. Returns nil for `*`, which we
// interpret as "match every value" — callers use [contains] to check.
func parseField(field string, lo, hi int) ([]int, error) {
	if field == "*" {
		return nil, nil
	}
	out := []int{}
	for _, part := range strings.Split(field, ",") {
		step := 1
		if i := strings.Index(part, "/"); i != -1 {
			s, err := strconv.Atoi(part[i+1:])
			if err != nil || s <= 0 {
				return nil, fmt.Errorf("invalid step %q", part)
			}
			step = s
			part = part[:i]
			if part == "*" {
				part = fmt.Sprintf("%d-%d", lo, hi)
			}
		}
		start, end := 0, 0
		if i := strings.Index(part, "-"); i != -1 {
			s, err1 := strconv.Atoi(part[:i])
			e, err2 := strconv.Atoi(part[i+1:])
			if err1 != nil || err2 != nil {
				return nil, fmt.Errorf("invalid range %q", part)
			}
			start, end = s, e
		} else if part == "" {
			return nil, errors.New("empty cron sub-field")
		} else {
			v, err := strconv.Atoi(part)
			if err != nil {
				return nil, fmt.Errorf("invalid value %q", part)
			}
			start, end = v, v
		}
		if start < lo || end > hi || start > end {
			return nil, fmt.Errorf("out of bounds %d-%d (allowed %d-%d)", start, end, lo, hi)
		}
		for v := start; v <= end; v += step {
			out = append(out, v)
		}
	}
	return out, nil
}

// contains reports whether the field allows value v. A nil slice (from
// `*`) matches every value.
func contains(field []int, v int) bool {
	if field == nil {
		return true
	}
	for _, x := range field {
		if x == v {
			return true
		}
	}
	return false
}

// dueWindow returns the set of "fire times" within (start, end] for the
// given schedule. The cron loop calls this with start=lastTick,
// end=now so a template that should have run mid-window still triggers
// even if the tick was delayed.
func (s cronSchedule) dueWindow(start, end time.Time) []time.Time {
	out := []time.Time{}
	// Walk minute by minute. With a 5-min tick window this is at most
	// a few iterations; we cap at 24 hours to stop a long-lagged tick
	// from spinning indefinitely after a deploy or pause.
	const maxWalk = 24 * time.Hour
	if end.Sub(start) > maxWalk {
		start = end.Add(-maxWalk)
	}
	// Truncate start up to the next whole minute and walk forward.
	t := start.Truncate(time.Minute).Add(time.Minute)
	for !t.After(end) {
		if s.matches(t) {
			out = append(out, t)
		}
		t = t.Add(time.Minute)
	}
	return out
}

// matches reports whether the schedule fires at exactly t.
func (s cronSchedule) matches(t time.Time) bool {
	dow := int(t.Weekday()) // already 0=Sunday … 6=Saturday
	return contains(s.minute, t.Minute()) &&
		contains(s.hour, t.Hour()) &&
		contains(s.dayOfMonth, t.Day()) &&
		contains(s.month, int(t.Month())) &&
		contains(s.dayOfWeek, dow)
}

// materialiseDueInstances scans active templates, parses their cron,
// and inserts a `pending` instance for every fire-time in the tick
// window that isn't already in the database. The UNIQUE constraint on
// (template_id, scheduled_for) makes the insert idempotent.
func (m *Module) materialiseDueInstances(ctx context.Context, now time.Time) error {
	// Look back 10 minutes by default so a missed 5-min tick is
	// caught up on the next run.
	since := now.Add(-10 * time.Minute)

	rows, err := m.db.QueryContext(ctx, `
		SELECT id, tenant_id, schedule_cron
		FROM task_templates
		WHERE is_active = TRUE AND is_deleted = FALSE
	`)
	if err != nil {
		return err
	}
	defer rows.Close()

	type tpl struct {
		id, tenant, cron string
	}
	var templates []tpl
	for rows.Next() {
		var t tpl
		if err := rows.Scan(&t.id, &t.tenant, &t.cron); err != nil {
			return err
		}
		templates = append(templates, t)
	}
	if err := rows.Err(); err != nil {
		return err
	}

	for _, t := range templates {
		sched, err := parseCron(t.cron)
		if err != nil {
			// Log but don't fail the whole tick — one broken template
			// shouldn't prevent the others from running.
			continue
		}
		for _, fireAt := range sched.dueWindow(since, now) {
			_, err := m.db.ExecContext(ctx, `
				INSERT INTO task_instances
				    (template_id, tenant_id, scheduled_for, status)
				VALUES ($1, $2, $3, 'pending')
				ON CONFLICT (template_id, scheduled_for) DO NOTHING
			`, t.id, t.tenant, fireAt)
			if err != nil {
				return fmt.Errorf("insert instance: %w", err)
			}
		}
	}
	return nil
}

// markMissedInstances looks for `pending` instances older than the
// configured grace window and flips them to `missed`. Also emits a
// `missing` alert so the dashboard surface lights up.
//
// Grace window: 2 hours by default. Pragmatic — a temperature reading
// every hour can slip 30-60 min during a busy lunch service before
// the operator notices. Tighter than 2h would spam the dashboard.
func (m *Module) markMissedInstances(ctx context.Context, now time.Time) error {
	const grace = 2 * time.Hour
	cutoff := now.Add(-grace)

	rows, err := m.db.QueryContext(ctx, `
		SELECT i.id, i.tenant_id, t.name
		FROM task_instances i
		JOIN task_templates t ON t.id = i.template_id
		WHERE i.status = 'pending' AND i.scheduled_for < $1
	`, cutoff)
	if err != nil {
		return err
	}
	defer rows.Close()

	type missed struct {
		id, tenant, name string
	}
	var list []missed
	for rows.Next() {
		var v missed
		if err := rows.Scan(&v.id, &v.tenant, &v.name); err != nil {
			return err
		}
		list = append(list, v)
	}
	if err := rows.Err(); err != nil {
		return err
	}

	for _, v := range list {
		// Promote status + raise alert in a single transaction so a
		// crash mid-batch never leaves the alert without the status
		// flip (or vice versa).
		tx, err := m.db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx,
			`UPDATE task_instances SET status='missed', updated_at=NOW() WHERE id=$1`,
			v.id,
		); err != nil {
			_ = tx.Rollback()
			return err
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO task_alerts (instance_id, tenant_id, alert_type, message, severity)
			VALUES ($1, $2, 'missing', $3, 'warn')
		`, v.id, v.tenant, fmt.Sprintf("%s: not completed within %s", v.name, grace)); err != nil {
			_ = tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

// scanTemplate is a small helper used by cron + handlers to read a
// template row consistently. Kept private to the package.
func scanTemplate(s interface {
	Scan(dest ...any) error
}) (TaskTemplate, error) {
	var t TaskTemplate
	var nameJSONB, descJSONB, items sql.NullString
	var desc sql.NullString
	var createdBy sql.NullString
	err := s.Scan(
		&t.ID, &t.TenantID, &t.Name, &nameJSONB,
		&desc, &descJSONB,
		&t.Category, &t.ScheduleCron, &items,
		&t.IsActive, &createdBy,
		&t.CreatedAt, &t.UpdatedAt,
	)
	if err != nil {
		return t, err
	}
	if nameJSONB.Valid {
		t.NameJSONB = []byte(nameJSONB.String)
	}
	if desc.Valid {
		t.Description = &desc.String
	}
	if descJSONB.Valid {
		t.DescriptionJSONB = []byte(descJSONB.String)
	}
	if items.Valid {
		t.Items = []byte(items.String)
	} else {
		t.Items = []byte("[]")
	}
	if createdBy.Valid {
		t.CreatedByUserID = &createdBy.String
	}
	return t, nil
}
