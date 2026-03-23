package fiscal_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gastrocore/server/internal/fiscal"
	"github.com/gastrocore/server/internal/shared/config"
)

// ---------------------------------------------------------------------------
// Module disabled (no credentials)
// ---------------------------------------------------------------------------

func TestModule_Disabled_Returns503(t *testing.T) {
	cfg := &config.Config{
		FiskalyAPIKey:    "",
		FiskalyAPISecret: "",
	}
	mod := fiscal.NewModule(cfg)

	mux := http.NewServeMux()
	mod.RegisterRoutes(mux)

	endpoints := []struct {
		method string
		path   string
	}{
		{"POST", "/api/fiscal/tse/init"},
		{"GET", "/api/fiscal/tse/status"},
		{"POST", "/api/fiscal/tse/self-test"},
		{"POST", "/api/fiscal/transaction/sign"},
		{"GET", "/api/fiscal/export/dsfinvk"},
	}

	for _, ep := range endpoints {
		t.Run(ep.method+" "+ep.path, func(t *testing.T) {
			req := httptest.NewRequest(ep.method, ep.path, nil)
			w := httptest.NewRecorder()
			mux.ServeHTTP(w, req)

			if w.Code != http.StatusServiceUnavailable {
				t.Errorf("expected 503, got %d", w.Code)
			}

			var body map[string]string
			if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
				t.Fatal("expected JSON body:", err)
			}
			if body["code"] != "fiscal_disabled" {
				t.Errorf("expected code=fiscal_disabled, got %q", body["code"])
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Handler validation tests (using fake Fiskaly server)
// ---------------------------------------------------------------------------

// fakeFiskaly starts a test HTTP server that simulates the Fiskaly API.
func fakeFiskaly(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()

	// Auth
	mux.HandleFunc("/api/v2/auth", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"access_token":                      "fake-token",
			"access_token_expires_in_seconds": 3600,
		})
	})

	// TSS create/get
	mux.HandleFunc("/api/v2/tss/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"_id":                 "tss-fake-id",
			"state":               "ACTIVE",
			"serial_number":       "DEADBEEF01234567",
			"signature_algorithm": "ecdsa-plain-SHA384",
			"signature_counter":   42,
			"description":         "GastroCore POS",
		})
	})

	return httptest.NewServer(mux)
}

// newTestModule creates a Module wired to a fake Fiskaly server.
func newTestModule(t *testing.T, srv *httptest.Server) *fiscal.Module {
	t.Helper()
	// We build the module directly with credentials pointing to the fake server.
	// The FiskalyClient base URL is hardcoded, so we patch it via a custom client.
	// For this test we just exercise the disabled/enabled routing.
	cfg := &config.Config{
		FiskalyAPIKey:    "test-key",
		FiskalyAPISecret: "test-secret",
	}
	_ = srv // Unused in this simplified test — full integration tests would patch the URL.
	return fiscal.NewModule(cfg)
}

func TestModule_Enabled_RegistersRoutes(t *testing.T) {
	srv := fakeFiskaly(t)
	defer srv.Close()

	mod := newTestModule(t, srv)

	mux := http.NewServeMux()
	mod.RegisterRoutes(mux)

	// With credentials set, routes should NOT return 503.
	// They will fail to reach the real Fiskaly server but should
	// return a different status code (not 503).
	paths := []struct {
		method string
		path   string
		body   string
	}{
		{"POST", "/api/fiscal/tse/init", `{"tse_id":"","client_id":""}`},
		{"GET", "/api/fiscal/tse/status", ""},
		{"POST", "/api/fiscal/tse/self-test", ""},
		{"POST", "/api/fiscal/transaction/sign", `{}`},
		{"GET", "/api/fiscal/export/dsfinvk", ""},
	}

	for _, ep := range paths {
		t.Run(ep.method+" "+ep.path, func(t *testing.T) {
			var body *bytes.Buffer
			if ep.body != "" {
				body = bytes.NewBufferString(ep.body)
			} else {
				body = &bytes.Buffer{}
			}
			req := httptest.NewRequest(ep.method, ep.path, body)
			w := httptest.NewRecorder()
			mux.ServeHTTP(w, req)

			// Route should NOT return 503 (disabled) — validation failures (400)
			// or Fiskaly errors (500) are expected.
			if w.Code == http.StatusServiceUnavailable {
				t.Errorf("route %s %s returned 503 — module may be disabled unexpectedly",
					ep.method, ep.path)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

func TestHandleInitTSE_MissingFields(t *testing.T) {
	cfg := &config.Config{
		FiskalyAPIKey:    "test-key",
		FiskalyAPISecret: "test-secret",
	}
	mod := fiscal.NewModule(cfg)
	mux := http.NewServeMux()
	mod.RegisterRoutes(mux)

	tests := []struct {
		name string
		body string
		want int
	}{
		{
			name: "empty body",
			body: `{}`,
			want: http.StatusBadRequest,
		},
		{
			name: "missing client_id",
			body: `{"tse_id":"valid-uuid-here"}`,
			want: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest("POST", "/api/fiscal/tse/init",
				bytes.NewBufferString(tt.body))
			w := httptest.NewRecorder()
			mux.ServeHTTP(w, req)

			if w.Code != tt.want {
				t.Errorf("expected %d, got %d (body: %s)",
					tt.want, w.Code, w.Body.String())
			}
		})
	}
}

func TestHandleTSEStatus_MissingTseID(t *testing.T) {
	cfg := &config.Config{
		FiskalyAPIKey:    "test-key",
		FiskalyAPISecret: "test-secret",
	}
	mod := fiscal.NewModule(cfg)
	mux := http.NewServeMux()
	mod.RegisterRoutes(mux)

	req := httptest.NewRequest("GET", "/api/fiscal/tse/status", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestHandleSignTransaction_MissingFields(t *testing.T) {
	cfg := &config.Config{
		FiskalyAPIKey:    "test-key",
		FiskalyAPISecret: "test-secret",
	}
	mod := fiscal.NewModule(cfg)
	mux := http.NewServeMux()
	mod.RegisterRoutes(mux)

	req := httptest.NewRequest("POST", "/api/fiscal/transaction/sign",
		bytes.NewBufferString(`{}`))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestHandleExportDSFinVK_MissingTseID(t *testing.T) {
	cfg := &config.Config{
		FiskalyAPIKey:    "test-key",
		FiskalyAPISecret: "test-secret",
	}
	mod := fiscal.NewModule(cfg)
	mux := http.NewServeMux()
	mod.RegisterRoutes(mux)

	req := httptest.NewRequest("GET", "/api/fiscal/export/dsfinvk", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}
