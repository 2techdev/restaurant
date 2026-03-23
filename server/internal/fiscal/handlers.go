package fiscal

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gastrocore/server/internal/shared/response"
)

// handler holds the Fiskaly client for request handling.
type handler struct {
	fiskaly *FiskalyClient
}

// ---------------------------------------------------------------------------
// POST /api/fiscal/tse/init
// ---------------------------------------------------------------------------

// handleInitTSE initializes a TSE through the full lifecycle:
// create → initialize → activate → register client.
func (h *handler) handleInitTSE(w http.ResponseWriter, r *http.Request) {
	var req InitTSERequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "bad_request", "invalid request body: "+err.Error())
		return
	}

	if req.TSEID == "" {
		response.Error(w, http.StatusBadRequest, "bad_request", "tse_id is required")
		return
	}
	if req.ClientID == "" {
		response.Error(w, http.StatusBadRequest, "bad_request", "client_id is required")
		return
	}
	if req.AdminPin == "" {
		req.AdminPin = "12345" // default pin for test environment
	}

	desc := req.Description
	if desc == "" {
		desc = "GastroCore POS"
	}

	// Step 1: Create TSS
	info, err := h.fiskaly.CreateTSS(req.TSEID, desc)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "fiskaly_error", "create TSS: "+err.Error())
		return
	}

	// Step 2: Initialize if needed
	if info.State == TSSStateCreated {
		info, err = h.fiskaly.InitializeTSS(req.TSEID, req.AdminPin)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "fiskaly_error", "initialize TSS: "+err.Error())
			return
		}
	}

	// Step 3: Activate if needed
	if info.State == TSSStateInitialized {
		info, err = h.fiskaly.ActivateTSS(req.TSEID, req.AdminPin)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "fiskaly_error", "activate TSS: "+err.Error())
			return
		}
	}

	// Step 4: Register client
	serialNumber := fmt.Sprintf("GASTROCORE-%s", req.ClientID[:8])
	if err := h.fiskaly.RegisterClient(req.TSEID, req.ClientID, serialNumber); err != nil {
		response.Error(w, http.StatusInternalServerError, "fiskaly_error", "register client: "+err.Error())
		return
	}

	response.JSON(w, http.StatusOK, InitTSEResponse{
		TSEID:        req.TSEID,
		ClientID:     req.ClientID,
		State:        info.State,
		SerialNumber: info.SerialNumber,
	})
}

// ---------------------------------------------------------------------------
// GET /api/fiscal/tse/status
// ---------------------------------------------------------------------------

// handleTSEStatus returns the current TSS state.
func (h *handler) handleTSEStatus(w http.ResponseWriter, r *http.Request) {
	tseID := r.URL.Query().Get("tse_id")
	if tseID == "" {
		response.Error(w, http.StatusBadRequest, "bad_request", "tse_id query parameter is required")
		return
	}

	info, err := h.fiskaly.GetTSSInfo(tseID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "fiskaly_error", "get TSS info: "+err.Error())
		return
	}

	response.JSON(w, http.StatusOK, info)
}

// ---------------------------------------------------------------------------
// POST /api/fiscal/transaction/sign
// ---------------------------------------------------------------------------

// handleSignTransaction starts and finishes a Fiskaly transaction,
// returning the signature data to embed in the receipt.
func (h *handler) handleSignTransaction(w http.ResponseWriter, r *http.Request) {
	var req SignTransactionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, "bad_request", "invalid request body: "+err.Error())
		return
	}
	if req.TransactionID == "" {
		response.Error(w, http.StatusBadRequest, "bad_request", "transaction_id is required")
		return
	}
	if req.TSEID == "" {
		response.Error(w, http.StatusBadRequest, "bad_request", "tse_id is required")
		return
	}
	if req.ClientID == "" {
		response.Error(w, http.StatusBadRequest, "bad_request", "client_id is required")
		return
	}

	// Start transaction
	_, err := h.fiskaly.StartTransaction(req.TSEID, req.TransactionID, req.ClientID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "fiskaly_error", "start transaction: "+err.Error())
		return
	}

	// Finish and sign
	finished, err := h.fiskaly.FinishTransaction(
		req.TSEID,
		req.TransactionID,
		req.ClientID,
		req.AmountsPerVatRate,
		req.PaymentType,
		req.PaymentAmount,
		2, // tx_revision=2 for simple start→finish
	)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "fiskaly_error", "finish transaction: "+err.Error())
		return
	}

	endTime := time.Now()
	if finished.TimeEnd != nil {
		endTime = *finished.TimeEnd
	}

	response.JSON(w, http.StatusOK, SignTransactionResponse{
		TransactionNumber: finished.TransactionNumber,
		SignatureCounter:  finished.Signature.SignatureCounter,
		StartTime:         finished.TimeStart,
		EndTime:           endTime,
		SignatureValue:    finished.Signature.Value,
		TSESerialNumber:   finished.TSE.SerialNumber,
		Algorithm:         finished.TSE.SignatureAlgorithm,
		PublicKey:         finished.TSE.PublicKey,
		ProcessType:       finished.ProcessType,
		ProcessData:       finished.ProcessData,
	})
}

// ---------------------------------------------------------------------------
// GET /api/fiscal/export/dsfinvk
// ---------------------------------------------------------------------------

// handleExportDSFinVK triggers or polls a DSFinV-K export on Fiskaly.
func (h *handler) handleExportDSFinVK(w http.ResponseWriter, r *http.Request) {
	tseID := r.URL.Query().Get("tse_id")
	if tseID == "" {
		response.Error(w, http.StatusBadRequest, "bad_request", "tse_id query parameter is required")
		return
	}

	// Optional export ID for polling
	exportID := r.URL.Query().Get("export_id")
	if exportID != "" {
		status, err := h.fiskaly.GetExportStatus(tseID, exportID)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, "fiskaly_error", "get export status: "+err.Error())
			return
		}
		response.JSON(w, http.StatusOK, status)
		return
	}

	// Trigger new export
	var startDate, endDate *time.Time

	if s := r.URL.Query().Get("start_date"); s != "" {
		t, err := time.Parse("2006-01-02", s)
		if err == nil {
			startDate = &t
		}
	}
	if e := r.URL.Query().Get("end_date"); e != "" {
		t, err := time.Parse("2006-01-02", e)
		if err == nil {
			endDate = &t
		}
	}

	export, err := h.fiskaly.TriggerExport(tseID, startDate, endDate)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "fiskaly_error", "trigger export: "+err.Error())
		return
	}

	response.JSON(w, http.StatusAccepted, export)
}

// ---------------------------------------------------------------------------
// POST /api/fiscal/tse/self-test
// ---------------------------------------------------------------------------

// handleSelfTest triggers the TSS self-test.
func (h *handler) handleSelfTest(w http.ResponseWriter, r *http.Request) {
	tseID := r.URL.Query().Get("tse_id")
	if tseID == "" {
		response.Error(w, http.StatusBadRequest, "bad_request", "tse_id query parameter is required")
		return
	}
	info, err := h.fiskaly.RunSelfTest(tseID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, "fiskaly_error", "self test: "+err.Error())
		return
	}
	response.JSON(w, http.StatusOK, info)
}
