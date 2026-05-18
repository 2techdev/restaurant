package crm

import (
	"errors"
	"fmt"
	"strings"
)

// buildSegmentWhere translates a SegmentDefinition into a SQL WHERE-clause
// fragment plus its bound arguments. Returned `where` does NOT include the
// leading `AND` — the caller is expected to compose it onto a base query
// like `SELECT … FROM customers WHERE tenant_id = $1 AND is_deleted = false`.
//
// `startIdx` is the 1-based index of the next free placeholder ($N).
// Returns ("", nil, nil) if the definition has zero filters — caller should
// then skip the additional WHERE conjunction.
func buildSegmentWhere(def SegmentDefinition, startIdx int) (string, []any, error) {
	if len(def.Filters) == 0 {
		return "", nil, nil
	}
	combinator := strings.ToUpper(strings.TrimSpace(def.Combinator))
	if combinator != "OR" {
		combinator = "AND"
	}

	clauses := make([]string, 0, len(def.Filters))
	args := make([]any, 0, len(def.Filters))
	idx := startIdx

	for _, f := range def.Filters {
		clause, fargs, err := filterToSQL(f, &idx)
		if err != nil {
			return "", nil, err
		}
		if clause != "" {
			clauses = append(clauses, clause)
			args = append(args, fargs...)
		}
	}
	if len(clauses) == 0 {
		return "", nil, nil
	}
	return "(" + strings.Join(clauses, " "+combinator+" ") + ")", args, nil
}

// filterToSQL converts one SegmentFilter into a SQL boolean fragment, bumping
// idx for each placeholder it consumes.
func filterToSQL(f SegmentFilter, idx *int) (string, []any, error) {
	switch f.Type {
	case "last_visit_before_days":
		if f.Days == nil {
			return "", nil, errors.New("last_visit_before_days requires days")
		}
		p := next(idx)
		return fmt.Sprintf("(last_visit_at IS NOT NULL AND last_visit_at < now() - (%s::int * interval '1 day'))", p), []any{*f.Days}, nil

	case "last_visit_after_days":
		if f.Days == nil {
			return "", nil, errors.New("last_visit_after_days requires days")
		}
		p := next(idx)
		return fmt.Sprintf("(last_visit_at IS NOT NULL AND last_visit_at >= now() - (%s::int * interval '1 day'))", p), []any{*f.Days}, nil

	case "never_visited":
		return "(last_visit_at IS NULL OR total_visits = 0)", nil, nil

	case "total_visits_min":
		if f.Value == nil {
			return "", nil, errors.New("total_visits_min requires value")
		}
		p := next(idx)
		return fmt.Sprintf("(total_visits >= %s)", p), []any{*f.Value}, nil

	case "total_visits_max":
		if f.Value == nil {
			return "", nil, errors.New("total_visits_max requires value")
		}
		p := next(idx)
		return fmt.Sprintf("(total_visits <= %s)", p), []any{*f.Value}, nil

	case "total_visits_eq":
		if f.Value == nil {
			return "", nil, errors.New("total_visits_eq requires value")
		}
		p := next(idx)
		return fmt.Sprintf("(total_visits = %s)", p), []any{*f.Value}, nil

	case "total_spend_min_cents":
		if f.Value == nil {
			return "", nil, errors.New("total_spend_min_cents requires value")
		}
		p := next(idx)
		return fmt.Sprintf("(total_spent_cents >= %s)", p), []any{*f.Value}, nil

	case "total_spend_max_cents":
		if f.Value == nil {
			return "", nil, errors.New("total_spend_max_cents requires value")
		}
		p := next(idx)
		return fmt.Sprintf("(total_spent_cents <= %s)", p), []any{*f.Value}, nil

	case "has_tag":
		if f.Tag == nil || *f.Tag == "" {
			return "", nil, errors.New("has_tag requires tag")
		}
		p := next(idx)
		return fmt.Sprintf("(tags @> ARRAY[%s]::text[])", p), []any{*f.Tag}, nil

	case "has_allergen":
		if f.Tag == nil || *f.Tag == "" {
			return "", nil, errors.New("has_allergen requires tag")
		}
		p := next(idx)
		return fmt.Sprintf("(allergens @> ARRAY[%s]::text[])", p), []any{*f.Tag}, nil

	case "has_dietary_tag":
		if f.Tag == nil || *f.Tag == "" {
			return "", nil, errors.New("has_dietary_tag requires tag")
		}
		p := next(idx)
		return fmt.Sprintf("(dietary_tags @> ARRAY[%s]::text[])", p), []any{*f.Tag}, nil

	case "birthday_in_days":
		if f.Days == nil {
			return "", nil, errors.New("birthday_in_days requires days")
		}
		// birthday stored as TEXT (YYYY-MM-DD). Compare month/day window.
		p := next(idx)
		return fmt.Sprintf(`(
			birthday IS NOT NULL AND length(birthday) >= 10
			AND (
				to_date(extract(year from now())::text || substr(birthday, 5, 6), 'YYYY-MM-DD')
				BETWEEN current_date AND current_date + (%s::int * interval '1 day')
			OR  to_date((extract(year from now())+1)::text || substr(birthday, 5, 6), 'YYYY-MM-DD')
				BETWEEN current_date AND current_date + (%s::int * interval '1 day')
			)
		)`, p, p), []any{*f.Days}, nil

	case "anniversary_in_days":
		if f.Days == nil {
			return "", nil, errors.New("anniversary_in_days requires days")
		}
		p := next(idx)
		return fmt.Sprintf(`(
			anniversary IS NOT NULL
			AND (
				to_date(extract(year from now())::text || to_char(anniversary, '-MM-DD'), 'YYYY-MM-DD')
				BETWEEN current_date AND current_date + (%s::int * interval '1 day')
			OR  to_date((extract(year from now())+1)::text || to_char(anniversary, '-MM-DD'), 'YYYY-MM-DD')
				BETWEEN current_date AND current_date + (%s::int * interval '1 day')
			)
		)`, p, p), []any{*f.Days}, nil

	case "first_visit_before_days":
		if f.Days == nil {
			return "", nil, errors.New("first_visit_before_days requires days")
		}
		p := next(idx)
		return fmt.Sprintf("(first_visit_at IS NOT NULL AND first_visit_at < now() - (%s::int * interval '1 day'))", p), []any{*f.Days}, nil

	case "preferred_hour_bucket_in":
		if len(f.Hours) == 0 {
			return "", nil, errors.New("preferred_hour_bucket_in requires hours")
		}
		placeholders := make([]string, 0, len(f.Hours))
		args := make([]any, 0, len(f.Hours))
		for _, h := range f.Hours {
			placeholders = append(placeholders, next(idx))
			args = append(args, h)
		}
		return fmt.Sprintf("(preferred_hour_bucket IN (%s))", strings.Join(placeholders, ",")), args, nil

	case "preferred_payment_method":
		if f.Tag == nil || *f.Tag == "" {
			return "", nil, errors.New("preferred_payment_method requires tag")
		}
		p := next(idx)
		return fmt.Sprintf("(preferred_payment_method = %s)", p), []any{*f.Tag}, nil

	default:
		return "", nil, fmt.Errorf("unsupported filter type: %s", f.Type)
	}
}

func next(idx *int) string {
	s := fmt.Sprintf("$%d", *idx)
	*idx++
	return s
}
