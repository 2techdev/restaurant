package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"

	_ "github.com/lib/pq"
)

const migrationsDir = "migrations"

func main() {
	if len(os.Args) < 2 {
		log.Fatal("usage: migrate <up|down>")
	}

	direction := os.Args[1]
	if direction != "up" && direction != "down" {
		log.Fatalf("unknown direction: %s (use 'up' or 'down')", direction)
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://gastrocore:gastrocore@localhost:5432/gastrocore?sslmode=disable"
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("failed to open database: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("failed to ping database: %v", err)
	}

	// Ensure migrations tracking table exists
	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version TEXT PRIMARY KEY,
			applied_at TIMESTAMPTZ DEFAULT NOW()
		)
	`)
	if err != nil {
		log.Fatalf("failed to create schema_migrations table: %v", err)
	}

	// Find migration files
	suffix := fmt.Sprintf(".%s.sql", direction)
	files, err := filepath.Glob(filepath.Join(migrationsDir, "*"+suffix))
	if err != nil {
		log.Fatalf("failed to glob migrations: %v", err)
	}

	sort.Strings(files)

	if direction == "down" {
		// Reverse order for down migrations
		for i, j := 0, len(files)-1; i < j; i, j = i+1, j-1 {
			files[i], files[j] = files[j], files[i]
		}
	}

	for _, file := range files {
		base := filepath.Base(file)
		version := strings.Split(base, ".")[0] // e.g., "001_initial"

		if direction == "up" {
			// Check if already applied
			var exists bool
			err := db.QueryRow("SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = $1)", version).Scan(&exists)
			if err != nil {
				log.Fatalf("failed to check migration %s: %v", version, err)
			}
			if exists {
				fmt.Printf("skip %s (already applied)\n", version)
				continue
			}
		}

		content, err := os.ReadFile(file)
		if err != nil {
			log.Fatalf("failed to read %s: %v", file, err)
		}

		tx, err := db.Begin()
		if err != nil {
			log.Fatalf("failed to begin transaction: %v", err)
		}

		if _, err := tx.Exec(string(content)); err != nil {
			tx.Rollback()
			log.Fatalf("failed to execute %s: %v", file, err)
		}

		if direction == "up" {
			if _, err := tx.Exec("INSERT INTO schema_migrations (version) VALUES ($1)", version); err != nil {
				tx.Rollback()
				log.Fatalf("failed to record migration %s: %v", version, err)
			}
		} else {
			if _, err := tx.Exec("DELETE FROM schema_migrations WHERE version = $1", version); err != nil {
				tx.Rollback()
				log.Fatalf("failed to remove migration record %s: %v", version, err)
			}
		}

		if err := tx.Commit(); err != nil {
			log.Fatalf("failed to commit %s: %v", file, err)
		}

		fmt.Printf("applied %s (%s)\n", file, direction)
	}

	fmt.Println("migrations complete")
}
