package qrbill

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// handleGenerateQRBill processes POST /api/invoices/qrbill.
// Requires a valid JWT (enforced by middleware in main.go).
func (m *Module) handleGenerateQRBill(w http.ResponseWriter, r *http.Request) {
	var req QRBillRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "INVALID_BODY", "Invalid request body")
		return
	}

	// ---- Validation ----
	ibanClean := strings.ReplaceAll(req.IBAN, " ", "")
	if len(ibanClean) < 15 {
		response.Error(w, http.StatusBadRequest, "INVALID_IBAN", "IBAN is missing or too short")
		return
	}
	if req.CreditorName == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_CREDITOR_NAME", "creditor_name is required")
		return
	}
	refType := strings.ToUpper(req.ReferenceType)
	if refType == "" {
		refType = "NON"
	}
	if (refType == "QRR" || refType == "SCOR") && req.Reference == "" {
		response.Error(w, http.StatusBadRequest, "MISSING_REFERENCE",
			"reference is required when reference_type is QRR or SCOR")
		return
	}

	// ---- Defaults ----
	if req.Currency == "" {
		req.Currency = "CHF"
	}
	if req.CreditorCountry == "" {
		req.CreditorCountry = "CH"
	}
	req.ReferenceType = refType

	// ---- Generate QR data ----
	qrData := GenerateQRData(&req)

	creditorAddr := OneLineAddress(req.CreditorStreet, req.CreditorZip, req.CreditorCity)
	debtorAddr := ""
	if req.DebtorName != "" {
		debtorAddr = OneLineAddress(req.DebtorStreet, req.DebtorZip, req.DebtorCity)
	}

	resp := QRBillResponse{
		QRData:          qrData,
		IBAN:            FormatIBAN(req.IBAN),
		AmountFormatted: FormatAmount(req.Amount, req.Currency),
		Currency:        req.Currency,
		ReferenceType:   refType,
		Reference:       req.Reference,
		CreditorName:    req.CreditorName,
		CreditorAddress: creditorAddr,
		DebtorName:      req.DebtorName,
		DebtorAddress:   debtorAddr,
		Message:         req.Message,
		InvoiceID:       req.InvoiceID,
		GeneratedAt:     time.Now().UTC(),
	}

	slog.Info("qrbill: generated",
		"iban_prefix", ibanClean[:4],
		"amount", req.Amount,
		"currency", req.Currency,
		"ref_type", refType,
		"iban_len", len(ibanClean),
	)

	response.JSON(w, http.StatusOK, resp)
}
