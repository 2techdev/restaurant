package sync

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// Store is the persistence interface used by the sync handlers.
// The interface makes it easy to inject mocks in unit tests.
type Store interface {
	SaveEvents(ctx context.Context, events []SyncEvent) error
	FetchEventsSince(ctx context.Context, tenantID, deviceID, cursor string, limit int) ([]SyncEvent, error)
	CountPendingForDevice(ctx context.Context, tenantID, deviceID, cursor string) (int, error)
	UpsertDeviceCursor(ctx context.Context, deviceID, tenantID string, push, pull bool) error
	GetDeviceCursor(ctx context.Context, deviceID, tenantID string) (lastPush, lastPull *time.Time, err error)
}

// sqlStore handles PostgreSQL persistence for sync events.
type sqlStore struct {
	db *sql.DB
}

// Ensure sqlStore implements Store.
var _ Store = (*sqlStore)(nil)

func newStore(db *sql.DB) Store {
	return &sqlStore{db: db}
}

// SaveEvents persists a batch of sync events. Duplicate IDs are silently ignored.
func (s *sqlStore) SaveEvents(ctx context.Context, events []SyncEvent) error {
	if len(events) == 0 {
		return nil
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(ctx, `
		INSERT INTO sync_events (id, tenant_id, device_id, table_name, record_id, operation, payload, created_at, received_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9)
		ON CONFLICT (id) DO NOTHING
	`)
	if err != nil {
		return fmt.Errorf("prepare insert: %w", err)
	}
	defer stmt.Close()

	now := time.Now().UTC()
	for _, e := range events {
		payload := e.Payload
		if len(payload) == 0 {
			payload = []byte("{}")
		}
		if _, err := stmt.ExecContext(ctx,
			e.ID, e.TenantID, e.DeviceID, e.TableName, e.RecordID,
			e.Operation, payload, e.CreatedAt, now,
		); err != nil {
			return fmt.Errorf("insert event %s: %w", e.ID, err)
		}
	}

	return tx.Commit()
}

// FetchEventsSince returns events received after cursor (RFC3339Nano) for tenantID,
// excluding events from deviceID. Returns up to limit events.
func (s *sqlStore) FetchEventsSince(ctx context.Context, tenantID, deviceID, cursor string, limit int) ([]SyncEvent, error) {
	var cursorTime time.Time
	if cursor != "" {
		var err error
		cursorTime, err = time.Parse(time.RFC3339Nano, cursor)
		if err != nil {
			return nil, fmt.Errorf("invalid cursor %q: %w", cursor, err)
		}
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT id, tenant_id, device_id, table_name, record_id, operation, payload, created_at, received_at
		FROM sync_events
		WHERE tenant_id = $1
		  AND device_id != $2
		  AND received_at > $3
		ORDER BY received_at ASC
		LIMIT $4
	`, tenantID, deviceID, cursorTime, limit)
	if err != nil {
		return nil, fmt.Errorf("query events: %w", err)
	}
	defer rows.Close()

	var events []SyncEvent
	for rows.Next() {
		var e SyncEvent
		var payload []byte
		if err := rows.Scan(
			&e.ID, &e.TenantID, &e.DeviceID, &e.TableName, &e.RecordID,
			&e.Operation, &payload, &e.CreatedAt, &e.ReceivedAt,
		); err != nil {
			return nil, fmt.Errorf("scan event: %w", err)
		}
		e.Payload = payload
		events = append(events, e)
	}
	return events, rows.Err()
}

// CountPendingForDevice counts events available for a device to pull since cursor.
func (s *sqlStore) CountPendingForDevice(ctx context.Context, tenantID, deviceID, cursor string) (int, error) {
	var cursorTime time.Time
	if cursor != "" {
		t, err := time.Parse(time.RFC3339Nano, cursor)
		if err == nil {
			cursorTime = t
		}
	}
	var count int
	err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM sync_events
		WHERE tenant_id = $1 AND device_id != $2 AND received_at > $3
	`, tenantID, deviceID, cursorTime).Scan(&count)
	return count, err
}

// UpsertDeviceCursor updates the device's last push/pull timestamps.
// When both push and pull are false the row is created (or left unchanged) —
// used for device registration without touching timestamps.
func (s *sqlStore) UpsertDeviceCursor(ctx context.Context, deviceID, tenantID string, push, pull bool) error {
	if push {
		_, err := s.db.ExecContext(ctx, `
			INSERT INTO sync_device_cursors (device_id, tenant_id, last_push_at, updated_at)
			VALUES ($1, $2, NOW(), NOW())
			ON CONFLICT (device_id, tenant_id) DO UPDATE SET last_push_at = NOW(), updated_at = NOW()
		`, deviceID, tenantID)
		return err
	}
	if pull {
		_, err := s.db.ExecContext(ctx, `
			INSERT INTO sync_device_cursors (device_id, tenant_id, last_pull_at, updated_at)
			VALUES ($1, $2, NOW(), NOW())
			ON CONFLICT (device_id, tenant_id) DO UPDATE SET last_pull_at = NOW(), updated_at = NOW()
		`, deviceID, tenantID)
		return err
	}
	// Register-only: ensure row exists without modifying timestamps.
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO sync_device_cursors (device_id, tenant_id, updated_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (device_id, tenant_id) DO NOTHING
	`, deviceID, tenantID)
	return err
}

// GetDeviceCursor returns the last push/pull timestamps for a device.
func (s *sqlStore) GetDeviceCursor(ctx context.Context, deviceID, tenantID string) (lastPush, lastPull *time.Time, err error) {
	var lp, lpu sql.NullTime
	err = s.db.QueryRowContext(ctx, `
		SELECT last_push_at, last_pull_at FROM sync_device_cursors
		WHERE device_id = $1 AND tenant_id = $2
	`, deviceID, tenantID).Scan(&lp, &lpu)
	if err == sql.ErrNoRows {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, err
	}
	if lp.Valid {
		lastPush = &lp.Time
	}
	if lpu.Valid {
		lastPull = &lpu.Time
	}
	return lastPush, lastPull, nil
}
