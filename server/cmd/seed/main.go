// cmd/seed: loads demo data into the GastroCore PostgreSQL database.
//
// Usage:
//
//	go run ./cmd/seed              # insert demo data if not present
//	go run ./cmd/seed --force      # wipe demo tenant and re-insert
//	go run ./cmd/seed --wipe       # remove demo data only
//
// The demo tenant is identified by its fixed UUID so the command is
// idempotent: running it twice has no extra effect unless --force is used.
//
// Environment variables:
//
//	DATABASE_URL  PostgreSQL DSN (default: postgres://gastrocore:gastrocore@localhost:5432/gastrocore?sslmode=disable)
package main

import (
	"crypto/sha256"
	"database/sql"
	"fmt"
	"log"
	"os"
	"time"

	_ "github.com/lib/pq"
)

// ---------------------------------------------------------------------------
// Fixed demo UUIDs — deterministic, never change
// ---------------------------------------------------------------------------

const (
	demoTenantID = "d0000000-0000-0000-0000-000000000001"

	// Users
	demoAdminID   = "d0000000-0001-0000-0000-000000000001"
	demoManagerID = "d0000000-0001-0000-0000-000000000002"
	demoCashierID = "d0000000-0001-0000-0000-000000000003"
	demoWaiter1ID = "d0000000-0001-0000-0000-000000000004"
	demoWaiter2ID = "d0000000-0001-0000-0000-000000000005"
	demoWaiter3ID = "d0000000-0001-0000-0000-000000000006"

	// Categories
	catVorspeisedID  = "d0000000-0002-0000-0000-000000000001"
	catHauptID       = "d0000000-0002-0000-0000-000000000002"
	catPizzaPastaID  = "d0000000-0002-0000-0000-000000000003"
	catDessertID     = "d0000000-0002-0000-0000-000000000004"
	catGetraenkeID   = "d0000000-0002-0000-0000-000000000005"

	// Products — Vorspeisen
	prodCaesarSalatID       = "d0000000-0003-0000-0000-000000000001"
	prodBruschettaID        = "d0000000-0003-0000-0000-000000000002"
	prodTagesuppeID         = "d0000000-0003-0000-0000-000000000003"
	prodGemischterVorspID   = "d0000000-0003-0000-0000-000000000004"

	// Products — Hauptspeisen
	prodZuerichGeschID      = "d0000000-0003-0000-0000-000000000005"
	prodWienerSchnitzelID   = "d0000000-0003-0000-0000-000000000006"
	prodRindsfiletID        = "d0000000-0003-0000-0000-000000000007"
	prodLachsfiletID        = "d0000000-0003-0000-0000-000000000008"
	prodCarbonara1ID        = "d0000000-0003-0000-0000-000000000009"
	prodBurgerClassicID     = "d0000000-0003-0000-0000-000000000010"

	// Products — Pizza & Pasta
	prodMargheritaID        = "d0000000-0003-0000-0000-000000000011"
	prodQuattroFormID       = "d0000000-0003-0000-0000-000000000012"
	prodProsciuttoID        = "d0000000-0003-0000-0000-000000000013"
	prodBologneseID         = "d0000000-0003-0000-0000-000000000014"

	// Products — Desserts
	prodTiramisuID          = "d0000000-0003-0000-0000-000000000015"
	prodCremeBruleeID       = "d0000000-0003-0000-0000-000000000016"
	prodSchokiFondueID      = "d0000000-0003-0000-0000-000000000017"
	prodApfelstrudelID      = "d0000000-0003-0000-0000-000000000018"

	// Products — Getränke
	prodMineralwasserID     = "d0000000-0003-0000-0000-000000000019"
	prodColaID              = "d0000000-0003-0000-0000-000000000020"
	prodHausweinID          = "d0000000-0003-0000-0000-000000000021"
	prodBierFassID          = "d0000000-0003-0000-0000-000000000022"
	prodEspressoID          = "d0000000-0003-0000-0000-000000000023"
	prodCappuccinoID        = "d0000000-0003-0000-0000-000000000024"

	// Modifier groups
	mgZutatenID     = "d0000000-0004-0000-0000-000000000001"
	mgSauceID       = "d0000000-0004-0000-0000-000000000002"
	mgGarpunktID    = "d0000000-0004-0000-0000-000000000003"
	mgGroesseID     = "d0000000-0004-0000-0000-000000000004"
	mgBeilageID     = "d0000000-0004-0000-0000-000000000005"
	mgDrinkExtraID  = "d0000000-0004-0000-0000-000000000006"
	mgSchaerfeID    = "d0000000-0004-0000-0000-000000000007"

	// Floors
	floorHauptraumID = "d0000000-0005-0000-0000-000000000001"
	floorTerasseID   = "d0000000-0005-0000-0000-000000000002"

	// Demo orders
	ticket1ID = "d0000000-0007-0000-0000-000000000001"
	ticket2ID = "d0000000-0007-0000-0000-000000000002"
	ticket3ID = "d0000000-0007-0000-0000-000000000003"
	bill1ID   = "d0000000-0008-0000-0000-000000000001"
	bill2ID   = "d0000000-0008-0000-0000-000000000002"
	bill3ID   = "d0000000-0008-0000-0000-000000000003"
)

