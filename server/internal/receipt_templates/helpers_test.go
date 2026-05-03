package receipt_templates

import (
	"strings"
	"testing"
)

func TestRoundToFiveRappen(t *testing.T) {
	cases := []struct {
		in, want float64
	}{
		{14.50, 14.50},
		{14.51, 14.50},
		{14.52, 14.50},
		{14.525, 14.55}, // boundary — math.Round goes to even / nearest
		{14.53, 14.55},
		{14.54, 14.55},
		{14.55, 14.55},
		{14.57, 14.55},
		{14.58, 14.60},
		{0.00, 0.00},
		{-0.02, 0.00},
		{-0.04, -0.05},
	}
	for _, c := range cases {
		got := RoundToFiveRappen(c.in)
		if got != c.want {
			t.Errorf("RoundToFiveRappen(%v) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestComputeVATBreakdown_Mixed(t *testing.T) {
	items := []SampleItem{
		{Qty: 1, Name: "Pizza", UnitPrice: 14.00, VATRate: 8.1},
		{Qty: 2, Name: "Coffee", UnitPrice: 3.50, VATRate: 8.1},
		{Qty: 1, Name: "Mineral", UnitPrice: 4.00, VATRate: 2.6},
	}
	bd := ComputeVATBreakdown(items)
	if got := round2(bd.GrossTotal); got != 25.00 {
		t.Errorf("GrossTotal = %v, want 25.00", got)
	}
	// 21.00 (8.1%) + 4.00 (2.6%) gross
	// VAT 8.1% = 21 - 21/(1.081) ≈ 1.573
	if got := round2(bd.Rate8_1Vat); got < 1.55 || got > 1.60 {
		t.Errorf("Rate8_1Vat = %v, want ~1.57", got)
	}
	// VAT 2.6% = 4 - 4/(1.026) ≈ 0.101
	if got := round2(bd.Rate2_6Vat); got < 0.09 || got > 0.12 {
		t.Errorf("Rate2_6Vat = %v, want ~0.10", got)
	}
}

func TestFormatItemsCH_Width80(t *testing.T) {
	items := []SampleItem{
		{Qty: 1, Name: "Margherita", UnitPrice: 14.50, VATRate: 8.1},
		{Qty: 2, Name: "Espresso", UnitPrice: 3.50, VATRate: 8.1},
	}
	out := FormatItemsCH(items, 80)
	lines := strings.Split(out, "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 lines, got %d: %q", len(lines), out)
	}
	for _, line := range lines {
		if len(line) != 48 {
			t.Errorf("line not 48 cols: %q (len=%d)", line, len(line))
		}
	}
	if !strings.HasSuffix(lines[0], " 14.50") {
		t.Errorf("line[0] should end with right-aligned price: %q", lines[0])
	}
	if !strings.HasSuffix(lines[1], " 7.00") {
		t.Errorf("line[1] should end with 7.00: %q", lines[1])
	}
}

func TestFormatItemsCH_Width58(t *testing.T) {
	items := []SampleItem{{Qty: 1, Name: "Coca-Cola 0.5l", UnitPrice: 4.50, VATRate: 8.1}}
	out := FormatItemsCH(items, 58)
	if len(out) != 32 {
		t.Errorf("expected 32 cols on 58mm, got %d: %q", len(out), out)
	}
}

func TestFormatVATBreakdownLines(t *testing.T) {
	bd := VATBreakdown{Rate8_1Vat: 1.57, Rate2_6Vat: 0.10}
	out := FormatVATBreakdownLines(bd, 80)
	if !strings.Contains(out, "MWST 8.1%") || !strings.Contains(out, "MWST 2.6%") {
		t.Errorf("missing rate labels: %q", out)
	}
	if strings.Contains(out, "MWST 3.8%") {
		t.Errorf("3.8 should be omitted when zero: %q", out)
	}
}

func TestRender_DefaultTemplate(t *testing.T) {
	tpl := Template{
		WidthMM:    80,
		Header:     "{{tenant_name}}\nUID: {{tenant_uid}}",
		BodyFormat: "Beleg {{order_no}} {{date_ch}} {{time_ch}}\n{{items_ch}}\n{{vat_breakdown}}TOTAL: CHF {{total}}",
		Footer:     "{{tenant_iban}}",
	}
	ctx := SampleData("Pizzeria Test", "Bahnhof 1, 8000 Zürich",
		"CHE-111.222.333 MWST", "CH00 0000 0000 0000 0000 0", "test.ch", "+41 44 000 00 00")
	out := Render(tpl, ctx)
	if !strings.Contains(out, "Pizzeria Test") {
		t.Errorf("tenant_name not substituted: %q", out)
	}
	if !strings.Contains(out, "CHE-111.222.333 MWST") {
		t.Errorf("UID not substituted: %q", out)
	}
	if !strings.Contains(out, "MWST 8.1%") {
		t.Errorf("VAT breakdown missing: %q", out)
	}
	if strings.Contains(out, "{{") {
		t.Errorf("unresolved placeholder: %q", out)
	}
}

func round2(f float64) float64 {
	return float64(int(f*100+0.5)) / 100
}
