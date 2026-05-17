package reporting

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Minimal 5-field cron parser: "m h dom mon dow"
//
// Supports:
//   - exact integers       ("0", "15", "23")
//   - lists                ("0,15,30,45")
//   - ranges               ("9-17")
//   - wildcards            ("*")
//   - steps                ("*/5", "0-30/10")
//
// Does NOT support: "@daily" macros, names ("MON","JAN"), L/W/# specifiers.
// That's intentional — the UI emits canonical numeric expressions.

type cronExpr struct {
	minute, hour, dom, month, dow fieldSet
}

type fieldSet struct {
	bits uint64 // up to 60 entries; we use one bit per value
}

func (s fieldSet) match(v int) bool {
	if v < 0 || v > 63 {
		return false
	}
	return s.bits&(1<<v) != 0
}

func parseCron(expr string) (cronExpr, error) {
	parts := strings.Fields(strings.TrimSpace(expr))
	if len(parts) != 5 {
		return cronExpr{}, fmt.Errorf("cron: expected 5 fields, got %d", len(parts))
	}
	mins, err := parseField(parts[0], 0, 59)
	if err != nil {
		return cronExpr{}, fmt.Errorf("cron: minute: %w", err)
	}
	hrs, err := parseField(parts[1], 0, 23)
	if err != nil {
		return cronExpr{}, fmt.Errorf("cron: hour: %w", err)
	}
	dom, err := parseField(parts[2], 1, 31)
	if err != nil {
		return cronExpr{}, fmt.Errorf("cron: dom: %w", err)
	}
	mon, err := parseField(parts[3], 1, 12)
	if err != nil {
		return cronExpr{}, fmt.Errorf("cron: month: %w", err)
	}
	dow, err := parseField(parts[4], 0, 6)
	if err != nil {
		return cronExpr{}, fmt.Errorf("cron: dow: %w", err)
	}
	return cronExpr{minute: mins, hour: hrs, dom: dom, month: mon, dow: dow}, nil
}

func parseField(field string, lo, hi int) (fieldSet, error) {
	var s fieldSet
	for _, part := range strings.Split(field, ",") {
		part = strings.TrimSpace(part)
		step := 1
		if idx := strings.Index(part, "/"); idx >= 0 {
			st, err := strconv.Atoi(part[idx+1:])
			if err != nil || st < 1 {
				return s, fmt.Errorf("bad step %q", part)
			}
			step = st
			part = part[:idx]
		}
		var start, end int
		switch {
		case part == "*":
			start, end = lo, hi
		case strings.Contains(part, "-"):
			pieces := strings.SplitN(part, "-", 2)
			a, err1 := strconv.Atoi(pieces[0])
			b, err2 := strconv.Atoi(pieces[1])
			if err1 != nil || err2 != nil {
				return s, fmt.Errorf("bad range %q", part)
			}
			start, end = a, b
		default:
			n, err := strconv.Atoi(part)
			if err != nil {
				return s, fmt.Errorf("bad value %q", part)
			}
			start, end = n, n
		}
		if start < lo || end > hi || end < start {
			return s, fmt.Errorf("out of range %q (allowed %d-%d)", part, lo, hi)
		}
		for v := start; v <= end; v += step {
			s.bits |= 1 << v
		}
	}
	return s, nil
}

// Next returns the first time strictly after `after` that satisfies the cron.
// Worst-case scan is one year forward (525 600 minutes) which is fine for
// the once-per-tick path.
func (c cronExpr) Next(after time.Time) time.Time {
	t := after.Add(time.Minute).Truncate(time.Minute)
	limit := t.AddDate(1, 0, 0)
	for t.Before(limit) {
		if c.minute.match(t.Minute()) &&
			c.hour.match(t.Hour()) &&
			c.dom.match(t.Day()) &&
			c.month.match(int(t.Month())) &&
			c.dow.match(int(t.Weekday())) {
			return t
		}
		t = t.Add(time.Minute)
	}
	return time.Time{} // unreachable for normal expressions
}
