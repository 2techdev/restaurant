// seed_clubdemo.go — Club Demo restaurant seed data.
//
// "Club Demo" is a showcase Swiss brasserie designed to demonstrate every
// GastroCore feature: multi-floor table plan, full Swiss-Italian menu, KDS
// routing, modifier groups, online ordering and demo orders.
//
// Fixed UUID namespace: cc000000-…  (never reused for production tenants)
package main

import (
	"database/sql"
	"fmt"
	"time"
)

// ---------------------------------------------------------------------------
// Fixed UUIDs — Club Demo
// ---------------------------------------------------------------------------

const (
	clubDemoTenantID = "cc000000-0000-0000-0000-000000000001"

	// Staff
	clubAdminID   = "cc000000-0001-0000-0000-000000000001"
	clubWaiter1ID = "cc000000-0001-0000-0000-000000000002"
	clubWaiter2ID = "cc000000-0001-0000-0000-000000000003"
	clubKitchenID = "cc000000-0001-0000-0000-000000000004"
	clubManagerID = "cc000000-0001-0000-0000-000000000005"

	// Categories
	clubCatSoupStarter  = "cc000000-0002-0000-0000-000000000001"
	clubCatSalads       = "cc000000-0002-0000-0000-000000000002"
	clubCatMains        = "cc000000-0002-0000-0000-000000000003"
	clubCatPizzaPasta   = "cc000000-0002-0000-0000-000000000004"
	clubCatDesserts     = "cc000000-0002-0000-0000-000000000005"
	clubCatSoftDrinks   = "cc000000-0002-0000-0000-000000000006"
	clubCatWinesBeer    = "cc000000-0002-0000-0000-000000000007"

	// Modifier groups
	clubMgPizzaSize  = "cc000000-0004-0000-0000-000000000001"
	clubMgGarpunkt   = "cc000000-0004-0000-0000-000000000002"
	clubMgBeilage    = "cc000000-0004-0000-0000-000000000003"
	clubMgZutaten    = "cc000000-0004-0000-0000-000000000004"

	// Floors
	clubFloorHauptraumID   = "cc000000-0005-0000-0000-000000000001"
	clubFloorWintergarten  = "cc000000-0005-0000-0000-000000000002"

	// Demo tickets / bills
	clubTicket1ID = "cc000000-0007-0000-0000-000000000001"
	clubTicket2ID = "cc000000-0007-0000-0000-000000000002"
	clubBill1ID   = "cc000000-0008-0000-0000-000000000001"
	clubBill2ID   = "cc000000-0008-0000-0000-000000000002"
)

// ---------------------------------------------------------------------------
// Entry point called from main seedAll
// ---------------------------------------------------------------------------

