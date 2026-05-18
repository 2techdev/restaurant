package orderprofiles

import (
	"strconv"
	"strings"
	"time"
)

// defaultLocation is the wall-clock timezone schedules are evaluated against
// when the tenant has no per-tenant timezone configured.  Swiss pilot, so
// Europe/Zurich.  When tenants gain a timezone column we'll thread it
// through ProfileMatchesNow's third arg.
var defaultLocation = mustLoadLocation("Europe/Zurich")

func mustLoadLocation(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		return time.UTC
	}
	return loc
}

// parseHM converts "HH:MM" → minutes-since-midnight.  Returns -1 on parse
// failure (caller treats as "slot does not match").
func parseHM(s string) int {
	s = strings.TrimSpace(s)
	if len(s) != 5 || s[2] != ':' {
		return -1
	}
	h, err := strconv.Atoi(s[:2])
	if err != nil || h < 0 || h > 23 {
		return -1
	}
	m, err := strconv.Atoi(s[3:])
	if err != nil || m < 0 || m > 59 {
		return -1
	}
	return h*60 + m
}

// slotMatchesAt reports whether the given slot is active at instant `at`
// (interpreted in defaultLocation).  Crossing-midnight slots
// (endsAt < startsAt) match either the late portion of the start weekday
// or the early portion of the *next* weekday — that's how a 22:00-02:00
// "Late Night" slot stays on through 01:30 even though midnight rolled
// over to the next time.Weekday.
func slotMatchesAt(slot ScheduleSlot, at time.Time) bool {
	local := at.In(defaultLocation)
	weekday := int(local.Weekday())
	nowMin := local.Hour()*60 + local.Minute()

	startMin := parseHM(slot.StartsAt)
	endMin := parseHM(slot.EndsAt)
	if startMin < 0 || endMin < 0 {
		return false
	}

	if endMin > startMin {
		// Same-day window.  Inclusive start, exclusive end (so a 16:00-18:00
		// slot covers 16:00:00 through 17:59:59).
		if !containsWeekday(slot.Weekdays, weekday) {
			return false
		}
		return nowMin >= startMin && nowMin < endMin
	}
	if endMin == startMin {
		// Degenerate slot — treat as 24h on listed weekdays.
		return containsWeekday(slot.Weekdays, weekday)
	}
	// Overnight: covers [startMin, 24:00) on weekday OR [00:00, endMin) on
	// weekday+1.  We accept the slot if EITHER half matches.
	lateHalf := nowMin >= startMin && containsWeekday(slot.Weekdays, weekday)
	prevWeekday := (weekday + 6) % 7
	earlyHalf := nowMin < endMin && containsWeekday(slot.Weekdays, prevWeekday)
	return lateHalf || earlyHalf
}

func containsWeekday(weekdays []int, target int) bool {
	for _, w := range weekdays {
		if w == target {
			return true
		}
	}
	return false
}

// ProfileMatchesNow returns true if any slot in the profile's schedule is
// currently active.  A profile with no schedule slots is "always on"
// (typically the default profile) but only counts as a winner when no
// scheduled profile matches — see chooseWinner.
func ProfileMatchesNow(p *Profile, at time.Time) bool {
	if !p.IsActive {
		return false
	}
	if len(p.Settings.Schedule) == 0 {
		return true
	}
	for _, slot := range p.Settings.Schedule {
		if slotMatchesAt(slot, at) {
			return true
		}
	}
	return false
}

// hasSchedule reports whether the profile has at least one configured slot.
// Used to separate "scheduled candidates" from "the default fallback" when
// choosing a winner.
func hasSchedule(p *Profile) bool {
	return len(p.Settings.Schedule) > 0
}

// chooseWinner picks the single profile that POS should apply when more
// than one is active simultaneously.  Rule: among profiles whose schedule
// matches *right now*, the highest Priority wins.  Ties broken by earliest
// CreatedAt for stability.  If no scheduled profile matches, the row with
// IsDefault=true wins.  Returns nil if there's no default and no scheduled
// match (a misconfigured tenant — the seed migration plants a default so
// this shouldn't happen in practice).
func chooseWinner(active []*Profile, defaultProfile *Profile) *Profile {
	var best *Profile
	for _, p := range active {
		if !hasSchedule(p) {
			continue // schedule-less profiles can only win as the default
		}
		if best == nil {
			best = p
			continue
		}
		if p.Priority > best.Priority {
			best = p
			continue
		}
		if p.Priority == best.Priority && p.CreatedAt.Before(best.CreatedAt) {
			best = p
		}
	}
	if best != nil {
		return best
	}
	return defaultProfile
}
