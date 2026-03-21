package database

import (
	"context"
	"database/sql"
	"fmt"
)

// ScanRow executes a query expected to return a single row and scans it using
// the provided scan function. Returns sql.ErrNoRows if no row found.
func ScanRow[T any](ctx context.Context, db *sql.DB, query string, args []any, scan func(*sql.Row) (T, error)) (T, error) {
	row := db.QueryRowContext(ctx, query, args...)
	return scan(row)
}

// ScanRows executes a query expected to return multiple rows and scans each
// using the provided scan function.
func ScanRows[T any](ctx context.Context, db *sql.DB, query string, args []any, scan func(*sql.Rows) (T, error)) ([]T, error) {
	rows, err := db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query: %w", err)
	}
	defer rows.Close()

	var results []T
	for rows.Next() {
		item, err := scan(rows)
		if err != nil {
			return nil, fmt.Errorf("scan: %w", err)
		}
		results = append(results, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}
	return results, nil
}

// ExecReturning executes an INSERT/UPDATE with a RETURNING clause and scans
// the returned row.
func ExecReturning[T any](ctx context.Context, db *sql.DB, query string, args []any, scan func(*sql.Row) (T, error)) (T, error) {
	row := db.QueryRowContext(ctx, query, args...)
	return scan(row)
}

// Exec executes a query that doesn't return rows (INSERT, UPDATE, DELETE)
// and returns the number of rows affected.
func Exec(ctx context.Context, db *sql.DB, query string, args ...any) (int64, error) {
	result, err := db.ExecContext(ctx, query, args...)
	if err != nil {
		return 0, fmt.Errorf("exec: %w", err)
	}
	return result.RowsAffected()
}

// InTx executes a function within a database transaction.
// The transaction is committed if fn returns nil, rolled back otherwise.
func InTx(ctx context.Context, db *sql.DB, fn func(tx *sql.Tx) error) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}

	if err := fn(tx); err != nil {
		if rbErr := tx.Rollback(); rbErr != nil {
			return fmt.Errorf("rollback failed: %v (original: %w)", rbErr, err)
		}
		return err
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}
