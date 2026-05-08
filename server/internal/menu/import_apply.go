package menu

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/gastrocore/server/internal/shared/uuid"
)

// applyResult is what import_apply returns to the handler.
type applyResult struct {
	Preview      ImportPreview
	SyncEventID  string
	Skipped      bool   // true when payload_hash already applied → idempotent replay
	IdempotencyK string // idempotency_key used (returned for caller logging)
}

// loadExistingMapping reads external_menu_refs + the cached current values
// from categories/products. Returns one row per mapped remote entity for the
// given tenant.
//
// Modifier-group/modifier rows are loaded even though Aşama 1 doesn't write
// them — future imports may need to detect changes once CRUD is added.
func loadExistingMapping(ctx context.Context, tx *sql.Tx, tenantID string) (map[MappingKey]existingMapping, error) {
	out := make(map[MappingKey]existingMapping, 64)

	// Categories: join external_menu_refs (entity_type='category') to categories.
	rows, err := tx.QueryContext(ctx, `
		SELECT r.entity_type, r.remote_id, r.local_id::text,
		       COALESCE(c.name,''), COALESCE(c.display_order,0), COALESCE(c.is_active,FALSE)
		FROM external_menu_refs r
		LEFT JOIN categories c ON c.id = r.local_id AND c.tenant_id = r.tenant_id AND c.is_deleted=FALSE
		WHERE r.tenant_id=$1 AND r.entity_type='category' AND r.remote_system='gastrohub'
	`, tenantID)
	if err != nil {
		return nil, fmt.Errorf("loadExistingMapping(categories): %w", err)
	}
	for rows.Next() {
		var et, rid, lid, name string
		var sortOrder int
		var active bool
		if err := rows.Scan(&et, &rid, &lid, &name, &sortOrder, &active); err != nil {
			rows.Close()
			return nil, err
		}
		out[MappingKey{EntityType: et, RemoteID: rid}] = existingMapping{
			LocalID:   lid,
			Name:      name,
			SortOrder: sortOrder,
			IsActive:  active,
		}
	}
	rows.Close()

	// Products.
	rows, err = tx.QueryContext(ctx, `
		SELECT r.entity_type, r.remote_id, r.local_id::text,
		       COALESCE(p.name,''),
		       p.description,
		       COALESCE(p.image_path,''),
		       COALESCE(p.price,0),
		       COALESCE(p.display_order,0),
		       COALESCE(p.is_active,FALSE),
		       COALESCE(p.category_id::text,'')
		FROM external_menu_refs r
		LEFT JOIN products p ON p.id = r.local_id AND p.tenant_id = r.tenant_id AND p.is_deleted=FALSE
		WHERE r.tenant_id=$1 AND r.entity_type='product' AND r.remote_system='gastrohub'
	`, tenantID)
	if err != nil {
		return nil, fmt.Errorf("loadExistingMapping(products): %w", err)
	}
	for rows.Next() {
		var et, rid, lid, name, image, catLocal string
		var desc sql.NullString
		var price int64
		var sortOrder int
		var active bool
		if err := rows.Scan(&et, &rid, &lid, &name, &desc, &image, &price, &sortOrder, &active, &catLocal); err != nil {
			rows.Close()
			return nil, err
		}
		var descPtr *string
		if desc.Valid && desc.String != "" {
			s := desc.String
			descPtr = &s
		}
		out[MappingKey{EntityType: et, RemoteID: rid}] = existingMapping{
			LocalID:       lid,
			Name:          name,
			Description:   descPtr,
			Image:         image,
			PriceCents:    price,
			SortOrder:     sortOrder,
			IsActive:      active,
			CategoryLocal: catLocal,
		}
	}
	rows.Close()

	return out, nil
}

