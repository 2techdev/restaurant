package config

import (
	"log/slog"
	"os"
	"strconv"
	"time"
)

// Config holds all server configuration loaded from environment variables.
type Config struct {
	Port        int
	Env         string
	LogLevelStr string
	DatabaseURL string
	JWTSecret   string
	JWTExpiry   time.Duration

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
	cfg := &Config{
		Port:              getEnvInt("PORT", 8080),
		Env:               getEnv("ENV", "development"),
		LogLevelStr:       getEnv("LOG_LEVEL", "debug"),
		DatabaseURL:       getEnv("DATABASE_URL", "postgres://gastrocore:gastrocore@localhost:5432/gastrocore?sslmode=disable"),
		JWTSecret:         getEnv("JWT_SECRET", "change-me-in-production-use-256-bit-random"),
		JWTExpiry:         getEnvDuration("JWT_EXPIRY", 24*time.Hour),
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
