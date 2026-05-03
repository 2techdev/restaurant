package receipt_templates

import (
	"fmt"
	"math"
	"strings"
	"time"
)

// CharsForWidth returns the printable column count for a given thermal-printer width.
// 58mm prints 32 chars/line, 80mm prints 48 chars/line on common Epson/Bixolon profiles.
func CharsForWidth(widthMM int) int {
	if widthMM == 58 {
		return 32
	}
	return 48
}

// RoundToFiveRappen rounds a CHF amount to the nearest 0.05.
// Banker's rounding is irrelevant here — Swiss cash law uses
// arithmetic rounding to the nearest 5 Rappen.
//
//	14.51 → 14.50
//	14.53 → 14.55
//	14.54 → 14.55
//	14.55 → 14.55
//	14.57 → 14.55
//	14.58 → 14.60
func RoundToFiveRappen(amount float64) float64 {
	return math.Round(amount*20) / 20
}

// FormatDateCH renders DD.MM.YYYY (Swiss locale convention).
func FormatDateCH(t time.Time) string {
	return t.Format("02.01.2006")
}

// FormatTimeCH renders HH:mm 24h.
func FormatTimeCH(t time.Time) string {
	return t.Format("15:04")
}

// FormatMoney renders CHF with two decimals and a fixed-width column.
//
//	14    → "14.00"
//	14.5  → "14.50"
//	0     → "0.00"
func FormatMoney(amount float64) string {
	return fmt.Sprintf("%.2f", amount)
}

// FormatItemsCH renders the items section with dot-leader fill so prices align right:
//
//	1x Margherita ............ 14.50
//	2x Espresso ............... 7.00
//
// Width-aware: pads to (widthChars - 1) to avoid wrap on tight thermal printers.
func FormatItemsCH(items []SampleItem, widthMM int) string {
	cols := CharsForWidth(widthMM)
	var b strings.Builder
	for i, it := range items {
		lineTotal := float64(it.Qty) * it.UnitPrice
		left := fmt.Sprintf("%dx %s", it.Qty, it.Name)
		right := FormatMoney(lineTotal)
		// Layout: <left><space><dots><space><right> — two separator spaces.
		fill := cols - len(left) - len(right) - 2
		if fill < 1 {
			// long product name → truncate gracefully
			maxLeft := cols - len(right) - 3
			if maxLeft < 1 {
				maxLeft = 1
			}
			if len(left) > maxLeft {
				left = left[:maxLeft]
			}
			fill = cols - len(left) - len(right) - 2
			if fill < 1 {
				fill = 1
			}
		}
		b.WriteString(left)
		b.WriteString(" ")
		b.WriteString(strings.Repeat(".", fill))
		b.WriteString(" ")
		b.WriteString(right)
		if i < len(items)-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}

// VATBreakdown holds per-rate base + VAT amount.
// Computation assumes line totals are gross (VAT-inclusive) — the standard
// Swiss POS convention. Net is derived as gross / (1 + rate/100).
type VATBreakdown struct {
	Rate8_1Net float64
	Rate8_1Vat float64
	Rate2_6Net float64
	Rate2_6Vat float64
	Rate3_8Net float64
	Rate3_8Vat float64
	NetTotal   float64
	VatTotal   float64
	GrossTotal float64
}

// ComputeVATBreakdown sums per-rate VAT from a list of items.
// Items carry a VATRate (8.1, 2.6, 3.8, 0); other rates are bucketed into
// the closest standard rate or ignored if rate is 0.
func ComputeVATBreakdown(items []SampleItem) VATBreakdown {
	var bd VATBreakdown
	for _, it := range items {
		gross := float64(it.Qty) * it.UnitPrice
		bd.GrossTotal += gross
		if it.VATRate <= 0 {
			bd.NetTotal += gross
			continue
		}
		net := gross / (1 + it.VATRate/100)
		vat := gross - net
		bd.NetTotal += net
		bd.VatTotal += vat
		switch {
		case nearly(it.VATRate, 8.1):
			bd.Rate8_1Net += net
			bd.Rate8_1Vat += vat
		case nearly(it.VATRate, 2.6):
			bd.Rate2_6Net += net
			bd.Rate2_6Vat += vat
		case nearly(it.VATRate, 3.8):
			bd.Rate3_8Net += net
			bd.Rate3_8Vat += vat
		}
	}
	return bd
}

func nearly(a, b float64) bool {
	return math.Abs(a-b) < 0.001
}

// FormatVATBreakdownLines renders one line per non-zero VAT rate, padded to width.
//
// Output (80mm / 48 chars):
//
//	MWST 8.1%:        1.05
//	MWST 2.6%:        0.36
//
// Empty rates are omitted. Always ends with a newline.
func FormatVATBreakdownLines(bd VATBreakdown, widthMM int) string {
	cols := CharsForWidth(widthMM)
	var b strings.Builder
	if bd.Rate8_1Vat > 0.001 {
		b.WriteString(padBetween("MWST 8.1%:", FormatMoney(bd.Rate8_1Vat), cols))
		b.WriteString("\n")
	}
	if bd.Rate2_6Vat > 0.001 {
		b.WriteString(padBetween("MWST 2.6%:", FormatMoney(bd.Rate2_6Vat), cols))
		b.WriteString("\n")
	}
	if bd.Rate3_8Vat > 0.001 {
		b.WriteString(padBetween("MWST 3.8%:", FormatMoney(bd.Rate3_8Vat), cols))
		b.WriteString("\n")
	}
	return b.String()
}

// padBetween returns "left" + spaces + "right" totaling exactly width chars.
// If left+right exceed width, the result is left + " " + right (overflow safe).
func padBetween(left, right string, width int) string {
	gap := width - len(left) - len(right)
	if gap < 1 {
		return left + " " + right
	}
	return left + strings.Repeat(" ", gap) + right
}

// SampleData returns a representative CH sample for preview rendering.
// Used by /test-print when no override is provided.
func SampleData(tenantName, tenantAddress, tenantUID, tenantIBAN, tenantWebsite, tenantPhone string) SampleContext {
	now := time.Now()
	return SampleContext{
		TenantName:    fallback(tenantName, "Pizzeria Da Mario"),
		TenantAddress: fallback(tenantAddress, "Bahnhofstrasse 12, 8001 Zürich"),
		TenantPhone:   fallback(tenantPhone, "+41 44 123 45 67"),
		TenantUID:     fallback(tenantUID, "CHE-123.456.789 MWST"),
		TenantIBAN:    fallback(tenantIBAN, "CH93 0076 2011 6238 5295 7"),
		TenantWebsite: fallback(tenantWebsite, "www.damario.ch"),

		OrderNo:         "4729",
		DateCH:          FormatDateCH(now),
		TimeCH:          FormatTimeCH(now),
		TableOrTakeaway: "Tisch 7",
		CashierName:     "Anna",
		CustomerName:    "",

		Items: []SampleItem{
			{Qty: 1, Name: "Margherita", UnitPrice: 14.50, VATRate: 8.1},
			{Qty: 2, Name: "Espresso", UnitPrice: 3.50, VATRate: 8.1},
			{Qty: 1, Name: "Mineral 50cl", UnitPrice: 4.00, VATRate: 2.6},
		},

		DiscountAmount: 0,
		TipAmount:      0,
		PaymentMethod:  "Bargeld",
		IsCash:         true,
	}
}

func fallback(v, def string) string {
	if strings.TrimSpace(v) == "" {
		return def
	}
	return v
}