// applyImport runs the full transaction:
//   1. Read existing mapping
//   2. Compute diff
//   3. Upsert categories
//   4. Upsert products (resolving snapshot CategoryID → local UUID)
//   5. Record external_menu_refs rows
//   6. Insert menu_sync_events row (idempotent on payload_hash)
//
// dryRun=true short-circuits after diff (no writes, no sync_events row).
//
// fallbackBase is the URL prefix used for relative image paths.
func (m *Module) applyImport(
	ctx context.Context,
	tenantID, token string,
	env *snapshotEnvelope,
	mode string, // "merge" | "replace" — currently only "merge" implemented
	dryRun bool,
	fallbackBase string,
) (*applyResult, error) {
	if mode == "" {
		mode = "merge"
	}
	if mode != "merge" {
		// Aşama 1 only supports merge. "replace" returns a 400 in the handler.
		return nil, fmt.Errorf("applyImport: unsupported mode %q", mode)
	}

	// idempotency_key is stable for (tenant, token, snapshot.generatedAt).
	// payload_hash is sha256(canonical JSON of snapshot) — identical
	// snapshots short-circuit even if generatedAt differs.
	payloadJSON, err := json.Marshal(env)
	if err != nil {
		return nil, fmt.Errorf("applyImport: marshal payload: %w", err)
	}
	hash := sha256.Sum256(payloadJSON)
	payloadHash := hex.EncodeToString(hash[:])

	idemKey := fmt.Sprintf("import:%s:%s:%s", tenantID, token, env.GeneratedAt)

	tx, err := m.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("applyImport: begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	// Idempotency check — same payload_hash already applied → skip.
	if !dryRun {
		var existingStatus string
		var existingID string
		err = tx.QueryRowContext(ctx, `
			SELECT id::text, status FROM menu_sync_events
			WHERE tenant_id=$1 AND payload_hash=$2 AND status='applied'
			ORDER BY created_at DESC LIMIT 1
		`, tenantID, payloadHash).Scan(&existingID, &existingStatus)
		if err == nil && existingStatus == "applied" {
			// Already applied — return previously-computed preview by recomputing.
			mapping, err := loadExistingMapping(ctx, tx, tenantID)
			if err != nil {
				return nil, err
			}
			preview, _ := computeDiff(env, mapping, fallbackBase)
			return &applyResult{
				Preview:      preview,
				SyncEventID:  existingID,
				Skipped:      true,
				IdempotencyK: idemKey,
			}, nil
		}
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("applyImport: idem check: %w", err)
		}
	}

	mapping, err := loadExistingMapping(ctx, tx, tenantID)
	if err != nil {
		return nil, err
	}

	preview, err := computeDiff(env, mapping, fallbackBase)
	if err != nil {
		return nil, err
	}

	if dryRun {
		// No writes, no commit needed. Return preview as-is.
		return &applyResult{
			Preview:      preview,
			IdempotencyK: idemKey,
		}, nil
	}

	now := time.Now().UTC()
	// Track remote→local for products (which need a category lookup post-upsert).
	categoryRemoteToLocal := make(map[string]string, len(env.Snapshot.Categories))

	// ---- Apply categories ----
	for _, c := range env.Snapshot.Categories {
		key := MappingKey{EntityType: "category", RemoteID: c.ID}
		prev, ok := mapping[key]
		var localID string
		if ok && prev.LocalID != "" {
			localID = prev.LocalID
			if _, err := tx.ExecContext(ctx, `
				UPDATE categories
				SET name=$1, name_translations=$2::jsonb, display_order=$3,
				    is_active=$4, updated_at=NOW()
				WHERE id=$5 AND tenant_id=$6 AND is_deleted=FALSE
			`, c.Name, nameToTranslations(c.Name), c.SortOrder, c.IsActive, localID, tenantID); err != nil {
				return nil, fmt.Errorf("applyImport: update category %s: %w", c.ID, err)
			}
		} else {
			localID = uuid.New()
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO categories (
					id, tenant_id, name, name_translations, display_order,
					is_active, created_at, updated_at, sync_status, is_deleted
				) VALUES ($1,$2,$3,$4::jsonb,$5,$6,$7,$7,0,FALSE)
			`, localID, tenantID, c.Name, nameToTranslations(c.Name), c.SortOrder, c.IsActive, now); err != nil {
				return nil, fmt.Errorf("applyImport: insert category %s: %w", c.ID, err)
			}
		}
		categoryRemoteToLocal[c.ID] = localID

		if err := upsertExternalRef(ctx, tx, tenantID, "category", localID, c.ID, now); err != nil {
			return nil, err
		}
	}

	// ---- Apply products ----
	for _, it := range env.Snapshot.Items {
		categoryLocal, ok := categoryRemoteToLocal[it.CategoryID]
		if !ok {
			// Snapshot already passed validateSnapshot, so missing means a race
			// between sync and category-rename. Fail the txn.
			return nil, fmt.Errorf("applyImport: item %q has unmapped category %q", it.Name, it.CategoryID)
		}
		priceCents, err := decimalToCents(it.PriceStandard)
		if err != nil {
			return nil, fmt.Errorf("applyImport: price for %q: %w", it.Name, err)
		}
		var imageStr string
		if it.Image != nil {
			imageStr = normalizeImageURL(*it.Image, fallbackBase)
		}
		var descPtr interface{}
		if it.Description != nil && *it.Description != "" {
			descPtr = *it.Description
		}

		key := MappingKey{EntityType: "product", RemoteID: it.ID}
		prev, ok := mapping[key]
		var localID string
		if ok && prev.LocalID != "" {
			localID = prev.LocalID
			if _, err := tx.ExecContext(ctx, `
				UPDATE products
				SET name=$1, name_translations=$2::jsonb,
				    description=$3, description_translations=$4::jsonb,
				    price=$5, image_path=$6, is_active=$7, display_order=$8,
				    category_id=$9::uuid, updated_at=NOW()
				WHERE id=$10 AND tenant_id=$11 AND is_deleted=FALSE
			`, it.Name, nameToTranslations(it.Name),
				descPtr, descriptionToTranslations(descPtr),
				priceCents, nullIfEmpty(imageStr),
				it.IsAvailable, it.SortOrder,
				categoryLocal, localID, tenantID); err != nil {
				return nil, fmt.Errorf("applyImport: update product %s: %w", it.ID, err)
			}
		} else {
			localID = uuid.New()
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO products (
					id, tenant_id, category_id, name, name_translations,
					description, description_translations,
					price, cost_price, tax_group, image_path, is_active,
					display_order, printer_group, created_at, updated_at,
					sync_status, is_deleted
				) VALUES (
					$1, $2, $3::uuid, $4, $5::jsonb,
					$6, $7::jsonb,
					$8, 0, 'default', $9, $10,
					$11, 'kitchen', $12, $12,
					0, FALSE
				)
			`, localID, tenantID, categoryLocal, it.Name, nameToTranslations(it.Name),
				descPtr, descriptionToTranslations(descPtr),
				priceCents, nullIfEmpty(imageStr),
				it.IsAvailable, it.SortOrder, now); err != nil {
				return nil, fmt.Errorf("applyImport: insert product %s: %w", it.ID, err)
			}
		}

		if err := upsertExternalRef(ctx, tx, tenantID, "product", localID, it.ID, now); err != nil {
			return nil, err
		}
	}

	// ---- Record sync event ----
	syncEventID := uuid.New()
	previewJSON, _ := json.Marshal(preview)
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO menu_sync_events (
			id, tenant_id, direction, event_type,
			idempotency_key, payload_hash, payload, status, created_at, applied_at
		) VALUES ($1, $2, 'gastrohub_to_pos', 'initial_import',
		          $3, $4, $5::jsonb, 'applied', NOW(), NOW())
	`, syncEventID, tenantID, idemKey, payloadHash, previewJSON); err != nil {
		return nil, fmt.Errorf("applyImport: record sync event: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("applyImport: commit: %w", err)
	}

	return &applyResult{
		Preview:      preview,
		SyncEventID:  syncEventID,
		Skipped:      false,
		IdempotencyK: idemKey,
	}, nil
}

// upsertExternalRef inserts or updates the external_menu_refs row that
// links a local UUID to a remote (gastrohub) ID. The unique constraint on
// (tenant_id, entity_type, local_id, remote_system) makes ON CONFLICT
// the right approach.
func upsertExternalRef(ctx context.Context, tx *sql.Tx, tenantID, entityType, localID, remoteID string, now time.Time) error {
	_, err := tx.ExecContext(ctx, `
		INSERT INTO external_menu_refs (
			tenant_id, entity_type, local_id, remote_system, remote_id,
			last_synced_at, last_sync_from, created_at, updated_at
		) VALUES ($1, $2, $3::uuid, 'gastrohub', $4, $5, 'gastrohub_to_pos', $5, $5)
		ON CONFLICT (tenant_id, entity_type, local_id, remote_system)
		DO UPDATE SET remote_id=EXCLUDED.remote_id,
		              last_synced_at=EXCLUDED.last_synced_at,
		              last_sync_from='gastrohub_to_pos',
		              updated_at=EXCLUDED.updated_at
	`, tenantID, entityType, localID, remoteID, now)
	if err != nil {
		return fmt.Errorf("upsertExternalRef(%s/%s): %w", entityType, remoteID, err)
	}
	return nil
}

// descriptionToTranslations wraps a description string-or-nil into JSONB.
// `descPtr` is the same interface{} value used by the SQL exec — handle
// the typed nil that nullableString returns.
func descriptionToTranslations(descPtr interface{}) []byte {
	switch v := descPtr.(type) {
	case nil:
		return []byte("{}")
	case string:
		return nameToTranslations(v)
	default:
		return []byte("{}")
	}
}

// nullIfEmpty returns nil for an empty string so the column stores NULL
// (image_path is nullable; empty strings would slip through CHECK-less
// columns and confuse downstream consumers).
func nullIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}
