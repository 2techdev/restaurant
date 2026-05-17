package reporting

import (
	"bytes"
	"fmt"
	"html/template"
	"strings"
	"time"
)

// L10n contains every translated string used by the email templates. One
// instance per locale; lookup via strings(locale).
type L10n struct {
	DigestSubject       string // "Daily Sales Report — {{date}}"
	Date                string
	Greeting            string
	Hello               string // "Hi {{name}},"
	Summary             string
	Revenue             string
	NetRevenue          string
	OrderCount          string
	AverageOrder        string
	PaymentBreakdown    string
	OrderTypeBreakdown  string
	TopProducts         string
	StaffPerformance    string
	Cancellations       string
	Voided              string
	Refunded            string
	Discounts           string
	OnlineOrders        string
	Stockouts           string
	OpenInBackoffice    string
	NoActivity          string
	OrderTypeDineIn     string
	OrderTypeTakeaway   string
	OrderTypeDelivery   string
	OrderTypeOnline     string
	Footer              string
	ColMethod           string
	ColTotal            string
	ColType             string
	ColCount            string
	ColProduct          string
	ColQty              string
	ColStaff            string
	ColOrders           string
}

var locales = map[string]L10n{
	"tr": {
		DigestSubject:      "Günlük Satış Raporu — %s",
		Date:               "Tarih",
		Greeting:           "Merhaba,",
		Summary:            "Özet",
		Revenue:            "Toplam Ciro",
		NetRevenue:         "Net (KDV hariç)",
		OrderCount:         "Sipariş Sayısı",
		AverageOrder:       "Ortalama Sepet",
		PaymentBreakdown:   "Ödeme Yöntemine Göre",
		OrderTypeBreakdown: "Sipariş Tipine Göre",
		TopProducts:        "En Çok Satan 5 Ürün",
		StaffPerformance:   "Personel Performansı",
		Cancellations:      "İptal / İade / İndirim",
		Voided:             "İptal",
		Refunded:           "İade",
		Discounts:          "İndirim Toplamı",
		OnlineOrders:       "Online Sipariş",
		Stockouts:          "Stokta Olmayan Ürün",
		OpenInBackoffice:   "Detaylı raporu Backoffice'te aç →",
		NoActivity:         "Bu gün için kayıtlı satış yok.",
		OrderTypeDineIn:    "Im Haus",
		OrderTypeTakeaway:  "Mitnahme",
		OrderTypeDelivery:  "Lieferung",
		OrderTypeOnline:    "Online",
		Footer:             "GastroCore tarafından gönderildi. Bu raporu istemiyorsanız Backoffice → Otomatik Raporlar üzerinden devre dışı bırakabilirsiniz.",
		ColMethod:          "Yöntem",
		ColTotal:           "Tutar",
		ColType:            "Tip",
		ColCount:           "Adet",
		ColProduct:         "Ürün",
		ColQty:             "Miktar",
		ColStaff:           "Personel",
		ColOrders:          "Sipariş",
	},
	"de": {
		DigestSubject:      "Tagesumsatzbericht — %s",
		Date:               "Datum",
		Greeting:           "Guten Tag,",
		Summary:            "Zusammenfassung",
		Revenue:            "Gesamtumsatz",
		NetRevenue:         "Netto (ohne MWST)",
		OrderCount:         "Bestellungen",
		AverageOrder:       "Ø Warenkorb",
		PaymentBreakdown:   "Nach Zahlungsmittel",
		OrderTypeBreakdown: "Nach Bestelltyp",
		TopProducts:        "Top 5 Produkte",
		StaffPerformance:   "Personalleistung",
		Cancellations:      "Stornos / Rückgaben / Rabatte",
		Voided:             "Storniert",
		Refunded:           "Erstattet",
		Discounts:          "Rabatt-Summe",
		OnlineOrders:       "Online-Bestellungen",
		Stockouts:          "Ausverkaufte Artikel",
		OpenInBackoffice:   "Vollständigen Bericht im Backoffice öffnen →",
		NoActivity:         "Heute keine Umsätze gebucht.",
		OrderTypeDineIn:    "Im Haus",
		OrderTypeTakeaway:  "Mitnahme",
		OrderTypeDelivery:  "Lieferung",
		OrderTypeOnline:    "Online",
		Footer:             "Versendet von GastroCore. Diesen Bericht abbestellen: Backoffice → Automatische Berichte.",
		ColMethod:          "Methode",
		ColTotal:           "Betrag",
		ColType:            "Typ",
		ColCount:           "Anzahl",
		ColProduct:         "Produkt",
		ColQty:             "Menge",
		ColStaff:           "Mitarbeiter",
		ColOrders:          "Bestellungen",
	},
	"en": {
		DigestSubject:      "Daily Sales Report — %s",
		Date:               "Date",
		Greeting:           "Hello,",
		Summary:            "Summary",
		Revenue:            "Total revenue",
		NetRevenue:         "Net (excl. VAT)",
		OrderCount:         "Order count",
		AverageOrder:       "Average ticket",
		PaymentBreakdown:   "Payment breakdown",
		OrderTypeBreakdown: "Order type breakdown",
		TopProducts:        "Top 5 products",
		StaffPerformance:   "Staff performance",
		Cancellations:      "Cancellations / refunds / discounts",
		Voided:             "Voided",
		Refunded:           "Refunded",
		Discounts:          "Discount total",
		OnlineOrders:       "Online orders",
		Stockouts:          "Out-of-stock items",
		OpenInBackoffice:   "Open full report in Backoffice →",
		NoActivity:         "No sales recorded today.",
		OrderTypeDineIn:    "Dine-in",
		OrderTypeTakeaway:  "Takeaway",
		OrderTypeDelivery:  "Delivery",
		OrderTypeOnline:    "Online",
		Footer:             "Sent by GastroCore. To unsubscribe: Backoffice → Automated reports.",
		ColMethod:          "Method",
		ColTotal:           "Amount",
		ColType:            "Type",
		ColCount:           "Count",
		ColProduct:         "Product",
		ColQty:             "Qty",
		ColStaff:           "Staff",
		ColOrders:          "Orders",
	},
	"fr": {
		DigestSubject:      "Rapport quotidien des ventes — %s",
		Date:               "Date",
		Greeting:           "Bonjour,",
		Summary:            "Résumé",
		Revenue:            "Chiffre d'affaires total",
		NetRevenue:         "Net (hors TVA)",
		OrderCount:         "Nombre de commandes",
		AverageOrder:       "Ticket moyen",
		PaymentBreakdown:   "Par moyen de paiement",
		OrderTypeBreakdown: "Par type de commande",
		TopProducts:        "Top 5 produits",
		StaffPerformance:   "Performance du personnel",
		Cancellations:      "Annulations / remboursements / remises",
		Voided:             "Annulés",
		Refunded:           "Remboursés",
		Discounts:          "Total remises",
		OnlineOrders:       "Commandes en ligne",
		Stockouts:          "Articles en rupture",
		OpenInBackoffice:   "Ouvrir le rapport complet dans Backoffice →",
		NoActivity:         "Aucune vente enregistrée aujourd'hui.",
		OrderTypeDineIn:    "Sur place",
		OrderTypeTakeaway:  "À emporter",
		OrderTypeDelivery:  "Livraison",
		OrderTypeOnline:    "En ligne",
		Footer:             "Envoyé par GastroCore. Pour se désabonner : Backoffice → Rapports automatisés.",
		ColMethod:          "Méthode",
		ColTotal:           "Montant",
		ColType:            "Type",
		ColCount:           "Quantité",
		ColProduct:         "Produit",
		ColQty:             "Qté",
		ColStaff:           "Personnel",
		ColOrders:          "Commandes",
	},
	"it": {
		DigestSubject:      "Report giornaliero vendite — %s",
		Date:               "Data",
		Greeting:           "Salve,",
		Summary:            "Riepilogo",
		Revenue:            "Fatturato totale",
		NetRevenue:         "Netto (IVA esclusa)",
		OrderCount:         "Numero ordini",
		AverageOrder:       "Scontrino medio",
		PaymentBreakdown:   "Per metodo di pagamento",
		OrderTypeBreakdown: "Per tipo ordine",
		TopProducts:        "Top 5 prodotti",
		StaffPerformance:   "Performance personale",
		Cancellations:      "Annullamenti / rimborsi / sconti",
		Voided:             "Annullati",
		Refunded:           "Rimborsati",
		Discounts:          "Totale sconti",
		OnlineOrders:       "Ordini online",
		Stockouts:          "Articoli esauriti",
		OpenInBackoffice:   "Apri il report completo in Backoffice →",
		NoActivity:         "Nessuna vendita registrata oggi.",
		OrderTypeDineIn:    "Al tavolo",
		OrderTypeTakeaway:  "Asporto",
		OrderTypeDelivery:  "Consegna",
		OrderTypeOnline:    "Online",
		Footer:             "Inviato da GastroCore. Per disattivare: Backoffice → Report automatici.",
		ColMethod:          "Metodo",
		ColTotal:           "Importo",
		ColType:            "Tipo",
		ColCount:           "Numero",
		ColProduct:         "Prodotto",
		ColQty:             "Qtà",
		ColStaff:           "Personale",
		ColOrders:          "Ordini",
	},
}

