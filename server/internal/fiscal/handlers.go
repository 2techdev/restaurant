package fiscal

import (
	"encoding/json"
	"net/http"
)

// handler holds the HTTP handlers for the fiscal module.
type handler struct {
	fiskaly *FiskalyClient
}

func (h *handler) handleInitTSE(w http.ResponseWriter, r *http.Request) {
	var req struct {
		TSSID       string `json:"tss_id"`
		Description string `json:"description"`
		AdminPin    string `json:"admin_pin"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request"}`, http.StatusBadRequest)
		return
	}
	info, err := h.fiskaly.InitializeTSS(req.TSSID, req.AdminPin)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func (h *handler) handleTSEStatus(w http.ResponseWriter, r *http.Request) {
	tssID := r.URL.Query().Get("tss_id")
	if tssID == "" {
		http.Error(w, `{"error":"tss_id required"}`, http.StatusBadRequest)
		return
	}
	info, err := h.fiskaly.GetTSSInfo(tssID)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func (h *handler) handleSelfTest(w http.ResponseWriter, r *http.Request) {
	var req struct {
		TSSID string `json:"tss_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request"}`, http.StatusBadRequest)
		return
	}
	info, err := h.fiskaly.RunSelfTest(req.TSSID)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func (h *handler) handleSignTransaction(w http.ResponseWriter, r *http.Request) {
	var req struct {
		TSSID         string             `json:"tss_id"`
		TransactionID string             `json:"transaction_id"`
		ClientID      string             `json:"client_id"`
		PaymentType   string             `json:"payment_type"`
		PaymentAmount string             `json:"payment_amount"`
		TxRevision    int                `json:"tx_revision"`
		AmountsPerVatRate []AmountPerVatRate `json:"amounts_per_vat_rate"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request"}`, http.StatusBadRequest)
		return
	}
	if req.TxRevision <= 0 {
		req.TxRevision = 2
	}
	resp, err := h.fiskaly.FinishTransaction(
		req.TSSID, req.TransactionID, req.ClientID,
		req.AmountsPerVatRate, req.PaymentType, req.PaymentAmount,
		req.TxRevision,
	)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func (h *handler) handleExportDSFinVK(w http.ResponseWriter, r *http.Request) {
	tssID := r.URL.Query().Get("tss_id")
	exportID := r.URL.Query().Get("export_id")
	if tssID == "" {
		http.Error(w, `{"error":"tss_id required"}`, http.StatusBadRequest)
		return
	}
	if exportID != "" {
		resp, err := h.fiskaly.GetExportStatus(tssID, exportID)
		if err != nil {
			http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
		return
	}
	resp, err := h.fiskaly.TriggerExport(tssID, nil, nil)
	if err != nil {
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
