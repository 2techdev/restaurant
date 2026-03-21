package online

import (
	_ "embed"
	"net/http"
)

//go:embed demo.html
var demoHTML []byte

// handleDemo serves the standalone online-ordering demo page.
// GET /demo  — no backend, no auth, pure embedded HTML.
func handleDemo(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=300")
	w.Write(demoHTML)
}
