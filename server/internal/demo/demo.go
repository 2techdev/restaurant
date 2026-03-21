// Package demo serves the self-contained online ordering demo page at /demo.
package demo

import (
	_ "embed"
	"net/http"
)

//go:embed demo.html
var demoHTML []byte

// Handler returns an http.HandlerFunc that serves the demo page.
func Handler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "public, max-age=300")
		w.WriteHeader(http.StatusOK)
		w.Write(demoHTML)
	}
}
