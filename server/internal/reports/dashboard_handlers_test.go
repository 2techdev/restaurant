// Pure-function tests for the dashboard handler helpers — period
// parsing and previous-period math. Doesn't touch the database so it
// runs without testcontainers / fixtures.

package reports

import (
	"net/http/httptest"
	"testing"
	"time"
)

func TestParsePeriod_DefaultsToToday(t *testing.T) {
	r := httptest.NewRequest("GET", "/api/v1/reports/sales-summary", nil)
	from, to, label := parsePeriod(r)
	if label != "today" {
		t.Fatalf("default label = %q, want today", label)
	}
	now := time.Now()
	if from.Year() != now.Year() || from.Month() != now.Month() || from.Day() != now.Day() {
		t.Errorf("from = %v, want today's date", from)
	}
	if to.Year() != now.Year() || to.Month() != now.Month() || to.Day() != now.Day() {
		t.Errorf("to = %v, want today's date", to)
	}
	if to.Hour() != 23 || to.Minute() != 59 {
		t.Errorf("to should be end-of-day, got %v", to)
	}
}

func TestParsePeriod_Yesterday(t *testing.T) {
	r := httptest.NewRequest("GET", "/api/v1/reports/sales-summary?period=yesterday", nil)
	from, to, label := parsePeriod(r)
	if label != "yesterday" {
		t.Fatalf("label = %q", label)
	}
	y := time.Now().AddDate(0, 0, -1)
	if from.Day() != y.Day() {
		t.Errorf("from.Day = %d, want %d", from.Day(), y.Day())
	}
	if !to.Before(time.Now().Add(-12 * time.Hour)) {
		t.Errorf("yesterday `to` should be in the past, got %v", to)
	}
}

func TestParsePeriod_ThisWeek_MondayStart(t *testing.T) {
	r := httptest.NewRequest("GET", "/api/v1/reports/sales-summary?period=this_week", nil)
	from, _, _ := parsePeriod(r)
	// Monday = 1, Sunday = 0; from should be a Monday.
	wd := int(from.Weekday())
	if wd != 1 {
		t.Errorf("this_week.from weekday = %d, want Monday (1)", wd)
	}
}

func TestParsePeriod_LastMonth(t *testing.T) {
	r := httptest.NewRequest("GET", "/api/v1/reports/sales-summary?period=last_month", nil)
	from, to, label := parsePeriod(r)
	if label != "last_month" {
		t.Fatalf("label = %q", label)
	}
	if from.Day() != 1 {
		t.Errorf("from.Day = %d, want 1 (start of month)", from.Day())
	}
	if to.Year() == time.Now().Year() && to.Month() == time.Now().Month() {
		t.Errorf("to should fall in the prior month, got %v", to)
	}
}

func TestParsePeriod_Custom(t *testing.T) {
	r := httptest.NewRequest("GET",
		"/api/v1/reports/sales-summary?period=custom&start=2026-01-05&end=2026-01-12", nil)
	from, to, _ := parsePeriod(r)
	if from.Format("2006-01-02") != "2026-01-05" {
		t.Errorf("from = %s", from.Format("2006-01-02"))
	}
	if to.Format("2006-01-02") != "2026-01-12" {
		t.Errorf("to = %s", to.Format("2006-01-02"))
	}
}

func TestPreviousPeriod_MirrorsWindow(t *testing.T) {
	from := time.Date(2026, 5, 10, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 5, 16, 23, 59, 59, 0, time.UTC)
	prevFrom, prevTo := previousPeriod(from, to)
	// prevTo should be one second before `from`.
	if !prevTo.Equal(from.Add(-time.Second)) {
		t.Errorf("prevTo = %v, want %v", prevTo, from.Add(-time.Second))
	}
	// Window length should match.
	if to.Sub(from) != prevTo.Sub(prevFrom) {
		t.Errorf("window mismatch: curr=%v, prev=%v",
			to.Sub(from), prevTo.Sub(prevFrom))
	}
}

func TestPctDelta(t *testing.T) {
	cases := []struct {
		curr, prev int64
		want       float64
	}{
		{100, 100, 0},
		{200, 100, 100},
		{50, 100, -50},
		{0, 0, 0},
		{100, 0, 100}, // sentinel: prev=0 + curr>0 → 100% (avoids /0)
	}
	for _, c := range cases {
		got := pctDelta(c.curr, c.prev)
		if got != c.want {
			t.Errorf("pctDelta(%d, %d) = %v, want %v", c.curr, c.prev, got, c.want)
		}
	}
}
