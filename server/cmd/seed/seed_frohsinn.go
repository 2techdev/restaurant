// seed_frohsinn.go — Restaurant Pizzeria Frohsinn, Bubendorf seed data.
//
// Real Swiss restaurant at Hauptstrasse 35, 4416 Bubendorf.
// Menu scraped from their live online ordering page (order.2pos.ch).
// Swiss tax rules apply: dine-in 8.1%, takeaway food 2.6%, alcohol 8.1%.
//
// Online ordering public menu: GET /api/v1/online/menu/ff000000-0000-0000-0000-000000000001
//
// Fixed UUID namespace: ff000000-…  (never reused for other tenants)
package main

import (
	"database/sql"
	"fmt"
	"time"
)

// ---------------------------------------------------------------------------
// Fixed UUIDs — Frohsinn Bubendorf
// ---------------------------------------------------------------------------

const (
	frohsinnTenantID = "ff000000-0000-0000-0000-000000000001"

	// Staff
	frohsinnAdminID   = "ff000000-0001-0000-0000-000000000001"
	frohsinnManagerID = "ff000000-0001-0000-0000-000000000002"
	frohsinnWaiter1ID = "ff000000-0001-0000-0000-000000000003"
	frohsinnWaiter2ID = "ff000000-0001-0000-0000-000000000004"
	frohsinnKitchenID = "ff000000-0001-0000-0000-000000000005"

	// Categories (18)
	frohsinnCatSuppen         = "ff000000-0002-0000-0000-000000000001"
	frohsinnCatSalateVorsp    = "ff000000-0002-0000-0000-000000000002"
	frohsinnCatPasta          = "ff000000-0002-0000-0000-000000000003"
	frohsinnCatVegPizza       = "ff000000-0002-0000-0000-000000000004"
	frohsinnCatPizzaFleisch   = "ff000000-0002-0000-0000-000000000005"
	frohsinnCatPizzaFisch     = "ff000000-0002-0000-0000-000000000006"
	frohsinnCatRisotto        = "ff000000-0002-0000-0000-000000000007"
	frohsinnCatPoulet         = "ff000000-0002-0000-0000-000000000008"
	frohsinnCatSchwein        = "ff000000-0002-0000-0000-000000000009"
	frohsinnCatKalb           = "ff000000-0002-0000-0000-000000000010"
	frohsinnCatRind           = "ff000000-0002-0000-0000-000000000011"
	frohsinnCatFisch          = "ff000000-0002-0000-0000-000000000012"
	frohsinnCatCordonBleu     = "ff000000-0002-0000-0000-000000000013"
	frohsinnCatKinder         = "ff000000-0002-0000-0000-000000000014"
	frohsinnCatDessert        = "ff000000-0002-0000-0000-000000000015"
	frohsinnCatKaffee         = "ff000000-0002-0000-0000-000000000016"
	frohsinnCatGetraenke      = "ff000000-0002-0000-0000-000000000017"
	frohsinnCatAperitif       = "ff000000-0002-0000-0000-000000000018"

	// Floors
	frohsinnFloorSaal    = "ff000000-0005-0000-0000-000000000001"
	frohsinnFloorTerrasse = "ff000000-0005-0000-0000-000000000002"

	// Demo orders
	frohsinnTicket1ID = "ff000000-0007-0000-0000-000000000001"
	frohsinnTicket2ID = "ff000000-0007-0000-0000-000000000002"
	frohsinnBill1ID   = "ff000000-0008-0000-0000-000000000001"
	frohsinnBill2ID   = "ff000000-0008-0000-0000-000000000002"
)

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

