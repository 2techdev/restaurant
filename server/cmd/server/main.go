package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gastrocore/server/internal/auth"
	"github.com/gastrocore/server/internal/crm"
	"github.com/gastrocore/server/internal/dashboard"
	"github.com/gastrocore/server/internal/devices"
	"github.com/gastrocore/server/internal/docs"
	"github.com/gastrocore/server/internal/fiscal"
	"github.com/gastrocore/server/internal/inventory"
	"github.com/gastrocore/server/internal/kds"
	"github.com/gastrocore/server/internal/license"
	"github.com/gastrocore/server/internal/licenses"
	"github.com/gastrocore/server/internal/menu"
	"github.com/gastrocore/server/internal/online"
	"github.com/gastrocore/server/internal/orders"
	"github.com/gastrocore/server/internal/qrbill"
	"github.com/gastrocore/server/internal/reports"
	"github.com/gastrocore/server/internal/reservations"
	"github.com/gastrocore/server/internal/shared/config"
	"github.com/gastrocore/server/internal/shared/database"
	"github.com/gastrocore/server/internal/shared/middleware"
	"github.com/gastrocore/server/internal/stores"
	gosync "github.com/gastrocore/server/internal/sync"
)

const version = "0.1.0"

func main() {
	// Load config
	cfg := config.Load()

	// Setup structured logging
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: cfg.LogLevel(),
	}))
	slog.SetDefault(logger)

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
	// Initialize modules
	// ---------------------------------------------------------------------------
	authModule := auth.NewModule(db, cfg)
	syncModule := gosync.NewModule(db, cfg)
	menuModule := menu.NewModule(db)
	ordersModule := orders.NewModule(db)
	onlineModule := online.NewModuleWithStripe(db, kdsHub, onlineHub, online.StripeConfig{
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

	// ---------------------------------------------------------------------------
	// Middleware chain
	// ---------------------------------------------------------------------------
	// Rate limits (applied globally; adjust per-environment as needed):
	//   - 200 req/min for most APIs (generous for POS devices on slow networks)
	//   - Public online-ordering endpoints share this limit
	rateLimiter := middleware.RateLimit(200, time.Minute)

	handler := middleware.Chain(mux,
		middleware.RequestID,
		middleware.Logger,
		middleware.Recover,
		middleware.CORS,
		rateLimiter,
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
