// Package docs embeds and serves the OpenAPI 3.0 specification.
package docs

import (
	_ "embed"
	"net/http"
)

//go:embed swagger.json
var swaggerJSON []byte

// Handler returns an http.HandlerFunc that serves the swagger.json spec.
func Handler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.WriteHeader(http.StatusOK)
		w.Write(swaggerJSON)
	}
}

// UIHandler returns a minimal Swagger UI redirect page.
func UIHandler() http.HandlerFunc {
	const html = `<!DOCTYPE html>
<html>
<head>
  <title>GastroCore API</title>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
<script>
  SwaggerUIBundle({
    url: "/docs/swagger.json",
    dom_id: '#swagger-ui',
    presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
    layout: "StandaloneLayout"
  });
</script>
</body>
</html>`
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(html))
	}
}
