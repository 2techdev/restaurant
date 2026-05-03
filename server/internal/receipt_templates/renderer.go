package receipt_templates

import (
	"strings"
)

// Render resolves template variables and returns the final printable text.
// Used both for backoffice preview (/test-print) and as the source of truth
// the POS replicates locally with the same substitution rules.
func Render(tpl Template, ctx SampleContext) string {
	bd := ComputeVATBreakdown(ctx.Items)
	gross := bd.GrossTotal - ctx.DiscountAmount + ctx.TipAmount
	rounded := RoundToFiveRappen(gross)
	roundingDiff := rounded - gross

	itemsBlock := FormatItemsCH(ctx.Items, tpl.WidthMM)
	vatLines := FormatVATBreakdownLines(bd, tpl.WidthMM)
	cols := CharsForWidth(tpl.WidthMM)

	discountLine := ""
	if ctx.DiscountAmount > 0.001 {
		discountLine = padBetween("Rabatt:", "-"+FormatMoney(ctx.DiscountAmount), cols) + "\n"
	}
	roundingLine := ""
	roundedTotalLine := ""
	if ctx.IsCash {
		roundingLine = padBetween("Rundung:", FormatMoney(roundingDiff), cols) + "\n"
		roundedTotalLine = padBetween("Bar:", "CHF "+FormatMoney(rounded), cols) + "\n"
	}

	twintQR := ""
	if ctx.TipAmount > 0.001 {
		twintQR = "[ TWINT QR — Trinkgeld ]"
	}

	subs := map[string]string{
		"{{tenant_name}}":         ctx.TenantName,
		"{{tenant_address}}":      ctx.TenantAddress,
		"{{tenant_phone}}":        ctx.TenantPhone,
		"{{tenant_uid}}":          ctx.TenantUID,
		"{{tenant_iban}}":         ctx.TenantIBAN,
		"{{tenant_website}}":      ctx.TenantWebsite,
		"{{order_no}}":            ctx.OrderNo,
		"{{date}}":                ctx.DateCH, // back-compat alias
		"{{date_ch}}":             ctx.DateCH,
		"{{time_ch}}":             ctx.TimeCH,
		"{{table_or_takeaway}}":   ctx.TableOrTakeaway,
		"{{cashier_name}}":        ctx.CashierName,
		"{{customer_name}}":       ctx.CustomerName,
		"{{items}}":               itemsBlock, // back-compat alias
		"{{items_ch}}":            itemsBlock,
		"{{subtotal}}":            FormatMoney(bd.GrossTotal),
		"{{subtotal_net}}":        FormatMoney(bd.NetTotal),
		"{{discount}}":            FormatMoney(ctx.DiscountAmount),
		"{{tip}}":                 FormatMoney(ctx.TipAmount),
		"{{vat_8_1_amount}}":      FormatMoney(bd.Rate8_1Vat),
		"{{vat_2_6_amount}}":      FormatMoney(bd.Rate2_6Vat),
		"{{vat_3_8_amount}}":      FormatMoney(bd.Rate3_8Vat),
		"{{vat_breakdown}}":       vatLines,
		"{{vat_amount}}":          FormatMoney(bd.VatTotal), // back-compat alias
		"{{vat_rate}}":            "8.1",                    // legacy single-rate alias
		"{{tax}}":                 FormatMoney(bd.VatTotal), // legacy alias
		"{{total}}":               FormatMoney(gross),
		"{{rounded_total}}":       FormatMoney(rounded),
		"{{rounding_diff}}":       FormatMoney(roundingDiff),
		"{{payment_method}}":      ctx.PaymentMethod,
		"{{fiskaly_signature}}":   ctx.FiskalySignature,
		"{{tsr_serial}}":          ctx.TSRSerial,
		"{{discount_line_if_any}}":      discountLine,
		"{{rounding_line_if_cash}}":     roundingLine,
		"{{rounded_total_line_if_cash}}": roundedTotalLine,
		"{{twint_qr_if_tip}}":     twintQR,
	}

	combined := tpl.Header + "\n" + tpl.BodyFormat + "\n" + tpl.Footer
	for k, v := range subs {
		combined = strings.ReplaceAll(combined, k, v)
	}

	// Collapse triple-blank lines that appear when a conditional placeholder
	// renders empty — keeps receipts compact without forcing the operator to
	// micro-manage whitespace in their template.
	for strings.Contains(combined, "\n\n\n") {
		combined = strings.ReplaceAll(combined, "\n\n\n", "\n\n")
	}
	return combined
}