func main() {
	force := false
	wipe := false
	for _, arg := range os.Args[1:] {
		switch arg {
		case "--force":
			force = true
		case "--wipe":
			wipe = true
		}
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://gastrocore:gastrocore@localhost:5432/gastrocore?sslmode=disable"
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatalf("open: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		log.Fatalf("ping: %v", err)
	}

	if wipe || force {
		if err := wipeDemoData(db); err != nil {
			log.Fatalf("wipe: %v", err)
		}
		fmt.Println("demo data removed")
		if wipe {
			return
		}
	}

	// Check if already seeded (any of the three known tenant IDs)
	if !force {
		var exists bool
		if err := db.QueryRow(
			"SELECT EXISTS(SELECT 1 FROM tenants WHERE id IN ($1,$2,$3))",
			demoTenantID, clubDemoTenantID, frohsinnTenantID,
		).Scan(&exists); err != nil {
			log.Fatalf("check: %v", err)
		}
		if exists {
			fmt.Println("demo data already present — use --force to re-seed")
			return
		}
	}

	if err := seedAll(db); err != nil {
		log.Fatalf("seed: %v", err)
	}
	fmt.Println("demo data seeded successfully")
}

// ---------------------------------------------------------------------------
// Wipe
// ---------------------------------------------------------------------------

func wipeDemoData(db *sql.DB) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	// Delete all known demo tenants in FK-safe order.
	for _, tid := range []string{demoTenantID, clubDemoTenantID, frohsinnTenantID} {
		for _, stmt := range []string{
			`DELETE FROM order_item_modifiers USING order_items WHERE order_item_modifiers.order_item_id = order_items.id AND order_items.tenant_id = '` + tid + `'`,
			`DELETE FROM order_items            WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM kitchen_ticket_items   USING kitchen_tickets WHERE kitchen_ticket_items.kitchen_ticket_id = kitchen_tickets.id AND kitchen_tickets.tenant_id = '` + tid + `'`,
			`DELETE FROM kitchen_tickets        WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM payments               WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM bills                  WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM tickets                WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM receipts               WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM cash_movements         WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM shifts                 WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM restaurant_tables      WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM floors                 WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM product_modifier_groups USING products WHERE product_modifier_groups.product_id = products.id AND products.tenant_id = '` + tid + `'`,
			`DELETE FROM modifiers              WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM modifier_groups        WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM products               WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM categories             WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM audit_log              WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM users                  WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM tenant_subscriptions   WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM device_registrations   WHERE tenant_id = '` + tid + `'`,
			`DELETE FROM tenants                WHERE id        = '` + tid + `'`,
		} {
			if _, err := tx.Exec(stmt); err != nil {
				tx.Rollback()
				return fmt.Errorf("wipe stmt failed (tenant %s): %w\n  SQL: %s", tid, err, stmt)
			}
		}
	}
	return tx.Commit()
}

// ---------------------------------------------------------------------------
// Seed — all tables
// ---------------------------------------------------------------------------

func seedAll(db *sql.DB) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	now := time.Now().UTC()

	steps := []func(*sql.Tx, time.Time) error{
		seedTenant,
		seedUsers,
		seedCategories,
		seedProducts,
		seedModifierGroups,
		seedModifiers,
		seedProductModifierLinks,
		seedFloors,
		seedTables,
		seedTaxProfiles,
		seedDemoOrders,
	}

	for _, fn := range steps {
		if err := fn(tx, now); err != nil {
			tx.Rollback()
			return err
		}
	}

	// Additional tenants
	if err := seedClubDemoAll(tx, now); err != nil {
		tx.Rollback()
		return err
	}
	if err := seedFrohsinnAll(tx, now); err != nil {
		tx.Rollback()
		return err
	}

	return tx.Commit()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func hashPin(pin string) string {
	sum := sha256.Sum256([]byte(pin))
	return fmt.Sprintf("%x", sum)
}

func exec(tx *sql.Tx, q string, args ...any) error {
	_, err := tx.Exec(q, args...)
	return err
}

// ---------------------------------------------------------------------------
// Tenant
// ---------------------------------------------------------------------------