// l returns the translation table for the locale, falling back to TR.
func l(locale string) L10n {
	if v, ok := locales[locale]; ok {
		return v
	}
	return locales["tr"]
}

// formatCHF turns cents into "CHF 1'234.50" — Swiss convention, apostrophe
// thousands separator, period decimal.
func formatCHF(cents int64) string {
	whole := cents / 100
	cent := cents % 100
	if cents < 0 {
		whole = -whole
		cent = -cent
	}
	s := fmt.Sprintf("%d", whole)
	// Group every 3 digits from the right.
	n := len(s)
	if n > 3 {
		var b strings.Builder
		first := n % 3
		if first > 0 {
			b.WriteString(s[:first])
		}
		for i := first; i < n; i += 3 {
			if i > 0 {
				b.WriteByte('\'')
			}
			b.WriteString(s[i : i+3])
		}
		s = b.String()
	}
	sign := ""
	if cents < 0 {
		sign = "-"
	}
	return fmt.Sprintf("%sCHF %s.%02d", sign, s, cent)
}

func orderTypeLabel(t L10n, ot string) string {
	switch strings.ToLower(ot) {
	case "dine_in", "dinein", "im_haus", "im haus", "":
		return t.OrderTypeDineIn
	case "takeaway", "take_away", "take-away", "mitnahme":
		return t.OrderTypeTakeaway
	case "delivery", "lieferung":
		return t.OrderTypeDelivery
	case "online":
		return t.OrderTypeOnline
	default:
		return ot
	}
}

