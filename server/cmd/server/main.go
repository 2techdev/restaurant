package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/gastrocore/server/internal/audit"
	"github.com/gastrocore/server/internal/auth"
	"github.com/gastrocore/server/internal/crm"
	"github.com/gastrocore/server/internal/dashboard"
	"github.com/gastrocore/server/internal/devices"
	"github.com/gastrocore/server/internal/docs"
	"github.com/gastrocore/server/internal/feedback"
	"github.com/gastrocore/server/internal/fiscal"
	"github.com/gastrocore/server/internal/inventory"
	"github.com/gastrocore/server/internal/kds"
	"github.com/gastrocore/server/internal/license"
	"github.com/gastrocore/server/internal/licenses"
	"github.com/gastrocore/server/internal/menu"
	"github.com/gastrocore/server/internal/notifications"
	"github.com/gastrocore/server/internal/online"
	"github.com/gastrocore/server/internal/orders"
	"github.com/gastrocore/server/internal/org"
	"github.com/gastrocore/server/internal/pos"
	"github.com/gastrocore/server/internal/printers"
	"github.com/gastrocore/server/internal/promotions"
	"github.com/gastrocore/server/internal/qrbill"
	"github.com/gastrocore/server/internal/receipt_templates"
	"github.com/gastrocore/server/internal/reports"
	"github.com/gastrocore/server/internal/reservations"
	"github.com/gastrocore/server/internal/shared/config"
	"github.com/gastrocore/server/internal/shared/database"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/stations"
	"github.com/gastrocore/server/internal/stores"
	"github.com/gastrocore/server/internal/suppliers"
	"github.com/gastrocore/server/internal/tasks"
	"github.com/gastrocore/server/internal/users"
	gosync "github.com/gastrocore/server/internal/sync"
	"github.com/gastrocore/server/internal/tables"
)

const version = "1.0.0-beta.1"

