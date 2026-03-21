package qrbill

import (
	"fmt"
	"strings"
)

// GenerateQRData builds the Swiss QR-Bill data string according to
// Swiss Payment Standards 2.0 (SPS) specification.
//
// The string must be encoded as a QR code using:
//   - Error-correction level: M
//   - Character set: UTF-8
//   - Line separator: CRLF (\r\n)
func GenerateQRData(req *QRBillRequest) string {
	var sb strings.Builder

	w := func(s string) { sb.WriteString(s + "\r\n") }

	// -------------------------------------------------------------------------
	// Header
	// -------------------------------------------------------------------------
	w("SPC")  // Swiss Payments Code
	w("0200") // Version 2.0
	w("1")    // Coding type: Latin (UTF-8)

	// -------------------------------------------------------------------------
	// Creditor account
	// -------------------------------------------------------------------------
	w(strings.ReplaceAll(req.IBAN, " ", ""))

	// -------------------------------------------------------------------------
	// Creditor address (S = Structured)
	// -------------------------------------------------------------------------
	country := req.CreditorCountry
	if country == "" {
		country = "CH"
	}
	w("S")
	w(req.CreditorName)
	w(req.CreditorStreet) // Street or P.O. Box
	w("")                 // Building number (separate field in structured format)
	w(req.CreditorZip)
	w(req.CreditorCity)
	w(country)

	// -------------------------------------------------------------------------
	// Ultimate creditor (7 empty lines — reserved, must be blank)
	// -------------------------------------------------------------------------
	for i := 0; i < 7; i++ {
		w("")
	}

	// -------------------------------------------------------------------------
	// Payment amount
	// -------------------------------------------------------------------------
	currency := req.Currency
	if currency == "" {
		currency = "CHF"
	}
	if req.Amount > 0 {
		w(fmt.Sprintf("%.2f", req.Amount))
	} else {
		w("") // No amount — customer fills in
	}
	w(currency)

	// -------------------------------------------------------------------------
	// Ultimate debtor (payer)
	// -------------------------------------------------------------------------
	if req.DebtorName != "" {
		debtorCountry := req.DebtorCountry
		if debtorCountry == "" {
			debtorCountry = "CH"
		}
		w("S")
		w(req.DebtorName)
		w(req.DebtorStreet)
		w("") // Building number
		w(req.DebtorZip)
		w(req.DebtorCity)
		w(debtorCountry)
	} else {
		// 7 empty fields for optional debtor
		for i := 0; i < 7; i++ {
			w("")
		}
	}

	// -------------------------------------------------------------------------
	// Reference
	// -------------------------------------------------------------------------
	refType := strings.ToUpper(req.ReferenceType)
	if refType == "" {
		refType = "NON"
	}
	w(refType)
	w(req.Reference) // Empty for NON

	// -------------------------------------------------------------------------
	// Additional information
	// -------------------------------------------------------------------------
	w(req.Message) // Unstructured message

	// -------------------------------------------------------------------------
	// Trailer
	// -------------------------------------------------------------------------
	w("EPD") // End of Payment Data

	// Alternative procedure parameters (empty – not used)
	w("")
	w("")

	return sb.String()
}

// FormatIBAN formats an IBAN with spaces every 4 characters for readability.
// E.g. "CH5604835012345678009" → "CH56 0483 5012 3456 7800 9"
func FormatIBAN(iban string) string {
	raw := strings.ReplaceAll(iban, " ", "")
	var out strings.Builder
	for i, ch := range raw {
		if i > 0 && i%4 == 0 {
			out.WriteRune(' ')
		}
		out.WriteRune(ch)
	}
	return out.String()
}

// FormatAmount returns "CHF 150.50" style string.
func FormatAmount(amount float64, currency string) string {
	if currency == "" {
		currency = "CHF"
	}
	if amount <= 0 {
		return currency + " –.–"
	}
	return fmt.Sprintf("%s %.2f", currency, amount)
}

// OneLineAddress builds a single-line address from components.
func OneLineAddress(street, zip, city string) string {
	parts := []string{}
	if street != "" {
		parts = append(parts, street)
	}
	if zip != "" || city != "" {
		parts = append(parts, strings.TrimSpace(zip+" "+city))
	}
	return strings.Join(parts, ", ")
}