func seedFrohsinnAll(tx *sql.Tx, now time.Time) error {
	steps := []func(*sql.Tx, time.Time) error{
		seedFrohsinnTenant,
		seedFrohsinnUsers,
		seedFrohsinnCategories,
		seedFrohsinnProducts,
		seedFrohsinnFloors,
		seedFrohsinnTables,
		seedFrohsinnTaxProfiles,
		seedFrohsinnDemoOrders,
	}
	for _, fn := range steps {
		if err := fn(tx, now); err != nil {
			return fmt.Errorf("frohsinn: %w", err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Tenant
// ---------------------------------------------------------------------------

func seedFrohsinnTenant(tx *sql.Tx, now time.Time) error {
	return exec(tx, `
		INSERT INTO tenants (id, name, address, phone, default_tax_rate, currency_code, country_code,
		                     description, is_open, is_deleted, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,true,false,$9,$10)
		ON CONFLICT (id) DO NOTHING`,
		frohsinnTenantID,
		"Restaurant Pizzeria Frohsinn",
		"Hauptstrasse 35, 4416 Bubendorf",
		"+41 61 461 68 68",
		8.1,
		"CHF",
		"CH",
		"Schweizer Restaurant und Pizzeria in Bubendorf. Pizza, Pasta, Fleisch- und Fischspezialitäten. Mo–Fr 10–14 Uhr und 16:30–23 Uhr, Sa 16:30–23 Uhr.",
		now, now,
	)
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

func seedFrohsinnUsers(tx *sql.Tx, now time.Time) error {
	users := []struct {
		id, name, pin, role string
	}{
		{frohsinnAdminID, "Admin Frohsinn", "0000", "admin"},
		{frohsinnManagerID, "Manager", "1234", "manager"},
		{frohsinnWaiter1ID, "Service 1", "1111", "waiter"},
		{frohsinnWaiter2ID, "Service 2", "2222", "waiter"},
		{frohsinnKitchenID, "Küche", "3333", "kitchen"},
	}
	for _, u := range users {
		if err := exec(tx, `
			INSERT INTO users (id, tenant_id, name, pin_hash, role, is_active, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,true,$6,$7,0,false)
			ON CONFLICT (id) DO NOTHING`,
			u.id, frohsinnTenantID, u.name, hashPin(u.pin), u.role, now, now,
		); err != nil {
			return fmt.Errorf("user %s: %w", u.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Categories (18)
// ---------------------------------------------------------------------------

func seedFrohsinnCategories(tx *sql.Tx, now time.Time) error {
	cats := []struct {
		id, name, icon, color string
		order                 int
	}{
		{frohsinnCatSuppen, "Suppen", "🍲", "#FF6B35", 0},
		{frohsinnCatSalateVorsp, "Salate & Vorspeisen", "🥗", "#34C759", 1},
		{frohsinnCatPasta, "Pasta", "🍝", "#FF9500", 2},
		{frohsinnCatVegPizza, "Vegetarische Pizzen", "🌿", "#30D158", 3},
		{frohsinnCatPizzaFleisch, "Pizzen mit Fleisch", "🍕", "#FF3B30", 4},
		{frohsinnCatPizzaFisch, "Pizzen mit Fisch", "🐟", "#4F8CFF", 5},
		{frohsinnCatRisotto, "Risotto", "🍚", "#FFD60A", 6},
		{frohsinnCatPoulet, "Pouletfleisch", "🍗", "#FF9F0A", 7},
		{frohsinnCatSchwein, "Schweinefleisch", "🥩", "#FF6B35", 8},
		{frohsinnCatKalb, "Kalbfleisch", "🍖", "#FF3A30", 9},
		{frohsinnCatRind, "Rindfleisch", "🥩", "#8E2424", 10},
		{frohsinnCatFisch, "Fisch", "🐠", "#007AFF", 11},
		{frohsinnCatCordonBleu, "Cordon Bleu", "🧀", "#FFCC00", 12},
		{frohsinnCatKinder, "Kindermenü", "⭐", "#FF6B35", 13},
		{frohsinnCatDessert, "Dessert & Glacé", "🍨", "#FF375F", 14},
		{frohsinnCatKaffee, "Kaffee & Tee", "☕", "#A2845E", 15},
		{frohsinnCatGetraenke, "Getränke & Bier", "🥤", "#4F8CFF", 16},
		{frohsinnCatAperitif, "Aperitif & Spirituosen", "🍹", "#AF52DE", 17},
	}
	for _, c := range cats {
		if err := exec(tx, `
			INSERT INTO categories (id, tenant_id, name, icon, color, display_order, is_active, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,true,$7,$8,0,false)
			ON CONFLICT (id) DO NOTHING`,
			c.id, frohsinnTenantID, c.name, c.icon, c.color, c.order, now, now,
		); err != nil {
			return fmt.Errorf("category %s: %w", c.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Products — full menu (141 items)
// ---------------------------------------------------------------------------

func seedFrohsinnProducts(tx *sql.Tx, now time.Time) error {
	type product struct {
		id, catID, name, desc, taxGroup, printer string
		price, prep                              int
	}

	products := []product{
		// ── SUPPEN ─────────────────────────────────────────────────────────
		{"ff000000-0003-0001-0000-000000000001", frohsinnCatSuppen,
			"Tagessuppe", "Suppe des Tages", "food", "kitchen", 750, 5},
		{"ff000000-0003-0001-0000-000000000002", frohsinnCatSuppen,
			"Tomatencremessuppe", "Cremige Tomatensauce mit Croutons", "food", "kitchen", 1050, 8},
		{"ff000000-0003-0001-0000-000000000003", frohsinnCatSuppen,
			"Bouillon mit Ei", "Klare Bouillon mit verlorenen Ei", "food", "kitchen", 1050, 5},
		{"ff000000-0003-0001-0000-000000000004", frohsinnCatSuppen,
			"Bouillon mit Mark", "Klare Bouillon mit Markklösschen", "food", "kitchen", 1050, 5},

		// ── SALATE & VORSPEISEN ────────────────────────────────────────────
		{"ff000000-0003-0002-0000-000000000001", frohsinnCatSalateVorsp,
			"Grüner Salat", "Frischer grüner Salat", "food", "cold", 1050, 4},
		{"ff000000-0003-0002-0000-000000000002", frohsinnCatSalateVorsp,
			"Gemischter Salat", "Bunt gemischter Salat der Saison", "food", "cold", 1250, 4},
		{"ff000000-0003-0002-0000-000000000003", frohsinnCatSalateVorsp,
			"Nüsslisalat mit Ei", "Feldsalat mit hartgekochtem Ei", "food", "cold", 1250, 4},
		{"ff000000-0003-0002-0000-000000000004", frohsinnCatSalateVorsp,
			"Nüsslisalat mit Ei und Speck", "Feldsalat, Ei, knuspriger Speck", "food", "cold", 1550, 4},
		{"ff000000-0003-0002-0000-000000000005", frohsinnCatSalateVorsp,
			"Rucola Salat", "Rucola, Parmesan, Balsamico, Olivenöl", "food", "cold", 1250, 4},
		{"ff000000-0003-0002-0000-000000000006", frohsinnCatSalateVorsp,
			"Caprese", "Tomaten, Mozzarella, Basilikum, Olivenöl", "food", "cold", 1250, 4},
		{"ff000000-0003-0002-0000-000000000007", frohsinnCatSalateVorsp,
			"Bruschetta", "Tomaten, Zwiebeln, Knoblauch, Olivenöl auf geröstetem Brot", "food", "cold", 1250, 5},
		{"ff000000-0003-0002-0000-000000000008", frohsinnCatSalateVorsp,
			"Crevetten Cocktail", "Mit Toastbrot und Butter", "food", "cold", 1750, 6},
		{"ff000000-0003-0002-0000-000000000009", frohsinnCatSalateVorsp,
			"Carpaccio", "Rucola, Parmesan – kleine Portion", "food", "cold", 2050, 5},
		{"ff000000-0003-0002-0000-000000000010", frohsinnCatSalateVorsp,
			"Vitello Tonnato", "Thunfisch-Créma, Kapern, Sardellen – kleine Portion", "food", "cold", 2050, 5},
		{"ff000000-0003-0002-0000-000000000011", frohsinnCatSalateVorsp,
			"Salatteller", "Grosser gemischter Salatteller", "food", "cold", 2050, 4},
		{"ff000000-0003-0002-0000-000000000012", frohsinnCatSalateVorsp,
			"Wurstsalat garniert", "Mit Pommes Frites", "food", "cold", 2150, 6},

		// ── PASTA ───────────────────────────────────────────────────────────
		{"ff000000-0003-0003-0000-000000000001", frohsinnCatPasta,
			"Pasta Napoli", "Tomatensauce", "food", "kitchen", 2050, 12},
		{"ff000000-0003-0003-0000-000000000002", frohsinnCatPasta,
			"Pasta Aglio Olio", "Aglio, Olio e Peperoncino", "food", "kitchen", 2150, 12},
		{"ff000000-0003-0003-0000-000000000003", frohsinnCatPasta,
			"Pasta Bolognese", "Tomaten-Rindshackfleischsauce", "food", "kitchen", 2350, 14},
		{"ff000000-0003-0003-0000-000000000004", frohsinnCatPasta,
			"Pasta Pesto", "Basilikum-Rahmsauce", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0003-0000-000000000005", frohsinnCatPasta,
			"Pasta Amatriciana", "Zwiebeln, Knoblauch, Speck, Peperoncini, Tomatensauce", "food", "kitchen", 2350, 14},
		{"ff000000-0003-0003-0000-000000000006", frohsinnCatPasta,
			"Pasta Carbonara", "Speck, Rahm, Ei, Parmesan", "food", "kitchen", 2350, 14},
		{"ff000000-0003-0003-0000-000000000007", frohsinnCatPasta,
			"Pasta Arrabbiata", "Scharfe Tomatensauce, Peperoncini", "food", "kitchen", 2250, 12},
		{"ff000000-0003-0003-0000-000000000008", frohsinnCatPasta,
			"Pasta Frutti di Mare", "Meeresfrüchte", "food", "kitchen", 2650, 16},
		{"ff000000-0003-0003-0000-000000000009", frohsinnCatPasta,
			"Pasta Bianca", "Kalbfleisch, Zwiebeln, Knoblauch, Tomaten-Curry-Rahmsauce", "food", "kitchen", 2850, 16},
		{"ff000000-0003-0003-0000-000000000010", frohsinnCatPasta,
			"Pasta Pollo Con Aglio", "Pouletstreifen, Knoblauch, Petersilie, Peperoni", "food", "kitchen", 2850, 16},
		{"ff000000-0003-0003-0000-000000000011", frohsinnCatPasta,
			"Pasta Gamberoni", "Riesencrevetten, Zwiebeln, Knoblauch, Tomatensauce", "food", "kitchen", 2650, 16},
		{"ff000000-0003-0003-0000-000000000012", frohsinnCatPasta,
			"Pasta Porcini", "Steinpilze an Rahmsauce", "food", "kitchen", 2550, 14},
		{"ff000000-0003-0003-0000-000000000013", frohsinnCatPasta,
			"Pasta Gorgonzola", "Gorgonzolasauce", "food", "kitchen", 2450, 12},
		{"ff000000-0003-0003-0000-000000000014", frohsinnCatPasta,
			"Pasta Fattoria", "Champignons, Peperoni, Zwiebeln, Tomatenrahmsauce", "food", "kitchen", 2350, 14},
		{"ff000000-0003-0003-0000-000000000015", frohsinnCatPasta,
			"Pasta Siciliana", "Rindfleisch, Zwiebeln, Knoblauch, Peperoncini, Tomatensauce", "food", "kitchen", 2850, 16},
		{"ff000000-0003-0003-0000-000000000016", frohsinnCatPasta,
			"Pasta A La Maison", "Schinken, Zwiebeln, Parmesan, Rahmsauce", "food", "kitchen", 2550, 14},
		{"ff000000-0003-0003-0000-000000000017", frohsinnCatPasta,
			"Lasagne", "Bolognese-Béchamelsauce, mit Mozzarella gratiniert", "food", "kitchen", 2450, 18},
		{"ff000000-0003-0003-0000-000000000018", frohsinnCatPasta,
			"Cannelloni", "Ricotta-Spinatfüllung, Tomatenrahmsauce, mit Mozzarella gratiniert", "food", "kitchen", 2450, 18},

		// ── VEGETARISCHE PIZZEN ─────────────────────────────────────────────
		{"ff000000-0003-0004-0000-000000000001", frohsinnCatVegPizza,
			"Pizza Margherita", "Tomatensauce, Mozzarella", "food", "kitchen", 1850, 12},
		{"ff000000-0003-0004-0000-000000000002", frohsinnCatVegPizza,
			"Pizza Funghi", "Frische Pilze", "food", "kitchen", 2050, 12},
		{"ff000000-0003-0004-0000-000000000003", frohsinnCatVegPizza,
			"Pizza Gorgonzola", "Gorgonzola, Mozzarella", "food", "kitchen", 2250, 12},
		{"ff000000-0003-0004-0000-000000000004", frohsinnCatVegPizza,
			"Pizza Fiorentina", "Pilze, Spinat, Knoblauch, Ei", "food", "kitchen", 2450, 12},
		{"ff000000-0003-0004-0000-000000000005", frohsinnCatVegPizza,
			"Pizza Mamma Mia", "Saisongemüse, frische Pilze", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0004-0000-000000000006", frohsinnCatVegPizza,
			"Pizza Quattro Formaggi", "4 verschiedene Käsesorten", "food", "kitchen", 2550, 12},
		{"ff000000-0003-0004-0000-000000000007", frohsinnCatVegPizza,
			"Pizza Funghi Porcini", "Steinpilze, Knoblauch", "food", "kitchen", 2550, 12},

		// ── PIZZEN MIT FLEISCH ──────────────────────────────────────────────
		{"ff000000-0003-0005-0000-000000000001", frohsinnCatPizzaFleisch,
			"Pizza Salame", "Salami", "food", "kitchen", 2250, 12},
		{"ff000000-0003-0005-0000-000000000002", frohsinnCatPizzaFleisch,
			"Pizza Prosciutto", "Schinken", "food", "kitchen", 2250, 12},
		{"ff000000-0003-0005-0000-000000000003", frohsinnCatPizzaFleisch,
			"Pizza Calabrese", "Scharfe Salami, Oliven", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0005-0000-000000000004", frohsinnCatPizzaFleisch,
			"Pizza Hawaii", "Schinken, Ananas", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0005-0000-000000000005", frohsinnCatPizzaFleisch,
			"Pizza Prosciutto e Funghi", "Schinken, frische Pilze", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0005-0000-000000000006", frohsinnCatPizzaFleisch,
			"Pizza Quattro Stagioni", "Schinken, Salami, Champignons, Oliven", "food", "kitchen", 2450, 12},
		{"ff000000-0003-0005-0000-000000000007", frohsinnCatPizzaFleisch,
			"Pizza Rustica", "Speck, Zwiebeln, Peperoni", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0005-0000-000000000008", frohsinnCatPizzaFleisch,
			"Pizza Muttenz", "Schinken, Gorgonzola", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0005-0000-000000000009", frohsinnCatPizzaFleisch,
			"Pizza Carbonara", "Speck, Ei, Zwiebeln", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0005-0000-000000000010", frohsinnCatPizzaFleisch,
			"Pizza Svizzera", "Schinken, Speck, scharfe Salami, Oliven", "food", "kitchen", 2550, 12},
		{"ff000000-0003-0005-0000-000000000011", frohsinnCatPizzaFleisch,
			"Pizza Diavola", "Scharfe Salami, Knoblauch", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0005-0000-000000000012", frohsinnCatPizzaFleisch,
			"Pizza Calzone", "Schinken, frische Pilze, Ei – gefaltet", "food", "kitchen", 2350, 14},
		{"ff000000-0003-0005-0000-000000000013", frohsinnCatPizzaFleisch,
			"Pizza Crudo", "Parmaschinken, Rucola, Parmesan", "food", "kitchen", 2650, 12},
		{"ff000000-0003-0005-0000-000000000014", frohsinnCatPizzaFleisch,
			"Pizza Bufala Con Parma", "Frische Tomaten, Büffelmozzarella, Parmaschinken", "food", "kitchen", 2650, 12},
		{"ff000000-0003-0005-0000-000000000015", frohsinnCatPizzaFleisch,
			"Pizza Onur", "Kalbfleisch, Zwiebeln, Knoblauch, Peperoncini", "food", "kitchen", 2850, 14},
		{"ff000000-0003-0005-0000-000000000016", frohsinnCatPizzaFleisch,
			"Pizza Exotica", "Pouletstreifen, Curry, Ananas", "food", "kitchen", 2650, 12},
		{"ff000000-0003-0005-0000-000000000017", frohsinnCatPizzaFleisch,
			"Pizza Bianca", "Lammgeschnetzeltes, Knoblauch, Rucola, Parmesan", "food", "kitchen", 2850, 14},

		// ── PIZZEN MIT FISCH ────────────────────────────────────────────────
		{"ff000000-0003-0006-0000-000000000001", frohsinnCatPizzaFisch,
			"Pizza Napoletana", "Sardellen, Kapern, Oliven", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0006-0000-000000000002", frohsinnCatPizzaFisch,
			"Pizza Tonno e Cipolle", "Thon, Zwiebeln", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0006-0000-000000000003", frohsinnCatPizzaFisch,
			"Pizza Gamberetti", "Crevetten, Knoblauch", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0006-0000-000000000004", frohsinnCatPizzaFisch,
			"Pizza Frutti di Mare", "Meeresfrüchte, Kapern", "food", "kitchen", 2350, 12},
		{"ff000000-0003-0006-0000-000000000005", frohsinnCatPizzaFisch,
			"Pizza Salmone", "Lachs, Zwiebeln, Kapern", "food", "kitchen", 2450, 12},
		{"ff000000-0003-0006-0000-000000000006", frohsinnCatPizzaFisch,
			"Pizza Yannick", "Thon, Zwiebeln, Kapern", "food", "kitchen", 2450, 12},
		{"ff000000-0003-0006-0000-000000000007", frohsinnCatPizzaFisch,
			"Pizza Miran", "Riesencrevetten, Rucola, Knoblauch", "food", "kitchen", 2850, 14},

		// ── RISOTTO ─────────────────────────────────────────────────────────
		{"ff000000-0003-0007-0000-000000000001", frohsinnCatRisotto,
			"Risotto Porcini", "Mit Steinpilzen", "food", "kitchen", 2550, 16},
		{"ff000000-0003-0007-0000-000000000002", frohsinnCatRisotto,
			"Risotto con Gamberetti", "Mit Crevetten", "food", "kitchen", 2650, 16},
		{"ff000000-0003-0007-0000-000000000003", frohsinnCatRisotto,
			"Risotto Milanese", "Kalbfleisch, Speck, Zwiebeln, Knoblauch, Parmesan, Safran", "food", "kitchen", 2850, 20},

		// ── POULETFLEISCH ───────────────────────────────────────────────────
		{"ff000000-0003-0008-0000-000000000001", frohsinnCatPoulet,
			"Riz Casimir", "Pouletgeschnetzeltes, Curry mit Früchten im Reisring", "food", "kitchen", 2650, 18},
		{"ff000000-0003-0008-0000-000000000002", frohsinnCatPoulet,
			"Pouletschnitzel Pommes", "Pouletschnitzel mit Pommes Frites", "food", "grill", 2650, 16},
		{"ff000000-0003-0008-0000-000000000003", frohsinnCatPoulet,
			"Pouletgeschnetzeltes Rahmsauce", "In Rahmsauce und Nudeln", "food", "grill", 2850, 18},
		{"ff000000-0003-0008-0000-000000000004", frohsinnCatPoulet,
			"Fitnessteller", "Pouletbrustfilet mit Salaten und Kräuterbutter", "food", "grill", 2650, 14},
		{"ff000000-0003-0008-0000-000000000005", frohsinnCatPoulet,
			"Poulet Cordon Bleu", "Mit Pommes Frites", "food", "grill", 2950, 20},
		{"ff000000-0003-0008-0000-000000000006", frohsinnCatPoulet,
			"Pouletbrust auf Fadenbrot", "Currysauce, Pommes Frites und Salat", "food", "grill", 2950, 18},

		// ── SCHWEINEFLEISCH ─────────────────────────────────────────────────
		{"ff000000-0003-0009-0000-000000000001", frohsinnCatSchwein,
			"Schweineschnitzel Pommes", "Schweineschnitzel mit Pommes Frites", "food", "grill", 2650, 16},
		{"ff000000-0003-0009-0000-000000000002", frohsinnCatSchwein,
			"Schweinesteak", "Gemischter Salat, Kräuterbutter, Pommes Frites", "food", "grill", 3650, 20},
		{"ff000000-0003-0009-0000-000000000003", frohsinnCatSchwein,
			"Schweins Saltimbocca", "Mit Risotto und Gemüse", "food", "grill", 2850, 20},
		{"ff000000-0003-0009-0000-000000000004", frohsinnCatSchwein,
			"Schweinsrahmschnitzel", "Mit Nudeln", "food", "grill", 2850, 18},

		// ── KALBFLEISCH ─────────────────────────────────────────────────────
		{"ff000000-0003-0010-0000-000000000001", frohsinnCatKalb,
			"Wienerschnitzel", "Mit Gemüse und Pommes Frites", "food", "grill", 3850, 18},
		{"ff000000-0003-0010-0000-000000000002", frohsinnCatKalb,
			"Saltimbocca alla Romana", "Mit Risotto und Gemüse", "food", "grill", 3850, 20},
		{"ff000000-0003-0010-0000-000000000003", frohsinnCatKalb,
			"Bratwurst an Zwiebelsauce", "Mit Pommes Frites", "food", "grill", 2650, 16},
		{"ff000000-0003-0010-0000-000000000004", frohsinnCatKalb,
			"Kalbsgeschnetzeltes Zürcher Art", "Mit Pommes Frites", "food", "grill", 3850, 20},
		{"ff000000-0003-0010-0000-000000000005", frohsinnCatKalb,
			"Kalbspiccata Milanese", "Mit Tomaten-Spaghetti", "food", "grill", 3850, 20},
		{"ff000000-0003-0010-0000-000000000006", frohsinnCatKalb,
			"Kalbsschnitzel", "Kräuterbutter, BBQ Sauce, Salat, Pommes Frites", "food", "grill", 3950, 20},
		{"ff000000-0003-0010-0000-000000000007", frohsinnCatKalb,
			"Kalbsrahmschnitzel", "Mit Gemüse und Nudeln", "food", "grill", 3950, 20},
		{"ff000000-0003-0010-0000-000000000008", frohsinnCatKalb,
			"Kalbs-Steak", "Grünpfeffersauce, Gemüse, Nudeln", "food", "grill", 4250, 22},
		{"ff000000-0003-0010-0000-000000000009", frohsinnCatKalb,
			"Leberli mit Madeirasauce", "Mit Rösti", "food", "grill", 3250, 18},
		{"ff000000-0003-0010-0000-000000000010", frohsinnCatKalb,
			"Leberli im Butter", "Mit Rösti", "food", "grill", 3250, 18},

		// ── RINDFLEISCH ─────────────────────────────────────────────────────
		{"ff000000-0003-0011-0000-000000000001", frohsinnCatRind,
			"Entrecôte auf heissem Stein", "Mit Saucen, Gemüsegarnitur und Pommes", "food", "grill", 4450, 22},
		{"ff000000-0003-0011-0000-000000000002", frohsinnCatRind,
			"Entrecôte mit Kräuterbutter", "Gemüsegarnitur und Nudeln", "food", "grill", 4450, 22},
		{"ff000000-0003-0011-0000-000000000003", frohsinnCatRind,
			"Entrecôte an Madeirasauce", "Mit Gemüsegarnitur und Reis", "food", "grill", 4450, 22},
		{"ff000000-0003-0011-0000-000000000004", frohsinnCatRind,
			"Entrecôte Café de Paris", "Mit Gemüsegarnitur und Pommes Frites", "food", "grill", 4250, 22},

		// ── FISCH ────────────────────────────────────────────────────────────
		{"ff000000-0003-0012-0000-000000000001", frohsinnCatFisch,
			"Egli Filets im Bierteig", "Tartarsauce, Salzkartoffeln", "food", "kitchen", 3250, 18},
		{"ff000000-0003-0012-0000-000000000002", frohsinnCatFisch,
			"Egli Filets Müllerin Art", "Spinat, Salzkartoffeln", "food", "kitchen", 3250, 18},
		{"ff000000-0003-0012-0000-000000000003", frohsinnCatFisch,
			"Riesencervetten Indischer Art", "Im Reisring", "food", "kitchen", 3250, 18},
		{"ff000000-0003-0012-0000-000000000004", frohsinnCatFisch,
			"Riesencervetten mit Knoblauchsauce", "Und Butterreis", "food", "kitchen", 3250, 18},
		{"ff000000-0003-0012-0000-000000000005", frohsinnCatFisch,
			"Calamares", "Tartarsauce oder Mayonnaise", "food", "kitchen", 2350, 14},
		{"ff000000-0003-0012-0000-000000000006", frohsinnCatFisch,
			"Zanderfilets mit Safransauce", "Und Butterreis", "food", "kitchen", 3250, 18},
		{"ff000000-0003-0012-0000-000000000007", frohsinnCatFisch,
			"Lachsfilet", "Zitrone, Olivenöl, Risotto", "food", "kitchen", 3250, 18},
		{"ff000000-0003-0012-0000-000000000008", frohsinnCatFisch,
			"Gamberoni alla Luganesi", "Riesencervetten, Cognac-Tomatenrahmsauce, Nudeln", "food", "kitchen", 3250, 18},

		// ── CORDON BLEU ─────────────────────────────────────────────────────
		{"ff000000-0003-0013-0000-000000000001", frohsinnCatCordonBleu,
			"Cordon Bleu Standard", "Vorderschinken, Raclettekäse", "food", "grill", 3050, 20},
		{"ff000000-0003-0013-0000-000000000002", frohsinnCatCordonBleu,
			"Cordon Bleu ai Funghi", "Vorderschinken, Raclettekäse, Pilze", "food", "grill", 3150, 20},
		{"ff000000-0003-0013-0000-000000000003", frohsinnCatCordonBleu,
			"Cordon Bleu Hawaii", "Vorderschinken, Raclettekäse, Ananas", "food", "grill", 3150, 20},
		{"ff000000-0003-0013-0000-000000000004", frohsinnCatCordonBleu,
			"Cordon Bleu Carbonara", "Vorderschinken, Raclettekäse, Speck, Ei, Zwiebeln", "food", "grill", 3250, 20},
		{"ff000000-0003-0013-0000-000000000005", frohsinnCatCordonBleu,
			"Cordon Bleu Bianca", "Vorderschinken, Raclettekäse, Speck, Zwiebeln, Pilze", "food", "grill", 3250, 20},
		{"ff000000-0003-0013-0000-000000000006", frohsinnCatCordonBleu,
			"Cordon Bleu Diavolo", "Vorderschinken, Raclettekäse, scharfe Salami, Gorgonzola, Peperoncini", "food", "grill", 3450, 22},
		{"ff000000-0003-0013-0000-000000000007", frohsinnCatCordonBleu,
			"Cordon Bleu Ticino", "Vorderschinken, Raclettekäse, Parmaschinken, Gorgonzola", "food", "grill", 3450, 22},

		// ── KINDERMENÜ ──────────────────────────────────────────────────────
		{"ff000000-0003-0014-0000-000000000001", frohsinnCatKinder,
			"Pizza Margherita Kids", "Tomatensauce, Mozzarella", "food", "kitchen", 1750, 12},
		{"ff000000-0003-0014-0000-000000000002", frohsinnCatKinder,
			"Chicken Nuggets mit Pommes", "Knusprige Chicken Nuggets", "food", "kitchen", 1750, 14},
		{"ff000000-0003-0014-0000-000000000003", frohsinnCatKinder,
			"Schnipo", "Paniertes Pouletschnitzel mit Pommes Frites", "food", "grill", 1750, 14},
		{"ff000000-0003-0014-0000-000000000004", frohsinnCatKinder,
			"Spaghetti Napoli Kids", "Mit Tomatensauce", "food", "kitchen", 1750, 12},

		// ── DESSERT & GLACÉ ─────────────────────────────────────────────────
		{"ff000000-0003-0015-0000-000000000001", frohsinnCatDessert,
			"Bananensplit", "Vanille, Schoko, Bananen, heisse Schokolade, Schlagrahm", "food", "dessert", 1450, 5},
		{"ff000000-0003-0015-0000-000000000002", frohsinnCatDessert,
			"Coupe Dänemark", "Vanille, Schokosauce, Schlagrahm", "food", "dessert", 1450, 3},
		{"ff000000-0003-0015-0000-000000000003", frohsinnCatDessert,
			"Coupe Romanoff", "Vanille, Erdbeerglace, Erdbeere, Topping, Schlagrahm", "food", "dessert", 1450, 3},
		{"ff000000-0003-0015-0000-000000000004", frohsinnCatDessert,
			"Coupe Kaffeeglace", "Kaffeeglace mit Schlagrahm", "food", "dessert", 1450, 3},
		{"ff000000-0003-0015-0000-000000000005", frohsinnCatDessert,
			"Sorbet Zwetschgen", "Mit Pflümli", "food", "dessert", 1450, 3},
		{"ff000000-0003-0015-0000-000000000006", frohsinnCatDessert,
			"Coupe Colonel", "Zitronensorbet und Vodka", "food", "dessert", 1450, 3},
		{"ff000000-0003-0015-0000-000000000007", frohsinnCatDessert,
			"Apfelstrudel", "Vanilleglace, Schlagrahm, Saisonfrüchte", "food", "dessert", 1450, 5},
		{"ff000000-0003-0015-0000-000000000008", frohsinnCatDessert,
			"Apfelchüechli", "Sirup und Vanilleglace", "food", "dessert", 1450, 8},

		// ── KAFFEE & TEE ────────────────────────────────────────────────────
		{"ff000000-0003-0016-0000-000000000001", frohsinnCatKaffee,
			"Kaffee", "Tasse Kaffee", "beverage", "bar", 450, 0},
		{"ff000000-0003-0016-0000-000000000002", frohsinnCatKaffee,
			"Espresso", "Einfacher Espresso", "beverage", "bar", 450, 0},
		{"ff000000-0003-0016-0000-000000000003", frohsinnCatKaffee,
			"Doppelter Espresso", "Doppelter Espresso", "beverage", "bar", 600, 0},
		{"ff000000-0003-0016-0000-000000000004", frohsinnCatKaffee,
			"Cappuccino", "Espresso mit Milchschaum", "beverage", "bar", 590, 0},
		{"ff000000-0003-0016-0000-000000000005", frohsinnCatKaffee,
			"Latte Macchiato", "Milchkaffee im Glas", "beverage", "bar", 650, 0},
		{"ff000000-0003-0016-0000-000000000006", frohsinnCatKaffee,
			"Milchkaffee", "Schale Milchkaffee", "beverage", "bar", 450, 0},
		{"ff000000-0003-0016-0000-000000000007", frohsinnCatKaffee,
			"Irish Coffee", "Whisky, Kaffee, Schlagrahm", "alcohol", "bar", 1250, 0},
		{"ff000000-0003-0016-0000-000000000008", frohsinnCatKaffee,
			"Tee", "Auswahl versch. Sorten", "beverage", "bar", 450, 0},

		// ── GETRÄNKE & BIER ──────────────────────────────────────────────────
		{"ff000000-0003-0017-0000-000000000001", frohsinnCatGetraenke,
			"Mineralwasser mit Kohlensäure", "3dl", "beverage", "bar", 350, 0},
		{"ff000000-0003-0017-0000-000000000002", frohsinnCatGetraenke,
			"Mineralwasser ohne Kohlensäure", "3dl", "beverage", "bar", 350, 0},
		{"ff000000-0003-0017-0000-000000000003", frohsinnCatGetraenke,
			"Ice Tea", "3dl", "beverage", "bar", 350, 0},
		{"ff000000-0003-0017-0000-000000000004", frohsinnCatGetraenke,
			"Coca Cola", "3dl", "beverage", "bar", 350, 0},
		{"ff000000-0003-0017-0000-000000000005", frohsinnCatGetraenke,
			"Coca Cola Zero", "3dl", "beverage", "bar", 350, 0},
		{"ff000000-0003-0017-0000-000000000006", frohsinnCatGetraenke,
			"Citro", "3dl Zitronenlimo", "beverage", "bar", 350, 0},
		{"ff000000-0003-0017-0000-000000000007", frohsinnCatGetraenke,
			"Offenes Bier", "3dl Fassbier", "alcohol", "bar", 390, 0},

		// ── APERITIF & SPIRITUOSEN ──────────────────────────────────────────
		{"ff000000-0003-0018-0000-000000000001", frohsinnCatAperitif,
			"Aperol Spritz", "Aperol, Prosecco, Soda, Orange", "alcohol", "bar", 1100, 0},
		{"ff000000-0003-0018-0000-000000000002", frohsinnCatAperitif,
			"Hugo", "Prosecco, Holunderblütensirup, Minze, Soda", "alcohol", "bar", 1100, 0},
		{"ff000000-0003-0018-0000-000000000003", frohsinnCatAperitif,
			"Prosecco", "1dl Prosecco", "alcohol", "bar", 850, 0},
		{"ff000000-0003-0018-0000-000000000004", frohsinnCatAperitif,
			"Martini Bianco", "4cl", "alcohol", "bar", 850, 0},
		{"ff000000-0003-0018-0000-000000000005", frohsinnCatAperitif,
			"Campari", "4cl", "alcohol", "bar", 850, 0},
		{"ff000000-0003-0018-0000-000000000006", frohsinnCatAperitif,
			"Ramazzotti", "4cl", "alcohol", "bar", 850, 0},
		{"ff000000-0003-0018-0000-000000000007", frohsinnCatAperitif,
			"Grappa", "2cl", "alcohol", "bar", 950, 0},
		{"ff000000-0003-0018-0000-000000000008", frohsinnCatAperitif,
			"Limoncello", "4cl", "alcohol", "bar", 1050, 0},
	}

	for i, p := range products {
		costPrice := p.price * 30 / 100
		prepTime := sql.NullInt32{Int32: int32(p.prep), Valid: p.prep > 0}
		if err := exec(tx, `
			INSERT INTO products (id, tenant_id, category_id, name, description, price, cost_price, tax_group, is_active, display_order, prep_time_minutes, printer_group, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,true,$9,$10,$11,$12,$13,0,false)
			ON CONFLICT (id) DO NOTHING`,
			p.id, frohsinnTenantID, p.catID, p.name, p.desc, p.price, costPrice,
			p.taxGroup, i, prepTime, p.printer, now, now,
		); err != nil {
			return fmt.Errorf("product %s: %w", p.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Floors (2)
// ---------------------------------------------------------------------------

func seedFrohsinnFloors(tx *sql.Tx, now time.Time) error {
	floors := []struct {
		id, name string
		order    int
	}{
		{frohsinnFloorSaal, "Saal", 0},
		{frohsinnFloorTerrasse, "Terrasse", 1},
	}
	for _, f := range floors {
		if err := exec(tx, `
			INSERT INTO floors (id, tenant_id, name, display_order, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,0,false)
			ON CONFLICT (id) DO NOTHING`,
			f.id, frohsinnTenantID, f.name, f.order, now, now,
		); err != nil {
			return fmt.Errorf("floor %s: %w", f.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Tables (12: 8 Saal + 4 Terrasse)
// ---------------------------------------------------------------------------

func seedFrohsinnTables(tx *sql.Tx, now time.Time) error {
	type tbl struct {
		id, floorID, name, shape string
		cap                      int
		x, y, w, h               float64
	}
	tables := []tbl{
		// Saal S1–S8
		{"ff000000-000a-0001-0000-000000000001", frohsinnFloorSaal, "S1", "rectangle", 4, 50, 50, 120, 80},
		{"ff000000-000a-0001-0000-000000000002", frohsinnFloorSaal, "S2", "rectangle", 4, 210, 50, 120, 80},
		{"ff000000-000a-0001-0000-000000000003", frohsinnFloorSaal, "S3", "rectangle", 6, 370, 50, 150, 90},
		{"ff000000-000a-0001-0000-000000000004", frohsinnFloorSaal, "S4", "rectangle", 2, 560, 50, 100, 70},
		{"ff000000-000a-0001-0000-000000000005", frohsinnFloorSaal, "S5", "rectangle", 4, 50, 190, 120, 80},
		{"ff000000-000a-0001-0000-000000000006", frohsinnFloorSaal, "S6", "rectangle", 4, 210, 190, 120, 80},
		{"ff000000-000a-0001-0000-000000000007", frohsinnFloorSaal, "S7", "rectangle", 8, 370, 190, 170, 100},
		{"ff000000-000a-0001-0000-000000000008", frohsinnFloorSaal, "S8", "rectangle", 4, 50, 340, 120, 80},
		// Terrasse T1–T4
		{"ff000000-000a-0002-0000-000000000001", frohsinnFloorTerrasse, "T1", "circle", 4, 80, 60, 110, 110},
		{"ff000000-000a-0002-0000-000000000002", frohsinnFloorTerrasse, "T2", "rectangle", 6, 260, 60, 150, 90},
		{"ff000000-000a-0002-0000-000000000003", frohsinnFloorTerrasse, "T3", "circle", 2, 80, 230, 90, 90},
		{"ff000000-000a-0002-0000-000000000004", frohsinnFloorTerrasse, "T4", "rectangle", 4, 260, 230, 120, 80},
	}
	for _, t := range tables {
		if err := exec(tx, `
			INSERT INTO restaurant_tables (id, tenant_id, floor_id, name, capacity, shape, pos_x, pos_y, width, height, status, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'available',$11,$12,0,false)
			ON CONFLICT (id) DO NOTHING`,
			t.id, frohsinnTenantID, t.floorID, t.name, t.cap, t.shape,
			t.x, t.y, t.w, t.h, now, now,
		); err != nil {
			return fmt.Errorf("table %s: %w", t.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Tax Profiles (Swiss: dine-in 8.1%, takeaway food 2.6%, alcohol 8.1%)
// ---------------------------------------------------------------------------

func seedFrohsinnTaxProfiles(tx *sql.Tx, now time.Time) error {
	type profile struct {
		id, orderType, taxGroup, name string
		rate                          float64
	}
	profiles := []profile{
		{"ff000000-000b-0001-0000-000000000001", "dine_in", "food", "MWST 8.1% (Restaurant)", 8.1},
		{"ff000000-000b-0001-0000-000000000002", "dine_in", "beverage", "MWST 8.1% (Restaurant)", 8.1},
		{"ff000000-000b-0001-0000-000000000003", "dine_in", "alcohol", "MWST 8.1% (Restaurant)", 8.1},
		{"ff000000-000b-0002-0000-000000000001", "takeaway", "food", "MWST 2.6% (Takeaway)", 2.6},
		{"ff000000-000b-0002-0000-000000000002", "takeaway", "beverage", "MWST 2.6% (Takeaway)", 2.6},
		{"ff000000-000b-0002-0000-000000000003", "takeaway", "alcohol", "MWST 8.1% (Alkohol)", 8.1},
		{"ff000000-000b-0003-0000-000000000001", "delivery", "food", "MWST 2.6% (Lieferung)", 2.6},
		{"ff000000-000b-0003-0000-000000000002", "delivery", "beverage", "MWST 2.6% (Lieferung)", 2.6},
		{"ff000000-000b-0003-0000-000000000003", "delivery", "alcohol", "MWST 8.1% (Alkohol)", 8.1},
	}
	for _, p := range profiles {
		if err := exec(tx, `
			INSERT INTO tax_profiles (id, tenant_id, country_code, order_type, product_tax_group, tax_rate, tax_name, is_default, created_at, updated_at)
			VALUES ($1,$2,'CH',$3,$4,$5,$6,false,$7,$8)
			ON CONFLICT (id) DO NOTHING`,
			p.id, frohsinnTenantID, p.orderType, p.taxGroup, p.rate, p.name, now, now,
		); err != nil {
			return fmt.Errorf("tax_profile %s/%s: %w", p.orderType, p.taxGroup, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Demo Orders (2 completed orders)
// ---------------------------------------------------------------------------

func seedFrohsinnDemoOrders(tx *sql.Tx, now time.Time) error {
	yesterday := now.AddDate(0, 0, -1)
	tableS2 := "ff000000-000a-0001-0000-000000000002"
	tableT1 := "ff000000-000a-0002-0000-000000000001"

	type orderItem struct {
		id, productID, productName string
		price                      int
	}
	type demoOrder struct {
		ticketID, billID, tableID string
		orderNum, guests          int
		subtotal, taxAmt, total   int
		openedH, closedH          int
		items                     []orderItem
		payMethod                 string
		tendered                  int
		kdsGroups                 []string
		kdsTableName              string
	}

	orders := []demoOrder{
		{
			ticketID: frohsinnTicket1ID, billID: frohsinnBill1ID, tableID: tableS2,
			orderNum: 3001, guests: 2,
			subtotal: 7600, taxAmt: 616, total: 8216,
			openedH: 19, closedH: 20, payMethod: "cash", tendered: 9000,
			items: []orderItem{
				{"ff000000-000c-0001-0000-000000000001", "ff000000-0003-0005-0000-000000000007", "Pizza Rustica", 2350},
				{"ff000000-000c-0001-0000-000000000002", "ff000000-0003-0005-0000-000000000002", "Pizza Prosciutto", 2250},
				{"ff000000-000c-0001-0000-000000000003", "ff000000-0003-0015-0000-000000000007", "Apfelstrudel", 1450},
				{"ff000000-000c-0001-0000-000000000004", "ff000000-0003-0015-0000-000000000002", "Coupe Dänemark", 1450},
				{"ff000000-000c-0001-0000-000000000005", "ff000000-0003-0017-0000-000000000001", "Mineralwasser", 350},
				{"ff000000-000c-0001-0000-000000000006", "ff000000-0003-0017-0000-000000000001", "Mineralwasser", 350},
			},
			kdsGroups: []string{"kitchen", "dessert", "bar"}, kdsTableName: "S2",
		},
		{
			ticketID: frohsinnTicket2ID, billID: frohsinnBill2ID, tableID: tableT1,
			orderNum: 3002, guests: 3,
			subtotal: 10000, taxAmt: 810, total: 10810,
			openedH: 12, closedH: 13, payMethod: "card", tendered: 10810,
			items: []orderItem{
				{"ff000000-000c-0002-0000-000000000001", "ff000000-0003-0010-0000-000000000001", "Wienerschnitzel", 3850},
				{"ff000000-000c-0002-0000-000000000002", "ff000000-0003-0003-0000-000000000006", "Pasta Carbonara", 2350},
				{"ff000000-000c-0002-0000-000000000003", "ff000000-0003-0003-0000-000000000003", "Pasta Bolognese", 2350},
				{"ff000000-000c-0002-0000-000000000004", "ff000000-0003-0016-0000-000000000004", "Cappuccino", 590},
				{"ff000000-000c-0002-0000-000000000005", "ff000000-0003-0016-0000-000000000004", "Cappuccino", 590},
				{"ff000000-000c-0002-0000-000000000006", "ff000000-0003-0016-0000-000000000002", "Espresso", 450},
			},
			kdsGroups: []string{"grill", "kitchen", "bar"}, kdsTableName: "T1",
		},
	}

	for i, o := range orders {
		openedAt := yesterday.Add(time.Duration(o.openedH)*time.Hour + 20*time.Minute)
		closedAt := yesterday.Add(time.Duration(o.closedH)*time.Hour + 5*time.Minute)

		if err := exec(tx, `
			INSERT INTO tickets (id, tenant_id, order_number, order_type, table_id, waiter_id, guest_count, status, channel, subtotal, tax_amount, discount_amount, total, opened_at, closed_at, device_id, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,'dine_in',$4,$5,$6,'fully_paid','pos',$7,$8,0,$9,$10,$11,'frohsinn-device-001',$12,$13,0,false)
			ON CONFLICT (id) DO NOTHING`,
			o.ticketID, frohsinnTenantID, o.orderNum, o.tableID, frohsinnWaiter1ID, o.guests,
			o.subtotal, o.taxAmt, o.total, openedAt, closedAt, openedAt, closedAt,
		); err != nil {
			return fmt.Errorf("frohsinn ticket %d: %w", i+1, err)
		}

		for _, item := range o.items {
			taxAmt := int(float64(item.price) * 0.081)
			if err := exec(tx, `
				INSERT INTO order_items (id, tenant_id, ticket_id, product_id, product_name, quantity, unit_price, subtotal, tax_amount, discount_amount, status, sent_to_kitchen, course, created_at, updated_at, sync_status, is_deleted)
				VALUES ($1,$2,$3,$4,$5,1,$6,$7,$8,0,'served',true,1,$9,$10,0,false)
				ON CONFLICT (id) DO NOTHING`,
				item.id, frohsinnTenantID, o.ticketID, item.productID, item.productName,
				item.price, item.price, taxAmt, openedAt, openedAt,
			); err != nil {
				return fmt.Errorf("frohsinn order_item %s: %w", item.id, err)
			}
		}

		for j, group := range o.kdsGroups {
			ktID := fmt.Sprintf("ff000000-000d-%04d-0000-%012d", i+1, j+1)
			if err := exec(tx, `
				INSERT INTO kitchen_tickets (id, tenant_id, ticket_id, kitchen_table_name, order_number, printer_group, status, sent_at, started_at, completed_at, created_at, sync_status, is_deleted)
				VALUES ($1,$2,$3,$4,$5,$6,'completed',$7,$8,$9,$10,0,false)
				ON CONFLICT (id) DO NOTHING`,
				ktID, frohsinnTenantID, o.ticketID, o.kdsTableName, o.orderNum, group,
				openedAt.Add(1*time.Minute),
				openedAt.Add(5*time.Minute),
				openedAt.Add(35*time.Minute),
				openedAt.Add(1*time.Minute),
			); err != nil {
				return fmt.Errorf("frohsinn kitchen_ticket %s: %w", ktID, err)
			}
		}

		if err := exec(tx, `
			INSERT INTO bills (id, tenant_id, ticket_id, bill_number, subtotal, tax_amount, discount_amount, total, status, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,0,$7,'paid',$8,$9,0,false)
			ON CONFLICT (id) DO NOTHING`,
			o.billID, frohsinnTenantID, o.ticketID, o.orderNum, o.subtotal, o.taxAmt, o.total, closedAt, closedAt,
		); err != nil {
			return fmt.Errorf("frohsinn bill %d: %w", i+1, err)
		}

		changeAmt := o.tendered - o.total
		pymtID := fmt.Sprintf("ff000000-000e-%04d-0000-000000000001", i+1)
		if err := exec(tx, `
			INSERT INTO payments (id, tenant_id, bill_id, ticket_id, payment_method, amount, tip_amount, tendered_amount, change_amount, received_by, paid_at, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,0,$7,$8,$9,$10,$11,$12,0,false)
			ON CONFLICT (id) DO NOTHING`,
			pymtID, frohsinnTenantID, o.billID, o.ticketID, o.payMethod,
			o.total, o.tendered, changeAmt, frohsinnWaiter1ID, closedAt, closedAt, closedAt,
		); err != nil {
			return fmt.Errorf("frohsinn payment %d: %w", i+1, err)
		}
	}
	return nil
}
