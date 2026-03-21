package config

import (
	"log/slog"
	"os"
	"strconv"
	"strings"
	"time"
)

// weakJWTSecret is the placeholder value shipped in .env.example.
// The server will refuse to start in production if this value is in use.
const weakJWTSecret = "change-me-in-production-use-256-bit-random"

// Config holds all server configuration loaded from environment variables.
type Config struct {
	Port        int
	Env         string
	LogLevelStr string
	DatabaseURL string
	JWTSecret   string
	JWTExpiry   time.Duration

	// CORSOrigins is a comma-separated list of allowed CORS origins.
	// Use "*" for development; set to specific origins in production.
	CORSOrigins []string

	// License
	LicenseSigningKey string

	// Fiskaly (Phase 4)
	FiskalyAPIKey    string
	FiskalyAPISecret string
	FiskalyEnv       string

	// ERPNext (Phase 9)
	ERPNextURL       string
	ERPNextAPIKey    string
	ERPNextAPISecret string
}

// Load reads configuration from environment variables with sensible defaults.
func Load() *Config {
	corsRaw := getEnv("CORS_ORIGINS", "*")
	var corsOrigins []string
	for _, o := range strings.Split(corsRaw, ",") {
		if o = strings.TrimSpace(o); o != "" {
			corsOrigins = append(corsOrigins, o)
		}
	}
	if len(corsOrigins) == 0 {
		corsOrigins = []string{"*"}
	}

	cfg := &Config{
		Port:              getEnvInt("PORT", 8080),
		Env:               getEnv("ENV", "development"),
		LogLevelStr:       getEnv("LOG_LEVEL", "debug"),
		DatabaseURL:       getEnv("DATABASE_URL", "postgres://gastrocore:gastrocore@localhost:5432/gastrocore?sslmode=disable"),
		JWTSecret:         getEnv("JWT_SECRET", weakJWTSecret),
		JWTExpiry:         getEnvDuration("JWT_EXPIRY", 24*time.Hour),
		CORSOrigins:       corsOrigins,
		LicenseSigningKey: getEnv("LICENSE_SIGNING_KEY", ""),
		FiskalyAPIKey:     getEnv("FISKALY_API_KEY", ""),
		FiskalyAPISecret:  getEnv("FISKALY_API_SECRET", ""),
		FiskalyEnv:        getEnv("FISKALY_ENV", "test"),
		ERPNextURL:        getEnv("ERPNEXT_URL", ""),
		ERPNextAPIKey:     getEnv("ERPNEXT_API_KEY", ""),
		ERPNextAPISecret:  getEnv("ERPNEXT_API_SECRET", ""),
	}
	return cfg
}

// Validate checks the configuration for security issues.
// Returns true if the server should abort startup (fatal misconfiguration in production).
func (c *Config) Validate() bool {
	fatal := false
	if c.IsDevelopment() {
		return false
	}
	// In production: reject the placeholder JWT secret.
	if c.JWTSecret == weakJWTSecret || len(c.JWTSecret) < 32 {
		slog.Error("SECURITY: JWT_SECRET is unset or too weak — set a random 256-bit secret in production")
		fatal = true
	}
	// In production: warn if CORS is wide open.
	for _, o := range c.CORSOrigins {
		if o == "*" {
			slog.Warn("SECURITY: CORS_ORIGINS is '*' in production — set specific allowed origins")
			break
		}
	}
	// In production: warn if DB uses sslmode=disable.
	if strings.Contains(c.DatabaseURL, "sslmode=disable") {
		slog.Warn("SECURITY: DATABASE_URL uses sslmode=disable — enable TLS in production")
	}
	return fatal
}

// LogLevel returns the slog.Level matching the configured log level string.
func (c *Config) LogLevel() slog.Level {
	switch c.LogLevelStr {
	case "debug":
		return slog.LevelDebug
	case "info":
		return slog.LevelInfo
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

// IsDevelopment returns true if running in development mode.
func (c *Config) IsDevelopment() bool {
	return c.Env == "development"
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return fallback
}

func getEnvDuration(key string, fallback time.Duration) time.Duration {
	if v := os.Getenv(key); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return fallback
}
