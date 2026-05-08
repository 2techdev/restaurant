package menu

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

// GastroHubClient calls Reservation's /api/gastrocore/* endpoints with an
// HMAC-signed request. Used by the magic-link import flow to fetch a one-time
// menu snapshot keyed by token.
//
// Auth contract (matches Reservation backend):
//   - Header X-GastroCore-Signature: sha256=<hex>
//   - HMAC-SHA256 over: METHOD + "\n" + path + "\n" + body
//   - Shared secret: env GASTROCORE_SERVICE_SECRET
//
// The default base URL is "https://gastro.2hub.ch" but can be overridden
// per-request (admin in dev points to staging).
type GastroHubClient struct {
	baseURL string
	secret  string
	http    *http.Client
}

// NewGastroHubClient builds a client from env vars. Returns an error when
// GASTROCORE_SERVICE_SECRET is unset — failing closed is preferable to
// shipping unauthenticated requests in prod.
func NewGastroHubClient() (*GastroHubClient, error) {
	base := strings.TrimRight(strings.TrimSpace(os.Getenv("GASTROHUB_BASE_URL")), "/")
	if base == "" {
		base = "https://gastro.2hub.ch"
	}
	secret := strings.TrimSpace(os.Getenv("GASTROCORE_SERVICE_SECRET"))
	if secret == "" {
		return nil, errors.New("gastrohub: GASTROCORE_SERVICE_SECRET is required")
	}
	return &GastroHubClient{
		baseURL: base,
		secret:  secret,
		http: &http.Client{
			Timeout: 30 * time.Second,
		},
	}, nil
}

// withBaseURL returns a shallow copy with a different base URL. Lets the
// import handler honor a per-request override without mutating the shared
// client. Empty override is a no-op.
func (c *GastroHubClient) withBaseURL(override string) *GastroHubClient {
	override = strings.TrimRight(strings.TrimSpace(override), "/")
	if override == "" {
		return c
	}
	cp := *c
	cp.baseURL = override
	return &cp
}

// signature returns the hex-encoded HMAC-SHA256 of "METHOD\npath\nbody".
func (c *GastroHubClient) signature(method, path string, body []byte) string {
	mac := hmac.New(sha256.New, []byte(c.secret))
	mac.Write([]byte(method))
	mac.Write([]byte("\n"))
	mac.Write([]byte(path))
	mac.Write([]byte("\n"))
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

// fetchSnapshotByToken hits GET /api/gastrocore/menu/by-token/{token} on
// Reservation and decodes the JSON envelope. Token format is enforced
// upstream (handler validates) — here we trust caller and just URL-escape.
//
// Returns:
//   - non-nil envelope on 200
//   - status-coded error on 404/410/429/5xx (caller maps to HTTP response)
func (c *GastroHubClient) fetchSnapshotByToken(ctx context.Context, token string) (*snapshotEnvelope, error) {
	path := "/api/gastrocore/menu/by-token/" + url.PathEscape(token)
	endpoint := c.baseURL + path

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("gastrohub: build request: %w", err)
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "gastrocore-pos-import/1.0")
	req.Header.Set("X-GastroCore-Signature", "sha256="+c.signature(http.MethodGet, path, nil))

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gastrohub: http error: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20)) // 4 MiB cap
	if err != nil {
		return nil, fmt.Errorf("gastrohub: read body: %w", err)
	}

	switch resp.StatusCode {
	case http.StatusOK:
		var env snapshotEnvelope
		if err := json.Unmarshal(body, &env); err != nil {
			return nil, fmt.Errorf("gastrohub: decode snapshot: %w", err)
		}
		return &env, nil
	case http.StatusNotFound:
		return nil, &ClientError{Status: http.StatusNotFound, Code: "TOKEN_NOT_FOUND", Message: "Magic-link token not found"}
	case http.StatusGone:
		return nil, &ClientError{Status: http.StatusGone, Code: "TOKEN_EXPIRED", Message: "Magic-link token expired or already consumed"}
	case http.StatusTooManyRequests:
		return nil, &ClientError{Status: http.StatusTooManyRequests, Code: "RATE_LIMITED", Message: "Reservation rate-limited the request"}
	case http.StatusUnauthorized, http.StatusForbidden:
		return nil, &ClientError{Status: resp.StatusCode, Code: "UPSTREAM_AUTH", Message: "HMAC signature rejected by Reservation"}
	default:
		preview := string(body)
		if len(preview) > 200 {
			preview = preview[:200] + "…"
		}
		return nil, &ClientError{
			Status:  http.StatusBadGateway,
			Code:    "UPSTREAM_ERROR",
			Message: fmt.Sprintf("Reservation returned %d: %s", resp.StatusCode, preview),
		}
	}
}

// ClientError carries an upstream-facing HTTP status so the handler can
// translate cleanly to its own response.
type ClientError struct {
	Status  int
	Code    string
	Message string
}

func (e *ClientError) Error() string {
	return fmt.Sprintf("gastrohub: %s (status=%d, code=%s)", e.Message, e.Status, e.Code)
}