func seedClubDemoAll(tx *sql.Tx, now time.Time) error {
	steps := []func(*sql.Tx, time.Time) error{
		seedClubDemoTenant,
		seedClubDemoUsers,
		seedClubDemoCategories,
		seedClubDemoProducts,
		seedClubDemoModifierGroups,
		seedClubDemoModifiers,
		seedClubDemoProductModifierLinks,
		seedClubDemoFloors,
		seedClubDemoTables,
		seedClubDemoTaxProfiles,
		seedClubDemoDemoOrders,
	}
	for _, fn := range steps {
		if err := fn(tx, now); err != nil {
			return fmt.Errorf("club_demo: %w", err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Tenant
// ---------------------------------------------------------------------------

func seedClubDemoTenant(tx *sql.Tx, now time.Time) error {
	return exec(tx, `
		INSERT INTO tenants (id, name, address, phone, default_tax_rate, currency_code, country_code,
		                     description, is_open, is_deleted, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,true,false,$9,$10)
		ON CONFLICT (id) DO NOTHING`,
		clubDemoTenantID,
		"Club Demo",
		"Seestrasse 77, 8002 Zürich",
		"+41 44 000 00 00",
		8.1,
		"CHF",
		"CH",
		"Showcase restaurant for GastroCore demos. Authentische Schweizer Küche mit internationalem Einfluss.",
		now, now,
	)
}

// ---------------------------------------------------------------------------
// Users (5: admin, manager, 2 waiters, kitchen)
// ---------------------------------------------------------------------------

func seedClubDemoUsers(tx *sql.Tx, now time.Time) error {
	users := []struct {
		id, name, pin, role string
	}{
		{clubAdminID, "Admin Demo", "0000", "admin"},
		{clubManagerID, "Sophie Zimmermann", "1234", "manager"},
		{clubWaiter1ID, "Lisa Moser", "1111", "waiter"},
		{clubWaiter2ID, "Jan Hofer", "2222", "waiter"},
		{clubKitchenID, "Marco Koch", "3333", "kitchen"},
	}
	for _, u := range users {
		if err := exec(tx, `
			INSERT INTO users (id, tenant_id, name, pin_hash, role, is_active, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,true,$6,$7,0,false)
			ON CONFLICT (id) DO NOTHING`,
			u.id, clubDemoTenantID, u.name, hashPin(u.pin), u.role, now, now,
		); err != nil {
			return fmt.Errorf("user %s: %w", u.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Categories (7)
// ---------------------------------------------------------------------------

func seedClubDemoCategories(tx *sql.Tx, now time.Time) error {
	cats := []struct {
		id, name, icon, color string
		order                 int
	}{
		{clubCatSoupStarter, "Suppen & Vorspeisen", "🍲", "#FF6B35", 0},
		{clubCatSalads, "Salate", "🥗", "#34C759", 1},
		{clubCatMains, "Hauptspeisen", "🍖", "#FF3B30", 2},
		{clubCatPizzaPasta, "Pizza & Pasta", "🍕", "#FF9500", 3},
		{clubCatDesserts, "Desserts", "🍰", "#FF375F", 4},
		{clubCatSoftDrinks, "Alkoholfreie Getränke", "🥤", "#4F8CFF", 5},
		{clubCatWinesBeer, "Weine & Bier", "🍷", "#AF52DE", 6},
	}
	for _, c := range cats {
		if err := exec(tx, `
			INSERT INTO categories (id, tenant_id, name, icon, color, display_order, is_active, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,true,$7,$8,0,false)
			ON CONFLICT (id) DO NOTHING`,
			c.id, clubDemoTenantID, c.name, c.icon, c.color, c.order, now, now,
		); err != nil {
			return fmt.Errorf("category %s: %w", c.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Products (38 items across 7 categories)
// ---------------------------------------------------------------------------

func seedClubDemoProducts(tx *sql.Tx, now time.Time) error {
	type product struct {
		id, catID, name, desc, taxGroup, printer string
		price, prep                              int
	}
	products := []product{
		// ── Suppen & Vorspeisen ─────────────────────────────────────────────
		{"cc000000-0003-0001-0000-000000000001", clubCatSoupStarter,
			"Tagessuppe", "Suppe des Tages mit frischem Brot", "food", "kitchen", 750, 5},
		{"cc000000-0003-0001-0000-000000000002", clubCatSoupStarter,
			"Bündner Gerstensuppe", "Traditionelle Gerstensuppe mit Speck und Gemüse", "food", "kitchen", 1050, 8},
		{"cc000000-0003-0001-0000-000000000003", clubCatSoupStarter,
			"Bruschetta", "Geröstetes Brot, frische Tomaten, Basilikum, Knoblauch, Olivenöl", "food", "cold", 1050, 5},
		{"cc000000-0003-0001-0000-000000000004", clubCatSoupStarter,
			"Gemischter Vorspeisenteller", "Hausgemachte Auswahl kalter Vorspeisen für 2 Personen", "food", "cold", 1850, 8},
		{"cc000000-0003-0001-0000-000000000005", clubCatSoupStarter,
			"Ziegenkäse auf Feigenkonfitüre", "Warmer Ziegenkäse auf Toast, Feigenkonfitüre, Rucola", "food", "kitchen", 1650, 8},
		// ── Salate ──────────────────────────────────────────────────────────
		{"cc000000-0003-0002-0000-000000000001", clubCatSalads,
			"Nüsslisalat mit Speck und Ei", "Feldsalat, knuspriger Speck, hartgekochtes Ei, Senf-Vinaigrette", "food", "cold", 1550, 6},
		{"cc000000-0003-0002-0000-000000000002", clubCatSalads,
			"Caesar Salad", "Römersalat, Croutons, Parmesan, Caesar-Dressing", "food", "cold", 1750, 6},
		{"cc000000-0003-0002-0000-000000000003", clubCatSalads,
			"Caprese", "Büffelmozzarella, Tomaten, Basilikum, Olivenöl extra vergine", "food", "cold", 1450, 4},
		{"cc000000-0003-0002-0000-000000000004", clubCatSalads,
			"Rucola-Salat", "Rucola, Kirschtomaten, Parmesan-Hobel, Balsamico-Reduktion", "food", "cold", 1350, 4},
		// ── Hauptspeisen ────────────────────────────────────────────────────
		{"cc000000-0003-0003-0000-000000000001", clubCatMains,
			"Zürcher Geschnetzeltes", "Kalbsgeschnetzeltes Zürcher Art, Rösti, Rahmsauce, Weisswein", "food", "grill", 3850, 20},
		{"cc000000-0003-0003-0000-000000000002", clubCatMains,
			"Wiener Schnitzel", "Paniertes Kalbsschnitzel, Zitronenscheibe, Kartoffelsalat", "food", "grill", 3850, 18},
		{"cc000000-0003-0003-0000-000000000003", clubCatMains,
			"Entrecôte vom Grill", "220g Schweizer Rind, Grillgemüse, Café-de-Paris-Butter, Pommes", "food", "grill", 4450, 22},
		{"cc000000-0003-0003-0000-000000000004", clubCatMains,
			"Lachsfilet", "Atlantik-Lachs, Safransauce, Blattspinat, Basmatireis", "food", "kitchen", 3250, 18},
		{"cc000000-0003-0003-0000-000000000005", clubCatMains,
			"Rumpsteak", "250g Rumpsteak, Kräuterbutter, Ratatouille, Pommes frites", "food", "grill", 4250, 20},
		{"cc000000-0003-0003-0000-000000000006", clubCatMains,
			"Cordon Bleu", "Hausgemachtes Cordon Bleu, Pommes frites, Gemüsegarnitur", "food", "grill", 3050, 18},
		{"cc000000-0003-0003-0000-000000000007", clubCatMains,
			"Rahmspinat mit Spiegelei", "Blattspinat in Rahmsauce, zwei Spiegeleier, Rösti", "food", "kitchen", 2250, 12},
		{"cc000000-0003-0003-0000-000000000008", clubCatMains,
			"Poulet Cordon Bleu", "Poulet-Cordon Bleu, Pommes frites, Tomatensalat", "food", "grill", 2950, 16},
		{"cc000000-0003-0003-0000-000000000009", clubCatMains,
			"Rinds-Tagliata", "Aufgeschnittenes Entrecôte, Rucola, Parmesan, Olivenöl, Balsamico", "food", "grill", 4450, 20},
		// ── Pizza & Pasta ────────────────────────────────────────────────────
		{"cc000000-0003-0004-0000-000000000001", clubCatPizzaPasta,
			"Pizza Margherita", "Tomatensauce, Mozzarella, frisches Basilikum", "food", "kitchen", 1850, 12},
		{"cc000000-0003-0004-0000-000000000002", clubCatPizzaPasta,
			"Pizza Prosciutto e Rucola", "Parmaschinken, Rucola, Kirschtomaten, Parmesan", "food", "kitchen", 2550, 12},
		{"cc000000-0003-0004-0000-000000000003", clubCatPizzaPasta,
			"Pizza Quattro Formaggi", "Mozzarella, Gorgonzola, Emmentaler, Parmesan", "food", "kitchen", 2650, 12},
		{"cc000000-0003-0004-0000-000000000004", clubCatPizzaPasta,
			"Pizza Rustica", "Speck, Zwiebeln, Peperoni, Tomatensauce, Mozzarella", "food", "kitchen", 2350, 12},
		{"cc000000-0003-0004-0000-000000000005", clubCatPizzaPasta,
			"Spaghetti Carbonara", "Spaghetti, Pancetta, Ei, Pecorino Romano, schwarzer Pfeffer", "food", "kitchen", 2350, 14},
		{"cc000000-0003-0004-0000-000000000006", clubCatPizzaPasta,
			"Pasta Bolognese", "Pappardelle, Rindfleisch-Bolognese, Parmesan", "food", "kitchen", 2350, 14},
		{"cc000000-0003-0004-0000-000000000007", clubCatPizzaPasta,
			"Tagliatelle Porcini", "Tagliatelle, Steinpilze, Knoblauch, Rahmsauce, Parmesan", "food", "kitchen", 2550, 15},
		{"cc000000-0003-0004-0000-000000000008", clubCatPizzaPasta,
			"Lasagne al Forno", "Hausgemachte Lasagne, Bolognese, Béchamelsauce, Mozzarella gratiniert", "food", "kitchen", 2450, 20},
		// ── Desserts ─────────────────────────────────────────────────────────
		{"cc000000-0003-0005-0000-000000000001", clubCatDesserts,
			"Apfelstrudel", "Hausgemachter Apfelstrudel, Vanilleglace, Zimtsahne", "food", "dessert", 1350, 5},
		{"cc000000-0003-0005-0000-000000000002", clubCatDesserts,
			"Tiramisu", "Klassisches Tiramisu mit Mascarpone und Amaretto", "food", "dessert", 1250, 3},
		{"cc000000-0003-0005-0000-000000000003", clubCatDesserts,
			"Crème Brûlée", "Vanille-Crème mit karamellisierter Zuckerkruste, saisionale Früchte", "food", "dessert", 1150, 5},
		{"cc000000-0003-0005-0000-000000000004", clubCatDesserts,
			"Sorbet des Tages", "Zwei Kugeln hausgemachtes Sorbet, frische Minze", "food", "dessert", 1050, 3},
		{"cc000000-0003-0005-0000-000000000005", clubCatDesserts,
			"Schoggimousse", "Schweizer Schokoladenmousse, Vanillesauce, Schlagrahm", "food", "dessert", 1150, 3},
		// ── Alkoholfreie Getränke ────────────────────────────────────────────
		{"cc000000-0003-0006-0000-000000000001", clubCatSoftDrinks,
			"Mineralwasser", "Still oder Sprudel, 3dl", "beverage", "bar", 450, 0},
		{"cc000000-0003-0006-0000-000000000002", clubCatSoftDrinks,
			"Coca-Cola", "3dl, inkl. Eis und Zitrone", "beverage", "bar", 450, 0},
		{"cc000000-0003-0006-0000-000000000003", clubCatSoftDrinks,
			"Orangensaft frisch gepresst", "2dl frisch gepresster Orangensaft", "beverage", "bar", 650, 0},
		{"cc000000-0003-0006-0000-000000000004", clubCatSoftDrinks,
			"Espresso", "Doppelter Espresso", "beverage", "bar", 450, 0},
		{"cc000000-0003-0006-0000-000000000005", clubCatSoftDrinks,
			"Cappuccino", "Mit feinem Milchschaum und Latte-Art", "beverage", "bar", 590, 0},
		{"cc000000-0003-0006-0000-000000000006", clubCatSoftDrinks,
			"Latte Macchiato", "Milchkaffee mit doppeltem Espresso", "beverage", "bar", 650, 0},
		{"cc000000-0003-0006-0000-000000000007", clubCatSoftDrinks,
			"Tee", "Auswahl aus verschiedenen Teesorten", "beverage", "bar", 450, 0},
		// ── Weine & Bier ─────────────────────────────────────────────────────
		{"cc000000-0003-0007-0000-000000000001", clubCatWinesBeer,
			"Fendant du Valais", "1dl, weiss, trocken, Suisse romande", "alcohol", "bar", 650, 0},
		{"cc000000-0003-0007-0000-000000000002", clubCatWinesBeer,
			"Dôle du Valais", "1dl, rot, Pinot Noir & Gamay", "alcohol", "bar", 650, 0},
		{"cc000000-0003-0007-0000-000000000003", clubCatWinesBeer,
			"Prosecco", "1dl, prickelnd, Venetien", "alcohol", "bar", 750, 0},
		{"cc000000-0003-0007-0000-000000000004", clubCatWinesBeer,
			"Bier vom Fass", "3dl, Helles vom Fass", "alcohol", "bar", 650, 0},
		{"cc000000-0003-0007-0000-000000000005", clubCatWinesBeer,
			"Heineken", "3dl Flasche", "alcohol", "bar", 550, 0},
		{"cc000000-0003-0007-0000-000000000006", clubCatWinesBeer,
			"Aperol Spritz", "Aperol, Prosecco, Soda, Orange", "alcohol", "bar", 1150, 0},
	}

	for i, p := range products {
		costPrice := p.price * 35 / 100
		prepTime := sql.NullInt32{Int32: int32(p.prep), Valid: p.prep > 0}
		if err := exec(tx, `
			INSERT INTO products (id, tenant_id, category_id, name, description, price, cost_price, tax_group, is_active, display_order, prep_time_minutes, printer_group, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,true,$9,$10,$11,$12,$13,0,false)
			ON CONFLICT (id) DO NOTHING`,
			p.id, clubDemoTenantID, p.catID, p.name, p.desc, p.price, costPrice,
			p.taxGroup, i, prepTime, p.printer, now, now,
		); err != nil {
			return fmt.Errorf("product %s: %w", p.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Modifier Groups (4)
// ---------------------------------------------------------------------------

func seedClubDemoModifierGroups(tx *sql.Tx, now time.Time) error {
	groups := []struct {
		id, name, selType   string
		min, max, order     int
		required            bool
	}{
		{clubMgPizzaSize, "Pizza-Grösse", "single", 1, 1, 0, true},
		{clubMgGarpunkt, "Garpunkt", "single", 1, 1, 1, true},
		{clubMgBeilage, "Beilage", "multiple", 0, 3, 2, false},
		{clubMgZutaten, "Zusätzliche Zutaten", "multiple", 0, 5, 3, false},
	}
	for _, g := range groups {
		if err := exec(tx, `
			INSERT INTO modifier_groups (id, tenant_id, name, selection_type, min_selections, max_selections, is_required, display_order, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,0,false)
			ON CONFLICT (id) DO NOTHING`,
			g.id, clubDemoTenantID, g.name, g.selType, g.min, g.max, g.required, g.order, now, now,
		); err != nil {
			return fmt.Errorf("modifier_group %s: %w", g.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Modifiers
// ---------------------------------------------------------------------------

func seedClubDemoModifiers(tx *sql.Tx, now time.Time) error {
	type opt struct {
		id, groupID, name string
		delta, order      int
		isDefault         bool
	}
	opts := []opt{
		// Pizza-Grösse
		{"cc000000-0006-0001-0000-000000000001", clubMgPizzaSize, "Standard 32cm", 0, 0, true},
		{"cc000000-0006-0001-0000-000000000002", clubMgPizzaSize, "Large 40cm", 500, 1, false},
		// Garpunkt
		{"cc000000-0006-0002-0000-000000000001", clubMgGarpunkt, "Rare (blutig)", 0, 0, false},
		{"cc000000-0006-0002-0000-000000000002", clubMgGarpunkt, "Medium", 0, 1, true},
		{"cc000000-0006-0002-0000-000000000003", clubMgGarpunkt, "Well Done", 0, 2, false},
		// Beilage
		{"cc000000-0006-0003-0000-000000000001", clubMgBeilage, "Pommes frites", 450, 0, false},
		{"cc000000-0006-0003-0000-000000000002", clubMgBeilage, "Rösti", 450, 1, false},
		{"cc000000-0006-0003-0000-000000000003", clubMgBeilage, "Gemischter Salat", 350, 2, false},
		{"cc000000-0006-0003-0000-000000000004", clubMgBeilage, "Basmatireis", 300, 3, false},
		// Zusätzliche Zutaten
		{"cc000000-0006-0004-0000-000000000001", clubMgZutaten, "Extra Mozzarella", 250, 0, false},
		{"cc000000-0006-0004-0000-000000000002", clubMgZutaten, "Champignons", 150, 1, false},
		{"cc000000-0006-0004-0000-000000000003", clubMgZutaten, "Peperoni", 100, 2, false},
		{"cc000000-0006-0004-0000-000000000004", clubMgZutaten, "Zwiebeln", 100, 3, false},
		{"cc000000-0006-0004-0000-000000000005", clubMgZutaten, "Oliven", 150, 4, false},
	}
	for _, o := range opts {
		if err := exec(tx, `
			INSERT INTO modifiers (id, tenant_id, group_id, name, price_delta, is_default, display_order, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,0,false)
			ON CONFLICT (id) DO NOTHING`,
			o.id, clubDemoTenantID, o.groupID, o.name, o.delta, o.isDefault, o.order, now, now,
		); err != nil {
			return fmt.Errorf("modifier %s: %w", o.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Product–Modifier Links
// ---------------------------------------------------------------------------

func seedClubDemoProductModifierLinks(tx *sql.Tx, now time.Time) error {
	type link struct {
		id, productID, groupID string
		order                  int
	}
	links := []link{
		// Pizzen → Grösse + Zutaten
		{"cc000000-0009-0001-0000-000000000001", "cc000000-0003-0004-0000-000000000001", clubMgPizzaSize, 0},
		{"cc000000-0009-0001-0000-000000000002", "cc000000-0003-0004-0000-000000000001", clubMgZutaten, 1},
		{"cc000000-0009-0001-0000-000000000003", "cc000000-0003-0004-0000-000000000002", clubMgPizzaSize, 0},
		{"cc000000-0009-0001-0000-000000000004", "cc000000-0003-0004-0000-000000000002", clubMgZutaten, 1},
		{"cc000000-0009-0001-0000-000000000005", "cc000000-0003-0004-0000-000000000003", clubMgPizzaSize, 0},
		{"cc000000-0009-0001-0000-000000000006", "cc000000-0003-0004-0000-000000000003", clubMgZutaten, 1},
		{"cc000000-0009-0001-0000-000000000007", "cc000000-0003-0004-0000-000000000004", clubMgPizzaSize, 0},
		{"cc000000-0009-0001-0000-000000000008", "cc000000-0003-0004-0000-000000000004", clubMgZutaten, 1},
		// Fleischgerichte → Garpunkt + Beilage
		{"cc000000-0009-0002-0000-000000000001", "cc000000-0003-0003-0000-000000000003", clubMgGarpunkt, 0},
		{"cc000000-0009-0002-0000-000000000002", "cc000000-0003-0003-0000-000000000003", clubMgBeilage, 1},
		{"cc000000-0009-0002-0000-000000000003", "cc000000-0003-0003-0000-000000000005", clubMgGarpunkt, 0},
		{"cc000000-0009-0002-0000-000000000004", "cc000000-0003-0003-0000-000000000005", clubMgBeilage, 1},
		{"cc000000-0009-0002-0000-000000000005", "cc000000-0003-0003-0000-000000000009", clubMgGarpunkt, 0},
		{"cc000000-0009-0002-0000-000000000006", "cc000000-0003-0003-0000-000000000009", clubMgBeilage, 1},
		// Schnitzel / Cordon Bleu → Beilage
		{"cc000000-0009-0003-0000-000000000001", "cc000000-0003-0003-0000-000000000002", clubMgBeilage, 0},
		{"cc000000-0009-0003-0000-000000000002", "cc000000-0003-0003-0000-000000000006", clubMgBeilage, 0},
		{"cc000000-0009-0003-0000-000000000003", "cc000000-0003-0003-0000-000000000008", clubMgBeilage, 0},
	}
	for _, l := range links {
		if err := exec(tx, `
			INSERT INTO product_modifier_groups (id, product_id, modifier_group_id, display_order)
			VALUES ($1,$2,$3,$4)
			ON CONFLICT (product_id, modifier_group_id) DO NOTHING`,
			l.id, l.productID, l.groupID, l.order,
		); err != nil {
			return fmt.Errorf("pmg %s→%s: %w", l.productID, l.groupID, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Floors (2)
// ---------------------------------------------------------------------------

func seedClubDemoFloors(tx *sql.Tx, now time.Time) error {
	floors := []struct {
		id, name string
		order    int
	}{
		{clubFloorHauptraumID, "Hauptraum", 0},
		{clubFloorWintergarten, "Wintergarten", 1},
	}
	for _, f := range floors {
		if err := exec(tx, `
			INSERT INTO floors (id, tenant_id, name, display_order, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,0,false)
			ON CONFLICT (id) DO NOTHING`,
			f.id, clubDemoTenantID, f.name, f.order, now, now,
		); err != nil {
			return fmt.Errorf("floor %s: %w", f.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Tables (12 total: 8 Hauptraum + 4 Wintergarten)
// ---------------------------------------------------------------------------

func seedClubDemoTables(tx *sql.Tx, now time.Time) error {
	type tbl struct {
		id, floorID, name, shape string
		cap                      int
		x, y, w, h               float64
	}
	tables := []tbl{
		// Hauptraum R1–R8
		{"cc000000-000a-0001-0000-000000000001", clubFloorHauptraumID, "R1", "rectangle", 4, 50, 50, 120, 80},
		{"cc000000-000a-0001-0000-000000000002", clubFloorHauptraumID, "R2", "rectangle", 4, 210, 50, 120, 80},
		{"cc000000-000a-0001-0000-000000000003", clubFloorHauptraumID, "R3", "rectangle", 2, 370, 50, 100, 70},
		{"cc000000-000a-0001-0000-000000000004", clubFloorHauptraumID, "R4", "rectangle", 6, 510, 50, 150, 90},
		{"cc000000-000a-0001-0000-000000000005", clubFloorHauptraumID, "R5", "rectangle", 4, 50, 190, 120, 80},
		{"cc000000-000a-0001-0000-000000000006", clubFloorHauptraumID, "R6", "rectangle", 2, 210, 190, 100, 70},
		{"cc000000-000a-0001-0000-000000000007", clubFloorHauptraumID, "R7", "rectangle", 8, 350, 190, 170, 100},
		{"cc000000-000a-0001-0000-000000000008", clubFloorHauptraumID, "R8", "rectangle", 4, 50, 330, 120, 80},
		// Wintergarten W1–W4
		{"cc000000-000a-0002-0000-000000000001", clubFloorWintergarten, "W1", "circle", 4, 80, 60, 110, 110},
		{"cc000000-000a-0002-0000-000000000002", clubFloorWintergarten, "W2", "rectangle", 6, 250, 60, 150, 90},
		{"cc000000-000a-0002-0000-000000000003", clubFloorWintergarten, "W3", "circle", 2, 80, 220, 90, 90},
		{"cc000000-000a-0002-0000-000000000004", clubFloorWintergarten, "W4", "rectangle", 4, 250, 220, 120, 80},
	}
	for _, t := range tables {
		if err := exec(tx, `
			INSERT INTO restaurant_tables (id, tenant_id, floor_id, name, capacity, shape, pos_x, pos_y, width, height, status, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'available',$11,$12,0,false)
			ON CONFLICT (id) DO NOTHING`,
			t.id, clubDemoTenantID, t.floorID, t.name, t.cap, t.shape,
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

func seedClubDemoTaxProfiles(tx *sql.Tx, now time.Time) error {
	type profile struct {
		id, orderType, taxGroup, name string
		rate                          float64
	}
	profiles := []profile{
		{"cc000000-000b-0001-0000-000000000001", "dine_in", "food", "MWST 8.1% (Restaurant)", 8.1},
		{"cc000000-000b-0001-0000-000000000002", "dine_in", "beverage", "MWST 8.1% (Restaurant)", 8.1},
		{"cc000000-000b-0001-0000-000000000003", "dine_in", "alcohol", "MWST 8.1% (Restaurant)", 8.1},
		{"cc000000-000b-0002-0000-000000000001", "takeaway", "food", "MWST 2.6% (Takeaway)", 2.6},
		{"cc000000-000b-0002-0000-000000000002", "takeaway", "beverage", "MWST 2.6% (Takeaway)", 2.6},
		{"cc000000-000b-0002-0000-000000000003", "takeaway", "alcohol", "MWST 8.1% (Alkohol)", 8.1},
		{"cc000000-000b-0003-0000-000000000001", "delivery", "food", "MWST 2.6% (Lieferung)", 2.6},
		{"cc000000-000b-0003-0000-000000000002", "delivery", "beverage", "MWST 2.6% (Lieferung)", 2.6},
		{"cc000000-000b-0003-0000-000000000003", "delivery", "alcohol", "MWST 8.1% (Alkohol)", 8.1},
	}
	for _, p := range profiles {
		if err := exec(tx, `
			INSERT INTO tax_profiles (id, tenant_id, country_code, order_type, product_tax_group, tax_rate, tax_name, is_default, created_at, updated_at)
			VALUES ($1,$2,'CH',$3,$4,$5,$6,false,$7,$8)
			ON CONFLICT (id) DO NOTHING`,
			p.id, clubDemoTenantID, p.orderType, p.taxGroup, p.rate, p.name, now, now,
		); err != nil {
			return fmt.Errorf("tax_profile %s/%s: %w", p.orderType, p.taxGroup, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Demo Orders (2 completed orders)
// ---------------------------------------------------------------------------

func seedClubDemoDemoOrders(tx *sql.Tx, now time.Time) error {
	yesterday := now.AddDate(0, 0, -1)
	tableR2 := "cc000000-000a-0001-0000-000000000002"
	tableW1 := "cc000000-000a-0002-0000-000000000001"

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
			ticketID: clubTicket1ID, billID: clubBill1ID, tableID: tableR2,
			orderNum: 2001, guests: 2,
			subtotal: 8800, taxAmt: 713, total: 9513,
			openedH: 19, closedH: 20, payMethod: "card", tendered: 9513,
			items: []orderItem{
				{"cc000000-000c-0001-0000-000000000001", "cc000000-0003-0003-0000-000000000001", "Zürcher Geschnetzeltes", 3850},
				{"cc000000-000c-0001-0000-000000000002", "cc000000-0003-0003-0000-000000000001", "Zürcher Geschnetzeltes", 3850},
				{"cc000000-000c-0001-0000-000000000003", "cc000000-0003-0007-0000-000000000001", "Fendant du Valais", 650},
				{"cc000000-000c-0001-0000-000000000004", "cc000000-0003-0007-0000-000000000001", "Fendant du Valais", 650},
			},
			kdsGroups: []string{"grill", "bar"}, kdsTableName: "R2",
		},
		{
			ticketID: clubTicket2ID, billID: clubBill2ID, tableID: tableW1,
			orderNum: 2002, guests: 3,
			subtotal: 7500, taxAmt: 608, total: 8108,
			openedH: 12, closedH: 13, payMethod: "cash", tendered: 8500,
			items: []orderItem{
				{"cc000000-000c-0002-0000-000000000001", "cc000000-0003-0004-0000-000000000001", "Pizza Margherita", 1850},
				{"cc000000-000c-0002-0000-000000000002", "cc000000-0003-0004-0000-000000000004", "Pizza Rustica", 2350},
				{"cc000000-000c-0002-0000-000000000003", "cc000000-0003-0005-0000-000000000002", "Tiramisu", 1250},
				{"cc000000-000c-0002-0000-000000000004", "cc000000-0003-0005-0000-000000000002", "Tiramisu", 1250},
				{"cc000000-000c-0002-0000-000000000005", "cc000000-0003-0006-0000-000000000004", "Espresso", 450},
				{"cc000000-000c-0002-0000-000000000006", "cc000000-0003-0006-0000-000000000004", "Espresso", 450},
			},
			kdsGroups: []string{"kitchen", "dessert", "bar"}, kdsTableName: "W1",
		},
	}

	for i, o := range orders {
		openedAt := yesterday.Add(time.Duration(o.openedH)*time.Hour + 10*time.Minute)
		closedAt := yesterday.Add(time.Duration(o.closedH)*time.Hour + 2*time.Minute)

		if err := exec(tx, `
			INSERT INTO tickets (id, tenant_id, order_number, order_type, table_id, waiter_id, guest_count, status, channel, subtotal, tax_amount, discount_amount, total, opened_at, closed_at, device_id, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,'dine_in',$4,$5,$6,'fully_paid','pos',$7,$8,0,$9,$10,$11,'club-demo-device-001',$12,$13,0,false)
			ON CONFLICT (id) DO NOTHING`,
			o.ticketID, clubDemoTenantID, o.orderNum, o.tableID, clubWaiter1ID, o.guests,
			o.subtotal, o.taxAmt, o.total, openedAt, closedAt, openedAt, closedAt,
		); err != nil {
			return fmt.Errorf("club ticket %d: %w", i+1, err)
		}

		for _, item := range o.items {
			taxAmt := int(float64(item.price) * 0.081)
			if err := exec(tx, `
				INSERT INTO order_items (id, tenant_id, ticket_id, product_id, product_name, quantity, unit_price, subtotal, tax_amount, discount_amount, status, sent_to_kitchen, course, created_at, updated_at, sync_status, is_deleted)
				VALUES ($1,$2,$3,$4,$5,1,$6,$7,$8,0,'served',true,1,$9,$10,0,false)
				ON CONFLICT (id) DO NOTHING`,
				item.id, clubDemoTenantID, o.ticketID, item.productID, item.productName,
				item.price, item.price, taxAmt, openedAt, openedAt,
			); err != nil {
				return fmt.Errorf("club order_item %s: %w", item.id, err)
			}
		}

		for j, group := range o.kdsGroups {
			ktID := fmt.Sprintf("cc000000-000d-%04d-0000-%012d", i+1, j+1)
			if err := exec(tx, `
				INSERT INTO kitchen_tickets (id, tenant_id, ticket_id, kitchen_table_name, order_number, printer_group, status, sent_at, started_at, completed_at, created_at, sync_status, is_deleted)
				VALUES ($1,$2,$3,$4,$5,$6,'completed',$7,$8,$9,$10,0,false)
				ON CONFLICT (id) DO NOTHING`,
				ktID, clubDemoTenantID, o.ticketID, o.kdsTableName, o.orderNum, group,
				openedAt.Add(1*time.Minute),
				openedAt.Add(5*time.Minute),
				openedAt.Add(30*time.Minute),
				openedAt.Add(1*time.Minute),
			); err != nil {
				return fmt.Errorf("club kitchen_ticket %s: %w", ktID, err)
			}
		}

		if err := exec(tx, `
			INSERT INTO bills (id, tenant_id, ticket_id, bill_number, subtotal, tax_amount, discount_amount, total, status, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,0,$7,'paid',$8,$9,0,false)
			ON CONFLICT (id) DO NOTHING`,
			o.billID, clubDemoTenantID, o.ticketID, o.orderNum, o.subtotal, o.taxAmt, o.total, closedAt, closedAt,
		); err != nil {
			return fmt.Errorf("club bill %d: %w", i+1, err)
		}

		changeAmt := o.tendered - o.total
		pymtID := fmt.Sprintf("cc000000-000e-%04d-0000-000000000001", i+1)
		if err := exec(tx, `
			INSERT INTO payments (id, tenant_id, bill_id, ticket_id, payment_method, amount, tip_amount, tendered_amount, change_amount, received_by, paid_at, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,0,$7,$8,$9,$10,$11,$12,0,false)
			ON CONFLICT (id) DO NOTHING`,
			pymtID, clubDemoTenantID, o.billID, o.ticketID, o.payMethod,
			o.total, o.tendered, changeAmt, clubWaiter1ID, closedAt, closedAt, closedAt,
		); err != nil {
			return fmt.Errorf("club payment %d: %w", i+1, err)
		}
	}
	return nil
}