func seedTenant(tx *sql.Tx, now time.Time) error {
	return exec(tx, `
		INSERT INTO tenants (id, name, address, phone, default_tax_rate, currency_code, country_code, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
		ON CONFLICT (id) DO NOTHING`,
		demoTenantID,
		"Demo Restaurant Zürich",
		"Bahnhofstrasse 42, 8001 Zürich",
		"+41 44 123 45 67",
		8.1,
		"CHF",
		"CH",
		now, now,
	)
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

func seedUsers(tx *sql.Tx, now time.Time) error {
	users := []struct {
		id, name, pin, role, avatar string
	}{
		{demoAdminID, "Klaus Wagner", "0000", "admin", "https://images.unsplash.com/photo-1566492031773-4f4e44671857?w=100&h=100&fit=crop&q=60"},
		{demoManagerID, "Max Müller", "1234", "manager", "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=100&h=100&fit=crop&q=60"},
		{demoCashierID, "Sarah Weber", "5678", "cashier", "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&h=100&fit=crop&q=60"},
		{demoWaiter1ID, "Luca Bernasconi", "9012", "waiter", "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&h=100&fit=crop&q=60"},
		{demoWaiter2ID, "Anna Fischer", "3456", "waiter", "https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&h=100&fit=crop&q=60"},
		{demoWaiter3ID, "Thomas Keller", "7890", "waiter", "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100&h=100&fit=crop&q=60"},
	}
	for _, u := range users {
		if err := exec(tx, `
			INSERT INTO users (id, tenant_id, name, pin_hash, role, avatar, is_active, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,true,$7,$8,0,false)
			ON CONFLICT (id) DO NOTHING`,
			u.id, demoTenantID, u.name, hashPin(u.pin), u.role, u.avatar, now, now,
		); err != nil {
			return fmt.Errorf("user %s: %w", u.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

func seedCategories(tx *sql.Tx, now time.Time) error {
	cats := []struct {
		id, name, icon, color string
		order                 int
	}{
		{catVorspeisedID, "Vorspeisen", "🥗", "#34C759", 0},
		{catHauptID, "Hauptspeisen", "🍖", "#FF3B30", 1},
		{catPizzaPastaID, "Pizza & Pasta", "🍕", "#FF6B35", 2},
		{catDessertID, "Desserts", "🍰", "#FF375F", 3},
		{catGetraenkeID, "Getränke", "🥤", "#4F8CFF", 4},
	}
	for _, c := range cats {
		if err := exec(tx, `
			INSERT INTO categories (id, tenant_id, name, icon, color, display_order, is_active, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,true,$7,$8,0,false)
			ON CONFLICT (id) DO NOTHING`,
			c.id, demoTenantID, c.name, c.icon, c.color, c.order, now, now,
		); err != nil {
			return fmt.Errorf("category %s: %w", c.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Products
// ---------------------------------------------------------------------------

func seedProducts(tx *sql.Tx, now time.Time) error {
	type product struct {
		id, catID, name, desc, taxGroup, printer, imagePath string
		price, prep                                         int
	}
	products := []product{
		// Vorspeisen
		{prodCaesarSalatID, catVorspeisedID, "Caesar Salat", "Römersalat, Croutons, Parmesan, Caesar-Dressing", "food", "cold", "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=400&h=300&fit=crop&q=80", 1250, 8},
		{prodBruschettaID, catVorspeisedID, "Bruschetta", "Geröstetes Brot, Tomaten, Basilikum, Knoblauch", "food", "cold", "https://images.unsplash.com/photo-1572695157366-5e585ab2b69f?w=400&h=300&fit=crop&q=80", 850, 6},
		{prodTagesuppeID, catVorspeisedID, "Tagessuppe", "Suppe des Tages mit frischem Brot", "food", "kitchen", "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&h=300&fit=crop&q=80", 700, 5},
		{prodGemischterVorspID, catVorspeisedID, "Gemischter Vorspeisenteller", "Auswahl hausgemachter kalter Vorspeisen", "food", "cold", "https://images.unsplash.com/photo-1565557623262-b51c2513a641?w=400&h=300&fit=crop&q=80", 1500, 8},
		// Hauptspeisen
		{prodZuerichGeschID, catHauptID, "Zürich Geschnetzeltes", "Kalbsgeschnetzeltes Zürcher Art, Rösti, Rahmsauce", "food", "grill", "https://images.unsplash.com/photo-1544025162-d76538661384?w=400&h=300&fit=crop&q=80", 2850, 18},
		{prodWienerSchnitzelID, catHauptID, "Wiener Schnitzel", "Paniertes Kalbsschnitzel, Kartoffelsalat, Zitrone", "food", "grill", "https://images.unsplash.com/photo-1599921841143-819065a55cc6?w=400&h=300&fit=crop&q=80", 2600, 15},
		{prodRindsfiletID, catHauptID, "Grilliertes Rindsfilet", "200g Rindsfilet vom Grill, Grillgemüse, Café-de-Paris-Butter", "food", "grill", "https://images.unsplash.com/photo-1558030006-450675393462?w=400&h=300&fit=crop&q=80", 3800, 22},
		{prodLachsfiletID, catHauptID, "Lachsfilet", "Atlantik-Lachs, Safransauce, Blattspinat, Basmati", "food", "kitchen", "https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=400&h=300&fit=crop&q=80", 3200, 18},
		{prodCarbonara1ID, catHauptID, "Pasta Carbonara", "Spaghetti, Pancetta, Eigelb, Pecorino Romano", "food", "kitchen", "https://images.unsplash.com/photo-1612874742237-6526221588e3?w=400&h=300&fit=crop&q=80", 1950, 12},
		{prodBurgerClassicID, catHauptID, "Burger Classic", "180g Rindfleisch, Cheddar, Salat, Tomate, Pommes frites", "food", "grill", "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400&h=300&fit=crop&q=80", 2200, 14},
		// Pizza & Pasta
		{prodMargheritaID, catPizzaPastaID, "Margherita", "Tomatensauce, Mozzarella, frisches Basilikum", "food", "kitchen", "https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=400&h=300&fit=crop&q=80", 1600, 10},
		{prodQuattroFormID, catPizzaPastaID, "Quattro Formaggi", "Mozzarella, Gorgonzola, Emmentaler, Parmesan", "food", "kitchen", "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400&h=300&fit=crop&q=80", 1900, 12},
		{prodProsciuttoID, catPizzaPastaID, "Prosciutto e Rucola", "Parmaschinken, Rucola, Kirschtomaten, Parmesan", "food", "kitchen", "https://images.unsplash.com/photo-1628840042765-356cda07504e?w=400&h=300&fit=crop&q=80", 2100, 12},
		{prodBologneseID, catPizzaPastaID, "Pasta Bolognese", "Pappardelle, Rindfleisch-Bolognese, Parmesan", "food", "kitchen", "https://images.unsplash.com/photo-1551183053-bf91798d9b1a?w=400&h=300&fit=crop&q=80", 1850, 15},
		// Desserts
		{prodTiramisuID, catDessertID, "Tiramisu", "Klassisches Tiramisu mit Mascarpone", "food", "dessert", "https://images.unsplash.com/photo-1571877227200-a0d98ea607e9?w=400&h=300&fit=crop&q=80", 950, 3},
		{prodCremeBruleeID, catDessertID, "Crème Brûlée", "Vanille-Crème mit karamellisierter Zuckerkruste", "food", "dessert", "https://images.unsplash.com/photo-1470324161839-ce2bb6fa6bc3?w=400&h=300&fit=crop&q=80", 850, 3},
		{prodSchokiFondueID, catDessertID, "Schokoladen-Fondue", "Schweizer Schokoladen-Fondue für 2 Personen, Früchte", "food", "dessert", "https://images.unsplash.com/photo-1548018560-c7ef2cccf51f?w=400&h=300&fit=crop&q=80", 1800, 8},
		{prodApfelstrudelID, catDessertID, "Apfelstrudel", "Hausgemachter Apfelstrudel, Vanillesauce, Zimt-Eis", "food", "dessert", "https://images.unsplash.com/photo-1621236378699-8597faf6a176?w=400&h=300&fit=crop&q=80", 900, 5},
		// Getränke
		{prodMineralwasserID, catGetraenkeID, "Mineralwasser", "Still oder Sprudel, 500ml", "beverage", "bar", "https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=400&h=300&fit=crop&q=80", 350, 0},
		{prodColaID, catGetraenkeID, "Coca-Cola", "330ml Dose", "beverage", "bar", "https://images.unsplash.com/photo-1592415486689-125cbbfcaefd?w=400&h=300&fit=crop&q=80", 450, 0},
		{prodHausweinID, catGetraenkeID, "Hauswein", "1dl Haus-Wein, Rot oder Weiss", "alcohol", "bar", "https://images.unsplash.com/photo-1510812431401-41d2bd2722f3?w=400&h=300&fit=crop&q=80", 600, 0},
		{prodBierFassID, catGetraenkeID, "Bier vom Fass", "3dl frisch vom Fass", "alcohol", "bar", "https://images.unsplash.com/photo-1535958636474-b021ee887b13?w=400&h=300&fit=crop&q=80", 550, 0},
		{prodEspressoID, catGetraenkeID, "Espresso", "Doppelter Espresso", "beverage", "bar", "https://images.unsplash.com/photo-1510591509098-f4fdc6d0ff04?w=400&h=300&fit=crop&q=80", 400, 0},
		{prodCappuccinoID, catGetraenkeID, "Cappuccino", "Mit feinem Milchschaum und Latte-Art", "beverage", "bar", "https://images.unsplash.com/photo-1572442388796-11668a67e53d?w=400&h=300&fit=crop&q=80", 550, 0},
	}

	for i, p := range products {
		costPrice := p.price * 35 / 100
		prepTime := sql.NullInt32{Int32: int32(p.prep), Valid: p.prep > 0}
		if err := exec(tx, `
			INSERT INTO products (id, tenant_id, category_id, name, description, price, cost_price, tax_group, image_path, is_active, display_order, prep_time_minutes, printer_group, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,true,$10,$11,$12,$13,$14,0,false)
			ON CONFLICT (id) DO NOTHING`,
			p.id, demoTenantID, p.catID, p.name, p.desc, p.price, costPrice,
			p.taxGroup, p.imagePath, i, prepTime, p.printer, now, now,
		); err != nil {
			return fmt.Errorf("product %s: %w", p.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Modifier Groups
// ---------------------------------------------------------------------------

func seedModifierGroups(tx *sql.Tx, now time.Time) error {
	groups := []struct {
		id, name, selType   string
		min, max, dispOrder int
		required            bool
	}{
		{mgZutatenID, "Extras", "multiple", 0, 5, 0, false},
		{mgSauceID, "Sauce", "single", 1, 1, 1, true},
		{mgGarpunktID, "Garpunkt", "single", 1, 1, 2, true},
		{mgGroesseID, "Grösse", "single", 1, 1, 3, true},
		{mgBeilageID, "Beilage", "multiple", 0, 3, 4, false},
		{mgDrinkExtraID, "Getränke Extras", "multiple", 0, 3, 5, false},
		{mgSchaerfeID, "Schärfe", "single", 0, 1, 6, false},
	}
	for _, g := range groups {
		if err := exec(tx, `
			INSERT INTO modifier_groups (id, tenant_id, name, selection_type, min_selections, max_selections, is_required, display_order, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,0,false)
			ON CONFLICT (id) DO NOTHING`,
			g.id, demoTenantID, g.name, g.selType, g.min, g.max, g.required, g.dispOrder, now, now,
		); err != nil {
			return fmt.Errorf("modifier_group %s: %w", g.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Modifiers (options)
// ---------------------------------------------------------------------------

func seedModifiers(tx *sql.Tx, now time.Time) error {
	type opt struct {
		id, groupID, name   string
		delta, order        int
		isDefault           bool
	}

	// Pre-defined option IDs
	opts := []opt{
		// Extras
		{"d0000000-0006-0001-0000-000000000001", mgZutatenID, "Käse", 250, 0, false},
		{"d0000000-0006-0001-0000-000000000002", mgZutatenID, "Speck", 300, 1, false},
		{"d0000000-0006-0001-0000-000000000003", mgZutatenID, "Ei", 150, 2, false},
		{"d0000000-0006-0001-0000-000000000004", mgZutatenID, "Avocado", 350, 3, false},
		// Sauce
		{"d0000000-0006-0002-0000-000000000001", mgSauceID, "Ketchup", 0, 0, true},
		{"d0000000-0006-0002-0000-000000000002", mgSauceID, "Mayo", 0, 1, false},
		{"d0000000-0006-0002-0000-000000000003", mgSauceID, "Senf", 0, 2, false},
		{"d0000000-0006-0002-0000-000000000004", mgSauceID, "BBQ", 0, 3, false},
		// Garpunkt
		{"d0000000-0006-0003-0000-000000000001", mgGarpunktID, "Rare (blutig)", 0, 0, false},
		{"d0000000-0006-0003-0000-000000000002", mgGarpunktID, "Medium", 0, 1, true},
		{"d0000000-0006-0003-0000-000000000003", mgGarpunktID, "Well Done", 0, 2, false},
		// Grösse
		{"d0000000-0006-0004-0000-000000000001", mgGroesseID, "Klein", 0, 0, true},
		{"d0000000-0006-0004-0000-000000000002", mgGroesseID, "Normal", 200, 1, false},
		{"d0000000-0006-0004-0000-000000000003", mgGroesseID, "Gross", 400, 2, false},
		// Beilage
		{"d0000000-0006-0005-0000-000000000001", mgBeilageID, "Pommes frites", 450, 0, false},
		{"d0000000-0006-0005-0000-000000000002", mgBeilageID, "Salat", 350, 1, false},
		{"d0000000-0006-0005-0000-000000000003", mgBeilageID, "Reis", 300, 2, false},
		{"d0000000-0006-0005-0000-000000000004", mgBeilageID, "Suppe", 400, 3, false},
		// Getränke Extras
		{"d0000000-0006-0006-0000-000000000001", mgDrinkExtraID, "Mit Eis", 0, 0, false},
		{"d0000000-0006-0006-0000-000000000002", mgDrinkExtraID, "Ohne Eis", 0, 1, false},
		{"d0000000-0006-0006-0000-000000000003", mgDrinkExtraID, "Extra Shot", 100, 2, false},
		// Schärfe
		{"d0000000-0006-0007-0000-000000000001", mgSchaerfeID, "Mild", 0, 0, true},
		{"d0000000-0006-0007-0000-000000000002", mgSchaerfeID, "Medium", 0, 1, false},
		{"d0000000-0006-0007-0000-000000000003", mgSchaerfeID, "Scharf", 0, 2, false},
	}

	for _, o := range opts {
		if err := exec(tx, `
			INSERT INTO modifiers (id, tenant_id, group_id, name, price_delta, is_default, display_order, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,0,false)
			ON CONFLICT (id) DO NOTHING`,
			o.id, demoTenantID, o.groupID, o.name, o.delta, o.isDefault, o.order, now, now,
		); err != nil {
			return fmt.Errorf("modifier %s: %w", o.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Product–Modifier Links
// ---------------------------------------------------------------------------

func seedProductModifierLinks(tx *sql.Tx, now time.Time) error {
	type link struct {
		id, productID, groupID string
		order                  int
	}

	links := []link{
		// Burger Classic → Garpunkt + Extras + Sauce + Schärfe + Beilage
		{"d0000000-0009-0001-0000-000000000001", prodBurgerClassicID, mgGarpunktID, 0},
		{"d0000000-0009-0001-0000-000000000002", prodBurgerClassicID, mgZutatenID, 1},
		{"d0000000-0009-0001-0000-000000000003", prodBurgerClassicID, mgSauceID, 2},
		{"d0000000-0009-0001-0000-000000000005", prodBurgerClassicID, mgSchaerfeID, 3},
		{"d0000000-0009-0001-0000-000000000004", prodBurgerClassicID, mgBeilageID, 4},
		// Zürich Geschnetzeltes → Garpunkt + Beilage
		{"d0000000-0009-0002-0000-000000000001", prodZuerichGeschID, mgGarpunktID, 0},
		{"d0000000-0009-0002-0000-000000000002", prodZuerichGeschID, mgBeilageID, 1},
		// Wiener Schnitzel → Garpunkt + Beilage
		{"d0000000-0009-0003-0000-000000000001", prodWienerSchnitzelID, mgGarpunktID, 0},
		{"d0000000-0009-0003-0000-000000000002", prodWienerSchnitzelID, mgBeilageID, 1},
		// Grilliertes Rindsfilet → Garpunkt + Beilage
		{"d0000000-0009-0004-0000-000000000001", prodRindsfiletID, mgGarpunktID, 0},
		{"d0000000-0009-0004-0000-000000000002", prodRindsfiletID, mgBeilageID, 1},
		// Lachsfilet + Carbonara → Beilage
		{"d0000000-0009-0005-0000-000000000001", prodLachsfiletID, mgBeilageID, 0},
		{"d0000000-0009-0005-0000-000000000002", prodCarbonara1ID, mgBeilageID, 0},
		// Pizzen → Extras + Schärfe
		{"d0000000-0009-0006-0000-000000000001", prodMargheritaID, mgZutatenID, 0},
		{"d0000000-0009-0006-0000-000000000007", prodMargheritaID, mgSchaerfeID, 1},
		{"d0000000-0009-0006-0000-000000000002", prodQuattroFormID, mgZutatenID, 0},
		{"d0000000-0009-0006-0000-000000000008", prodQuattroFormID, mgSchaerfeID, 1},
		{"d0000000-0009-0006-0000-000000000003", prodProsciuttoID, mgZutatenID, 0},
		{"d0000000-0009-0006-0000-000000000009", prodProsciuttoID, mgSchaerfeID, 1},
		// Pasta Bolognese → Beilage
		{"d0000000-0009-0006-0000-000000000004", prodBologneseID, mgBeilageID, 0},
		// Getränke → Grösse + Getränke Extras
		{"d0000000-0009-0007-0000-000000000001", prodMineralwasserID, mgGroesseID, 0},
		{"d0000000-0009-0007-0000-000000000007", prodMineralwasserID, mgDrinkExtraID, 1},
		{"d0000000-0009-0007-0000-000000000002", prodColaID, mgGroesseID, 0},
		{"d0000000-0009-0007-0000-000000000008", prodColaID, mgDrinkExtraID, 1},
		{"d0000000-0009-0007-0000-000000000003", prodHausweinID, mgGroesseID, 0},
		{"d0000000-0009-0007-0000-000000000009", prodHausweinID, mgDrinkExtraID, 1},
		{"d0000000-0009-0007-0000-000000000004", prodBierFassID, mgGroesseID, 0},
		{"d0000000-0009-0007-0000-000000000010", prodBierFassID, mgDrinkExtraID, 1},
		{"d0000000-0009-0007-0000-000000000005", prodEspressoID, mgGroesseID, 0},
		{"d0000000-0009-0007-0000-000000000011", prodEspressoID, mgDrinkExtraID, 1},
		{"d0000000-0009-0007-0000-000000000006", prodCappuccinoID, mgGroesseID, 0},
		{"d0000000-0009-0007-0000-000000000012", prodCappuccinoID, mgDrinkExtraID, 1},
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
// Floors
// ---------------------------------------------------------------------------

func seedFloors(tx *sql.Tx, now time.Time) error {
	floors := []struct {
		id, name string
		order    int
	}{
		{floorHauptraumID, "Hauptraum", 0},
		{floorTerasseID, "Terrasse", 1},
	}
	for _, f := range floors {
		if err := exec(tx, `
			INSERT INTO floors (id, tenant_id, name, display_order, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,0,false)
			ON CONFLICT (id) DO NOTHING`,
			f.id, demoTenantID, f.name, f.order, now, now,
		); err != nil {
			return fmt.Errorf("floor %s: %w", f.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

func seedTables(tx *sql.Tx, now time.Time) error {
	type tbl struct {
		id, floorID, name, shape string
		cap                      int
		x, y, w, h               float64
	}

	tables := []tbl{
		// Hauptraum M1–M10
		{"d0000000-000a-0001-0000-000000000001", floorHauptraumID, "M1", "rectangle", 4, 50, 50, 120, 80},
		{"d0000000-000a-0001-0000-000000000002", floorHauptraumID, "M2", "rectangle", 4, 200, 50, 120, 80},
		{"d0000000-000a-0001-0000-000000000003", floorHauptraumID, "M3", "rectangle", 2, 350, 50, 100, 70},
		{"d0000000-000a-0001-0000-000000000004", floorHauptraumID, "M4", "rectangle", 6, 500, 50, 140, 90},
		{"d0000000-000a-0001-0000-000000000005", floorHauptraumID, "M5", "rectangle", 4, 50, 180, 120, 80},
		{"d0000000-000a-0001-0000-000000000006", floorHauptraumID, "M6", "rectangle", 2, 200, 180, 100, 70},
		{"d0000000-000a-0001-0000-000000000007", floorHauptraumID, "M7", "rectangle", 4, 350, 180, 120, 80},
		{"d0000000-000a-0001-0000-000000000008", floorHauptraumID, "M8", "rectangle", 8, 500, 180, 160, 100},
		{"d0000000-000a-0001-0000-000000000009", floorHauptraumID, "M9", "rectangle", 4, 50, 320, 120, 80},
		{"d0000000-000a-0001-0000-000000000010", floorHauptraumID, "M10", "rectangle", 2, 200, 320, 100, 70},
		// Terrasse T1–T5
		{"d0000000-000a-0002-0000-000000000001", floorTerasseID, "T1", "circle", 4, 80, 60, 100, 100},
		{"d0000000-000a-0002-0000-000000000002", floorTerasseID, "T2", "rectangle", 6, 240, 60, 140, 90},
		{"d0000000-000a-0002-0000-000000000003", floorTerasseID, "T3", "circle", 2, 80, 200, 90, 90},
		{"d0000000-000a-0002-0000-000000000004", floorTerasseID, "T4", "square", 4, 240, 200, 110, 110},
		{"d0000000-000a-0002-0000-000000000005", floorTerasseID, "T5", "rectangle", 8, 400, 60, 160, 100},
	}

	for _, t := range tables {
		if err := exec(tx, `
			INSERT INTO restaurant_tables (id, tenant_id, floor_id, name, capacity, shape, pos_x, pos_y, width, height, status, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'available',$11,$12,0,false)
			ON CONFLICT (id) DO NOTHING`,
			t.id, demoTenantID, t.floorID, t.name, t.cap, t.shape,
			t.x, t.y, t.w, t.h, now, now,
		); err != nil {
			return fmt.Errorf("table %s: %w", t.name, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Tax Profiles
// ---------------------------------------------------------------------------

func seedTaxProfiles(tx *sql.Tx, now time.Time) error {
	type profile struct {
		id, orderType, taxGroup, name string
		rate                          float64
	}

	profiles := []profile{
		// Dine-in 8.1%
		{"d0000000-000b-0001-0000-000000000001", "dine_in", "food", "MWST 8.1% (Restaurant)", 8.1},
		{"d0000000-000b-0001-0000-000000000002", "dine_in", "beverage", "MWST 8.1% (Restaurant)", 8.1},
		{"d0000000-000b-0001-0000-000000000003", "dine_in", "alcohol", "MWST 8.1% (Restaurant)", 8.1},
		// Takeaway 2.6% / 8.1%
		{"d0000000-000b-0002-0000-000000000001", "takeaway", "food", "MWST 2.6% (Takeaway)", 2.6},
		{"d0000000-000b-0002-0000-000000000002", "takeaway", "beverage", "MWST 2.6% (Takeaway)", 2.6},
		{"d0000000-000b-0002-0000-000000000003", "takeaway", "alcohol", "MWST 8.1% (Alkohol)", 8.1},
		// Delivery 2.6% / 8.1%
		{"d0000000-000b-0003-0000-000000000001", "delivery", "food", "MWST 2.6% (Lieferung)", 2.6},
		{"d0000000-000b-0003-0000-000000000002", "delivery", "beverage", "MWST 2.6% (Lieferung)", 2.6},
		{"d0000000-000b-0003-0000-000000000003", "delivery", "alcohol", "MWST 8.1% (Alkohol)", 8.1},
		// Accommodation 3.8%
		{"d0000000-000b-0004-0000-000000000001", "accommodation", "food", "MWST 3.8% (Beherbergung)", 3.8},
		{"d0000000-000b-0004-0000-000000000002", "accommodation", "beverage", "MWST 3.8% (Beherbergung)", 3.8},
		{"d0000000-000b-0004-0000-000000000003", "accommodation", "alcohol", "MWST 3.8% (Beherbergung)", 3.8},
	}

	for _, p := range profiles {
		if err := exec(tx, `
			INSERT INTO tax_profiles (id, tenant_id, country_code, order_type, product_tax_group, tax_rate, tax_name, is_default, created_at, updated_at)
			VALUES ($1,$2,'CH',$3,$4,$5,$6,false,$7,$8)
			ON CONFLICT (id) DO NOTHING`,
			p.id, demoTenantID, p.orderType, p.taxGroup, p.rate, p.name, now, now,
		); err != nil {
			return fmt.Errorf("tax_profile %s/%s: %w", p.orderType, p.taxGroup, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// Demo Orders — 3 abgeschlossene Bestellungen
// ---------------------------------------------------------------------------

func seedDemoOrders(tx *sql.Tx, now time.Time) error {
	yesterday := now.AddDate(0, 0, -1)
	tableM2ID := "d0000000-000a-0001-0000-000000000002"
	tableT1ID := "d0000000-000a-0002-0000-000000000001"
	tableM7ID := "d0000000-000a-0001-0000-000000000007"

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
			ticketID: ticket1ID, billID: bill1ID, tableID: tableM2ID,
			orderNum: 1001, guests: 2,
			subtotal: 6900, taxAmt: 559, total: 7459,
			openedH: 12, closedH: 13, payMethod: "cash", tendered: 8000,
			items: []orderItem{
				{"d0000000-000c-0001-0000-000000000001", prodZuerichGeschID, "Zürich Geschnetzeltes", 2850},
				{"d0000000-000c-0001-0000-000000000002", prodZuerichGeschID, "Zürich Geschnetzeltes", 2850},
				{"d0000000-000c-0001-0000-000000000003", prodHausweinID, "Hauswein", 600},
				{"d0000000-000c-0001-0000-000000000004", prodHausweinID, "Hauswein", 600},
			},
			kdsGroups: []string{"grill", "bar"}, kdsTableName: "M2",
		},
		{
			ticketID: ticket2ID, billID: bill2ID, tableID: tableT1ID,
			orderNum: 1002, guests: 3,
			subtotal: 4850, taxAmt: 393, total: 5243,
			openedH: 19, closedH: 20, payMethod: "card", tendered: 5243,
			items: []orderItem{
				{"d0000000-000c-0002-0000-000000000001", prodMargheritaID, "Margherita", 1600},
				{"d0000000-000c-0002-0000-000000000002", prodMargheritaID, "Margherita", 1600},
				{"d0000000-000c-0002-0000-000000000003", prodCappuccinoID, "Cappuccino", 550},
				{"d0000000-000c-0002-0000-000000000004", prodCappuccinoID, "Cappuccino", 550},
				{"d0000000-000c-0002-0000-000000000005", prodCappuccinoID, "Cappuccino", 550},
			},
			kdsGroups: []string{"kitchen", "bar"}, kdsTableName: "T1",
		},
		{
			ticketID: ticket3ID, billID: bill3ID, tableID: tableM7ID,
			orderNum: 1003, guests: 2,
			subtotal: 6450, taxAmt: 522, total: 6972,
			openedH: 20, closedH: 21, payMethod: "twint", tendered: 6972,
			items: []orderItem{
				{"d0000000-000c-0003-0000-000000000001", prodWienerSchnitzelID, "Wiener Schnitzel", 2600},
				{"d0000000-000c-0003-0000-000000000002", prodCaesarSalatID, "Caesar Salat", 1250},
				{"d0000000-000c-0003-0000-000000000003", prodTiramisuID, "Tiramisu", 950},
				{"d0000000-000c-0003-0000-000000000004", prodTiramisuID, "Tiramisu", 950},
				{"d0000000-000c-0003-0000-000000000005", prodMineralwasserID, "Mineralwasser", 350},
				{"d0000000-000c-0003-0000-000000000006", prodMineralwasserID, "Mineralwasser", 350},
			},
			kdsGroups: []string{"grill", "cold", "dessert"}, kdsTableName: "M7",
		},
	}

	for i, o := range orders {
		openedAt := yesterday.Add(time.Duration(o.openedH)*time.Hour + 15*time.Minute)
		closedAt := yesterday.Add(time.Duration(o.closedH)*time.Hour + 5*time.Minute)

		// Ticket
		if err := exec(tx, `
			INSERT INTO tickets (id, tenant_id, order_number, order_type, table_id, waiter_id, guest_count, status, channel, subtotal, tax_amount, discount_amount, total, opened_at, closed_at, device_id, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,'dine_in',$4,$5,$6,'fully_paid','pos',$7,$8,0,$9,$10,$11,'demo-device-001',$12,$13,0,false)
			ON CONFLICT (id) DO NOTHING`,
			o.ticketID, demoTenantID, o.orderNum, o.tableID, demoWaiter1ID, o.guests,
			o.subtotal, o.taxAmt, o.total, openedAt, closedAt, openedAt, closedAt,
		); err != nil {
			return fmt.Errorf("ticket %d: %w", i+1, err)
		}

		// Order items
		for _, item := range o.items {
			taxAmt := int(float64(item.price) * 0.081)
			if err := exec(tx, `
				INSERT INTO order_items (id, tenant_id, ticket_id, product_id, product_name, quantity, unit_price, subtotal, tax_amount, discount_amount, status, sent_to_kitchen, course, created_at, updated_at, sync_status, is_deleted)
				VALUES ($1,$2,$3,$4,$5,1,$6,$7,$8,0,'served',true,1,$9,$10,0,false)
				ON CONFLICT (id) DO NOTHING`,
				item.id, demoTenantID, o.ticketID, item.productID, item.productName,
				item.price, item.price, taxAmt, openedAt, openedAt,
			); err != nil {
				return fmt.Errorf("order_item %s: %w", item.id, err)
			}
		}

		// KDS tickets
		for j, group := range o.kdsGroups {
			ktID := fmt.Sprintf("d0000000-000d-%04d-0000-%012d", i+1, j+1)
			if err := exec(tx, `
				INSERT INTO kitchen_tickets (id, tenant_id, ticket_id, kitchen_table_name, order_number, printer_group, status, sent_at, started_at, completed_at, created_at, sync_status, is_deleted)
				VALUES ($1,$2,$3,$4,$5,$6,'completed',$7,$8,$9,$10,0,false)
				ON CONFLICT (id) DO NOTHING`,
				ktID, demoTenantID, o.ticketID, o.kdsTableName, o.orderNum, group,
				openedAt.Add(1*time.Minute),
				openedAt.Add(5*time.Minute),
				openedAt.Add(35*time.Minute),
				openedAt.Add(1*time.Minute),
			); err != nil {
				return fmt.Errorf("kitchen_ticket %s: %w", ktID, err)
			}
		}

		// Bill
		if err := exec(tx, `
			INSERT INTO bills (id, tenant_id, ticket_id, bill_number, subtotal, tax_amount, discount_amount, total, status, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,0,$7,'paid',$8,$9,0,false)
			ON CONFLICT (id) DO NOTHING`,
			o.billID, demoTenantID, o.ticketID, o.orderNum, o.subtotal, o.taxAmt, o.total, closedAt, closedAt,
		); err != nil {
			return fmt.Errorf("bill %d: %w", i+1, err)
		}

		// Payment
		changeAmt := o.tendered - o.total
		pymtID := fmt.Sprintf("d0000000-000e-%04d-0000-000000000001", i+1)
		if err := exec(tx, `
			INSERT INTO payments (id, tenant_id, bill_id, ticket_id, payment_method, amount, tip_amount, tendered_amount, change_amount, received_by, paid_at, created_at, updated_at, sync_status, is_deleted)
			VALUES ($1,$2,$3,$4,$5,$6,0,$7,$8,$9,$10,$11,$12,0,false)
			ON CONFLICT (id) DO NOTHING`,
			pymtID, demoTenantID, o.billID, o.ticketID, o.payMethod,
			o.total, o.tendered, changeAmt, demoCashierID, closedAt, closedAt, closedAt,
		); err != nil {
			return fmt.Errorf("payment %d: %w", i+1, err)
		}
	}
	return nil
}