// digestView is the data shape passed into the html template.
type digestView struct {
	L             L10n
	D             *DailyDigest
	Title         string // pre-formatted "Günlük Satış Raporu — 17.05.2026"
	DateStr       string
	Revenue       string
	Net           string
	AvgOrder      string
	Payments      []paymentView
	OrderTypes    []orderTypeView
	TopProducts   []topProductView
	Staff         []staffView
	VoidedAmt     string
	RefundedAmt   string
	DiscountAmt   string
	BackofficeURL string
}

type paymentView struct {
	Method string
	Total  string
}
type orderTypeView struct {
	Label string
	Total string
	Count int64
}
type topProductView struct {
	Name  string
	Qty   string
	Total string
}
type staffView struct {
	Name    string
	Orders  int64
	Revenue string
}

// digestTpl is the shared HTML email template. Mobile-friendly, inline CSS
// (Gmail/Outlook strip <style> tags from <head>).
var digestTpl = template.Must(template.New("digest").Parse(`<!DOCTYPE html>
<html><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#f6f7f9;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#1a1a1a">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f6f7f9;padding:24px 0">
  <tr><td align="center">
    <table role="presentation" width="600" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.06)">
      <tr><td style="background:linear-gradient(135deg,#0f172a,#1e293b);color:#fff;padding:24px 32px">
        <div style="font-size:13px;letter-spacing:1px;opacity:0.7;text-transform:uppercase">GastroCore</div>
        <h1 style="margin:4px 0 0;font-size:22px;font-weight:700">{{.Title}}</h1>
        <div style="margin-top:4px;font-size:14px;opacity:0.85">{{.D.TenantName}} · {{.DateStr}}</div>
      </td></tr>

      {{if eq .D.OrderCount 0}}
      <tr><td style="padding:32px;text-align:center;color:#64748b">
        <p style="margin:0">{{.L.NoActivity}}</p>
      </td></tr>
      {{else}}

      <tr><td style="padding:24px 32px">
        <h2 style="margin:0 0 12px;font-size:16px;color:#0f172a">{{.L.Summary}}</h2>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
          <tr>
            <td style="padding:12px;border:1px solid #e2e8f0;border-radius:8px;width:50%">
              <div style="font-size:12px;color:#64748b">{{.L.Revenue}}</div>
              <div style="font-size:22px;font-weight:700;color:#0f172a">{{.Revenue}}</div>
            </td>
            <td style="width:12px"></td>
            <td style="padding:12px;border:1px solid #e2e8f0;border-radius:8px;width:50%">
              <div style="font-size:12px;color:#64748b">{{.L.NetRevenue}}</div>
              <div style="font-size:22px;font-weight:700;color:#0f172a">{{.Net}}</div>
            </td>
          </tr>
          <tr><td style="height:12px"></td><td></td><td></td></tr>
          <tr>
            <td style="padding:12px;border:1px solid #e2e8f0;border-radius:8px">
              <div style="font-size:12px;color:#64748b">{{.L.OrderCount}}</div>
              <div style="font-size:22px;font-weight:700;color:#0f172a">{{.D.OrderCount}}</div>
            </td>
            <td></td>
            <td style="padding:12px;border:1px solid #e2e8f0;border-radius:8px">
              <div style="font-size:12px;color:#64748b">{{.L.AverageOrder}}</div>
              <div style="font-size:22px;font-weight:700;color:#0f172a">{{.AvgOrder}}</div>
            </td>
          </tr>
        </table>
      </td></tr>

      {{if .Payments}}
      <tr><td style="padding:8px 32px 16px">
        <h2 style="margin:0 0 8px;font-size:15px;color:#0f172a">{{.L.PaymentBreakdown}}</h2>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;font-size:14px">
          <tr style="background:#f8fafc"><th align="left" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColMethod}}</th><th align="right" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColTotal}}</th></tr>
          {{range .Payments}}<tr><td style="padding:8px;border-bottom:1px solid #f1f5f9">{{.Method}}</td><td align="right" style="padding:8px;border-bottom:1px solid #f1f5f9;font-variant-numeric:tabular-nums">{{.Total}}</td></tr>{{end}}
        </table>
      </td></tr>
      {{end}}

      {{if .OrderTypes}}
      <tr><td style="padding:8px 32px 16px">
        <h2 style="margin:0 0 8px;font-size:15px;color:#0f172a">{{.L.OrderTypeBreakdown}}</h2>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;font-size:14px">
          <tr style="background:#f8fafc"><th align="left" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColType}}</th><th align="right" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColCount}}</th><th align="right" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColTotal}}</th></tr>
          {{range .OrderTypes}}<tr><td style="padding:8px;border-bottom:1px solid #f1f5f9">{{.Label}}</td><td align="right" style="padding:8px;border-bottom:1px solid #f1f5f9;font-variant-numeric:tabular-nums">{{.Count}}</td><td align="right" style="padding:8px;border-bottom:1px solid #f1f5f9;font-variant-numeric:tabular-nums">{{.Total}}</td></tr>{{end}}
        </table>
      </td></tr>
      {{end}}

      {{if .TopProducts}}
      <tr><td style="padding:8px 32px 16px">
        <h2 style="margin:0 0 8px;font-size:15px;color:#0f172a">{{.L.TopProducts}}</h2>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;font-size:14px">
          <tr style="background:#f8fafc"><th align="left" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColProduct}}</th><th align="right" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColQty}}</th><th align="right" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColTotal}}</th></tr>
          {{range .TopProducts}}<tr><td style="padding:8px;border-bottom:1px solid #f1f5f9">{{.Name}}</td><td align="right" style="padding:8px;border-bottom:1px solid #f1f5f9;font-variant-numeric:tabular-nums">{{.Qty}}</td><td align="right" style="padding:8px;border-bottom:1px solid #f1f5f9;font-variant-numeric:tabular-nums">{{.Total}}</td></tr>{{end}}
        </table>
      </td></tr>
      {{end}}

      {{if .Staff}}
      <tr><td style="padding:8px 32px 16px">
        <h2 style="margin:0 0 8px;font-size:15px;color:#0f172a">{{.L.StaffPerformance}}</h2>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;font-size:14px">
          <tr style="background:#f8fafc"><th align="left" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColStaff}}</th><th align="right" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColOrders}}</th><th align="right" style="padding:8px;border-bottom:1px solid #e2e8f0">{{.L.ColTotal}}</th></tr>
          {{range .Staff}}<tr><td style="padding:8px;border-bottom:1px solid #f1f5f9">{{.Name}}</td><td align="right" style="padding:8px;border-bottom:1px solid #f1f5f9;font-variant-numeric:tabular-nums">{{.Orders}}</td><td align="right" style="padding:8px;border-bottom:1px solid #f1f5f9;font-variant-numeric:tabular-nums">{{.Revenue}}</td></tr>{{end}}
        </table>
      </td></tr>
      {{end}}

      <tr><td style="padding:8px 32px 24px">
        <h2 style="margin:0 0 8px;font-size:15px;color:#0f172a">{{.L.Cancellations}}</h2>
        <div style="font-size:14px;color:#475569">{{.L.Voided}}: <b style="color:#0f172a">{{.D.Cancellations.VoidedCount}} ({{.VoidedAmt}})</b> · {{.L.Refunded}}: <b style="color:#0f172a">{{.D.Cancellations.RefundedCount}} ({{.RefundedAmt}})</b> · {{.L.Discounts}}: <b style="color:#0f172a">{{.DiscountAmt}}</b></div>
        <div style="margin-top:6px;font-size:13px;color:#475569">{{.L.OnlineOrders}}: <b>{{.D.OnlineOrders}}</b> · {{.L.Stockouts}}: <b>{{.D.StockoutsCount}}</b></div>
      </td></tr>

      <tr><td align="center" style="padding:0 32px 24px">
        <a href="{{.BackofficeURL}}/tr/reports" style="display:inline-block;background:#0f172a;color:#fff;text-decoration:none;padding:12px 20px;border-radius:8px;font-size:14px;font-weight:600">{{.L.OpenInBackoffice}}</a>
      </td></tr>

      {{end}}

      <tr><td style="background:#f8fafc;padding:16px 32px;font-size:12px;color:#94a3b8;line-height:1.5">{{.L.Footer}}</td></tr>
    </table>
  </td></tr>
</table>
</body></html>`))

