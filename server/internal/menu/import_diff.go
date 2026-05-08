package menu

// Diff calculator for magic-link menu import. Pure functions: takes a
// snapshot from Reservation plus the existing external_menu_refs mapping
// rows, produces a per-entity DiffRow indicating NEW / UPDATE / UNCHANGED
// / SKIP. The handler renders this as a JSON preview when ?dryRun=true,
// and import_apply consumes the same struct to drive INSERTs/UPDATEs.

// DiffAction is the verb describing what the import will do for one entity.
type DiffAction string

const (
	DiffNew       DiffAction = "NEW"
	DiffUpdate    DiffAction = "UPDATE"
	DiffUnchanged DiffAction = "UNCHANGED"
	DiffSkip      DiffAction = "SKIP"
	DiffError     DiffAction = "ERROR"
)

// DiffRow describes the planned action for one entity. LocalID is set only
// when an existing row is reused (mapped via external_menu_refs).
type DiffRow struct {
	EntityType string     `json:"entityType"` // category | product | modifier_group | modifier
	Action     DiffAction `json:"action"`
	LocalID    *string    `json:"localId,omitempty"`
	RemoteID   string     `json:"remoteId"`
	Name       string     `json:"name"`
	Reason     string     `json:"reason,omitempty"` // SKIP_MODIFIER_CRUD_MISSING, etc.
}

// ImportSummary is the per-entity-type tally for the response envelope.
type ImportSummary struct {
	CategoriesNew       int `json:"categoriesNew"`
	CategoriesUpdated   int `json:"categoriesUpdated"`
	CategoriesUnchanged int `json:"categoriesUnchanged"`
	ProductsNew         int `json:"productsNew"`
	ProductsUpdated     int `json:"productsUpdated"`
	ProductsUnchanged   int `json:"productsUnchanged"`
	ModifiersSkipped    int `json:"modifiersSkipped"`
	Errors              int `json:"errors"`
}

// ImportPreview is the payload returned for both dryRun=true and after a
// real apply (the apply adds tenantId/syncEventId at the handler level).
type ImportPreview struct {
	Categories []DiffRow     `json:"categories"`
	Products   []DiffRow     `json:"products"`
	Modifiers  []DiffRow     `json:"modifiers"`
	Summary    ImportSummary `json:"summary"`
}

// MappingKey identifies a remote entity in the external_menu_refs table.
// Tenant is implied by the calling context (per-tenant query).
type MappingKey struct {
	EntityType string
	RemoteID   string
}

// existingMapping holds the local UUID for a previously-mapped remote entity
// plus the cached current values used to decide UPDATE vs UNCHANGED. The
// import_apply layer fills these by reading the current Postgres row.
type existingMapping struct {
	LocalID string
	// Snapshot fields used for change detection. For categories: name,
	// sortOrder, isActive. For products: name, descriptionSet, image,
	// priceCents, sortOrder, isActive, categoryLocalID.
	Name           string
	Description    *string
	Image          string
	PriceCents     int64
	SortOrder      int
	IsActive       bool
	CategoryLocal  string
	SelectionType  string
	IsRequired     bool
	MinSelect      int
	MaxSelect      int
	PriceDeltaCent int64
	IsDefault      bool
}

// computeDiff produces the planned diff for a snapshot vs the existing
// mapping table. fallbackBase feeds normalizeImageURL.
//
// `existing` maps {entityType, remoteID} → row values currently in Postgres.
// Apply layer is responsible for populating it. Missing key = NEW.
//
// Modifier groups & options are SKIPped with reason SKIP_MODIFIER_CRUD_MISSING
// because the menu module doesn't expose POST/PUT for those yet (Aşama 2).
func computeDiff(env *snapshotEnvelope, existing map[MappingKey]existingMapping, fallbackBase string) (ImportPreview, error) {
	preview := ImportPreview{
		Categories: []DiffRow{},
		Products:   []DiffRow{},
		Modifiers:  []DiffRow{},
	}

	// ---- Categories ----
	for _, c := range env.Snapshot.Categories {
		row := DiffRow{
			EntityType: "category",
			RemoteID:   c.ID,
			Name:       c.Name,
		}
		key := MappingKey{EntityType: "category", RemoteID: c.ID}
		prev, ok := existing[key]
		if !ok {
			row.Action = DiffNew
			preview.Summary.CategoriesNew++
		} else {
			row.LocalID = &prev.LocalID
			if prev.Name == c.Name && prev.SortOrder == c.SortOrder && prev.IsActive == c.IsActive {
				row.Action = DiffUnchanged
				preview.Summary.CategoriesUnchanged++
			} else {
				row.Action = DiffUpdate
				preview.Summary.CategoriesUpdated++
			}
		}
		preview.Categories = append(preview.Categories, row)
	}

	// ---- Products ----
	for _, it := range env.Snapshot.Items {
		row := DiffRow{
			EntityType: "product",
			RemoteID:   it.ID,
			Name:       it.Name,
		}
		// Compute target values for change-detection.
		priceCents, err := decimalToCents(it.PriceStandard)
		if err != nil {
			row.Action = DiffError
			row.Reason = err.Error()
			preview.Summary.Errors++
			preview.Products = append(preview.Products, row)
			continue
		}
		var imageStr string
		if it.Image != nil {
			imageStr = normalizeImageURL(*it.Image, fallbackBase)
		}
		key := MappingKey{EntityType: "product", RemoteID: it.ID}
		prev, ok := existing[key]
		if !ok {
			row.Action = DiffNew
			preview.Summary.ProductsNew++
			preview.Products = append(preview.Products, row)
			continue
		}
		row.LocalID = &prev.LocalID

		descSnap := ""
		if it.Description != nil {
			descSnap = *it.Description
		}
		descPrev := ""
		if prev.Description != nil {
			descPrev = *prev.Description
		}
		// Category mapping: snapshot CategoryID is the *remote* ID; the
		// resolved local is whatever the category mapping points to. The
		// apply layer will surface a mismatch as a real UPDATE.
		categoryRemote := it.CategoryID
		_ = categoryRemote // documented; resolved at apply-time

		if prev.Name == it.Name &&
			descPrev == descSnap &&
			prev.Image == imageStr &&
			prev.PriceCents == priceCents &&
			prev.SortOrder == it.SortOrder &&
			prev.IsActive == it.IsAvailable {
			row.Action = DiffUnchanged
			preview.Summary.ProductsUnchanged++
		} else {
			row.Action = DiffUpdate
			preview.Summary.ProductsUpdated++
		}
		preview.Products = append(preview.Products, row)
	}

	// ---- Modifier groups + options (read-only, Aşama 2 unblocks writes) ----
	for _, g := range env.Snapshot.ExtraGroups {
		preview.Modifiers = append(preview.Modifiers, DiffRow{
			EntityType: "modifier_group",
			RemoteID:   g.ID,
			Name:       g.Name,
			Action:     DiffSkip,
			Reason:     "SKIP_MODIFIER_CRUD_MISSING",
		})
		preview.Summary.ModifiersSkipped++
	}
	for _, o := range env.Snapshot.ExtraOptions {
		preview.Modifiers = append(preview.Modifiers, DiffRow{
			EntityType: "modifier",
			RemoteID:   o.ID,
			Name:       o.Name,
			Action:     DiffSkip,
			Reason:     "SKIP_MODIFIER_CRUD_MISSING",
		})
		preview.Summary.ModifiersSkipped++
	}

	return preview, nil
}