func main() {
	// Load config
	cfg := config.Load()

	// Setup structured logging
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: cfg.LogLevel(),
	}))
	slog.SetDefault(logger)

	// Validate config — abort in production on fatal misconfigurations.
	if cfg.Validate() {
		slog.Error("fatal configuration error — aborting startup")
		os.Exit(1)
	}

	// Connect database
	db, err := database.Connect(cfg.DatabaseURL)
	if err != nil {
		slog.Error("failed to connect database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	// ---------------------------------------------------------------------------
	// KDS hub — must be started before modules that reference it.
	// ---------------------------------------------------------------------------
	kdsHub := kds.NewHub()
	go kdsHub.Run()

	onlineHub := online.NewOnlineHub()
	go onlineHub.Run()

	// ---------------------------------------------------------------------------
	// POS hub — real-time push for online orders to POS terminals.
	// ---------------------------------------------------------------------------
	posHub := pos.NewHub()
	go posHub.Run()

	// ---------------------------------------------------------------------------
	// Initialize modules
	// ---------------------------------------------------------------------------
	authModule := auth.NewModule(db, cfg)
	syncModule := gosync.NewModule(db, cfg)
	menuModule := menu.NewModuleWithHub(db, syncModule.SyncHub())
	ordersModule := orders.NewModule(db)
	onlineModule := online.NewModuleWithStripe(db, kdsHub, onlineHub, posHub, online.StripeConfig{
		SecretKey:      cfg.StripeSecretKey,
		WebhookSecret:  cfg.StripeWebhookSecret,
		SuccessURLBase: cfg.StripeSuccessURLBase,
	})
	reportsModule := reports.NewModule(db)
	dashboardModule := dashboard.NewModule(db)
	devicesModule := devices.NewModule(db)
	licensesModule := licenses.NewModule(db, cfg)
	licenseModule := license.NewModule(db, cfg)
	storesModule := stores.NewModule(db, cfg)
	kdsModule := kds.NewModule(db, kdsHub)
	// Fiscal compliance (Germany KassenSichV) — enabled when Fiskaly credentials set.
	fiscalModule := fiscal.NewModule(cfg)
	qrbillModule := qrbill.NewModule()
	crmModule := crm.NewModule(db, syncModule.SyncHub())
	reservationsModule := reservations.NewModule(db, syncModule.SyncHub())
	inventoryModule := inventory.NewModule(db)
	posModule := pos.NewModule(db, posHub)
	tablesModule := tables.NewModule(db, cfg)
	stationsModule := stations.NewModule(db, cfg)
	usersModule := users.NewModule(db, cfg)
	printersModule := printers.NewModule(db)
	orgModule := org.NewModule(db, syncModule.SyncHub())

	// Coverage extension (016)
	feedbackModule := feedback.NewModule(db)
	suppliersModule := suppliers.NewModule(db)
	promotionsModule := promotions.NewModule(db)
	auditModule := audit.NewModule(db)
	notificationsModule := notifications.NewModule(db)

	// Swiss-compliant receipt templates (020)
	receiptTemplatesModule := receipt_templates.NewModule(db)

	// HACCP digital checklist (039) — templates + scheduled instances + alerts
	tasksModule := tasks.NewModule(db)

	// ---------------------------------------------------------------------------
	// Build router
	// ---------------------------------------------------------------------------
	mux := http.NewServeMux()

	// Health check — includes DB connectivity.
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()

		dbStatus := "ok"
		if err := db.PingContext(ctx); err != nil {
			dbStatus = "error"
			slog.Warn("health: db ping failed", "error", err)
		}

		status := "ok"
		httpCode := http.StatusOK
		if dbStatus != "ok" {
			status = "degraded"
			httpCode = http.StatusServiceUnavailable
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(httpCode)
		json.NewEncoder(w).Encode(map[string]any{
			"status":  status,
			"version": version,
			"components": map[string]string{
				"database": dbStatus,
			},
		})
	})

	// /demo registered by onlineModule.RegisterRoutes below.

	// OpenAPI docs
	mux.HandleFunc("GET /docs/swagger.json", docs.Handler())
	mux.HandleFunc("GET /docs", docs.UIHandler())
	mux.HandleFunc("GET /docs/", docs.UIHandler())

	// Register module routes
	authModule.RegisterRoutes(mux)
	syncModule.RegisterRoutes(mux)
	menuModule.RegisterRoutes(mux)
	ordersModule.RegisterRoutes(mux)
	onlineModule.RegisterRoutes(mux)  // public — no auth
	reportsModule.RegisterRoutes(mux)
	dashboardModule.RegisterRoutes(mux)
	devicesModule.RegisterRoutes(mux)
	licensesModule.RegisterRoutes(mux)
	licenseModule.RegisterRoutes(mux)
	storesModule.RegisterRoutes(mux)
	kdsModule.RegisterRoutes(mux)
	fiscalModule.RegisterRoutes(mux)
	qrbillModule.RegisterRoutes(mux) // POST /api/invoices/qrbill — JWT required at call site
	crmModule.RegisterRoutes(mux)
	reservationsModule.RegisterRoutes(mux)
	inventoryModule.RegisterRoutes(mux)
	posModule.RegisterRoutes(mux)
	tablesModule.RegisterRoutes(mux)
	stationsModule.RegisterRoutes(mux)
	usersModule.RegisterRoutes(mux)
	printersModule.RegisterRoutes(mux)
	orgModule.RegisterRoutes(mux)

	// Coverage extension (016)
	feedbackModule.RegisterRoutes(mux)
	suppliersModule.RegisterRoutes(mux)
	promotionsModule.RegisterRoutes(mux)
	auditModule.RegisterRoutes(mux)
	notificationsModule.RegisterRoutes(mux)

	// Receipt templates (020) — Swiss MWST-compliant printable layouts
	receiptTemplatesModule.RegisterRoutes(mux)

	// HACCP digital checklist (039) — REST surface + background cron
	tasksModule.RegisterRoutes(mux)
	tasksModule.StartCron(context.Background())

	// ---------------------------------------------------------------------------
	// Middleware chain
	// ---------------------------------------------------------------------------
	// Rate limits:
	//   - 200 req/min per IP for general API traffic
	//   - 10 req/min per IP for auth endpoints (brute-force / credential-stuffing protection)
	rateLimiter := middleware.RateLimit(200, time.Minute)
	authRateLimiter := middleware.RateLimit(10, time.Minute)

	corsMW := middleware.CORS(middleware.CORSConfig{
		AllowedOrigins: cfg.CORSOrigins,
	})
	securityHeadersMW := middleware.SecurityHeaders(!cfg.IsDevelopment())

	// publicAPIPaths lists auth endpoints that do NOT require a Bearer token.
	// Online ordering and health/docs paths are excluded by prefix below.
	publicAPIPaths := map[string]bool{
		"/api/v1/auth/device/register": true,
		"/api/v1/auth/device/token":    true,
		"/api/v1/auth/admin/login":     true,
		"/api/v1/auth/token/refresh":   true,
	}

	authMW := middleware.AuthRequired(authModule.ValidateToken)

	// authGate applies JWT authentication to all /api/v1/* routes except
	// public ones (auth, online ordering, health, docs).
	//
	// Menu version + snapshot paths run their own auth inside the handler
	// (authorizeTenantRead — accepts JWT *or* X-API-Key from a paired POS
	// device). The middleware lets them through without an Authorization
	// header so the X-API-Key path actually reaches the handler.
	authGate := middleware.Middleware(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			path := r.URL.Path
			if !strings.HasPrefix(path, "/api/v1/") ||
				strings.HasPrefix(path, "/api/v1/online/") ||
				strings.HasPrefix(path, "/api/v1/menu/version/") ||
				strings.HasPrefix(path, "/api/v1/menu/snapshot/") ||
				strings.HasPrefix(path, "/api/v1/receipt-templates/sync/") ||
				publicAPIPaths[path] {
				next.ServeHTTP(w, r)
				return
			}
			authMW(next).ServeHTTP(w, r)
		})
	})

	// authEndpointLimiter applies a tighter per-IP rate limit to auth endpoints.
	authEndpointLimiter := middleware.Middleware(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if publicAPIPaths[r.URL.Path] {
				authRateLimiter(next).ServeHTTP(w, r)
				return
			}
			next.ServeHTTP(w, r)
		})
	})

	handler := middleware.Chain(mux,
		middleware.RequestID,
		middleware.Logger,
		middleware.Recover,
		securityHeadersMW,
		corsMW,
		middleware.MaxBodySize,
		authEndpointLimiter,
		rateLimiter,
		authGate,
	)

	// ---------------------------------------------------------------------------
	// HTTP server with production-safe timeouts
	// ---------------------------------------------------------------------------
	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Port),
		Handler:      handler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	go func() {
		slog.Info("server starting", "port", cfg.Port, "env", cfg.Env, "version", version)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	slog.Info("server shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("shutdown error", "error", err)
	}
	slog.Info("server stopped")
}