// RenderDigest produces (subject, htmlBody) for the given digest + locale.
func (m *Module) RenderDigest(d *DailyDigest, locale string) (subject, html string, err error) {
	t := l(locale)
	dateStr := d.Date.Format("02.01.2006")
	subject = fmt.Sprintf(t.DigestSubject, dateStr)

	v := digestView{
		L:             t,
		D:             d,
		Title:         subject,
		DateStr:       dateStr,
		Revenue:       formatCHF(d.Revenue),
		Net:           formatCHF(d.Net),
		AvgOrder:      formatCHF(d.AverageOrder),
		VoidedAmt:     formatCHF(d.Cancellations.VoidedAmount),
		RefundedAmt:   formatCHF(d.Cancellations.RefundedAmount),
		DiscountAmt:   formatCHF(d.Cancellations.DiscountAmount),
		BackofficeURL: m.cfg.BackofficeURLBase,
	}
	for _, p := range d.ByPayment {
		v.Payments = append(v.Payments, paymentView{Method: p.Method, Total: formatCHF(p.Total)})
	}
	for _, o := range d.ByOrderType {
		v.OrderTypes = append(v.OrderTypes, orderTypeView{Label: orderTypeLabel(t, o.OrderType), Count: o.Count, Total: formatCHF(o.Total)})
	}
	for _, p := range d.TopProducts {
		v.TopProducts = append(v.TopProducts, topProductView{Name: p.Name, Qty: fmt.Sprintf("%.0f", p.Quantity), Total: formatCHF(p.Total)})
	}
	for _, s := range d.StaffPerf {
		v.Staff = append(v.Staff, staffView{Name: s.Name, Orders: s.OrderCount, Revenue: formatCHF(s.Revenue)})
	}

	var buf bytes.Buffer
	if err := digestTpl.Execute(&buf, v); err != nil {
		return "", "", err
	}
	return subject, buf.String(), nil
}

