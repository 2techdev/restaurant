/// Seed data for the GastroCore POS demo restaurant.
///
/// Populates the database with a complete Swiss-style restaurant demo dataset
/// on first launch: tenant, staff, categories, products, modifier groups,
/// modifiers, product-modifier links, floors, tables, tax profiles, and
/// sample order history.
///
/// Call [seedIfEmpty] at app start — it is a no-op when data already exists.
/// Call [seedForce] to re-insert (e.g. from settings "Load demo data" button).
/// Call [clearAll] to wipe all tenant-scoped data (settings "Clear demo data").
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';

/// Populates the database with realistic Swiss restaurant demo data.
///
/// Demo Restaurant: "Demo Restaurant Zürich"
/// Address:         Bahnhofstrasse 42, 8001 Zürich
/// Currency:        CHF
/// MWST rates:      2.6% (takeaway/delivery food), 3.8% (accommodation),
///                  8.1% (dine-in / standard)
/// KDS stations:    Grill · Cold · Dessert · Bar
class SeedData {
  final AppDatabase db;

  SeedData(this.db);

  // -------------------------------------------------------------------------
  // Well-known IDs used across seed methods
  // -------------------------------------------------------------------------

  String _tenantId = '';

  // Category IDs
  String _catVorspeisedId = '';
  String _catHauptId = '';
  String _catPizzaPastaId = '';
  String _catDessertId = '';
  String _catGetraenkeId = '';

  // User IDs needed for demo orders
  String _cashierId = '';
  final List<String> _waiterIds = [];

  // Modifier group IDs
  String _mgZutatenId = '';
  String _mgSauceId = '';
  String _mgGarpunktId = '';
  String _mgGroesseId = '';
  String _mgBeilageId = '';

  // Product ID buckets for modifier linking & demo orders
  final List<String> _grillIds = [];
  final List<String> _pizzaIds = [];
  final List<String> _drinkIds = [];
  final List<String> _mainIds = [];
  String? _burgerId;

  // Products used in demo orders
  String _prodZuerichGeschId = '';
  String _prodWienerSchnitzelId = '';
  String _prodMargheritaId = '';
  String _prodCaesarSalatId = '';
  String _prodTiramisuId = '';
  String _prodCappuccinoId = '';
  String _prodMineralwasserId = '';
  String _prodHausweinId = '';

  // Table IDs used in demo orders
  String _tableM2Id = '';
  String _tableT1Id = '';
  String _tableM7Id = '';

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Inserts demo data only when the database is empty (no tenants).
  Future<void> seedIfEmpty() async {
    final existing = await db.select(db.tenants).get();
    if (existing.isNotEmpty) return;
    await _seed();
  }

  /// Always inserts demo data (clears existing first). Used from settings UI.
  Future<void> seedForce() async {
    await clearAll();
    await _seed();
  }

  /// Deletes all data for the current tenant (soft-delete aware).
  /// Cascades through all tables that carry a tenantId foreign key.
  Future<void> clearAll() async {
    await db.transaction(() async {
      // Children before parents to respect FK constraints.
      await db.delete(db.orderItemModifiers).go();
      await db.delete(db.orderItems).go();
      await db.delete(db.kitchenTicketItems).go();
      await db.delete(db.kitchenTickets).go();
      await db.delete(db.payments).go();
      await db.delete(db.bills).go();
      await db.delete(db.tickets).go();
      await db.delete(db.receipts).go();
      await db.delete(db.cashMovements).go();
      await db.delete(db.shifts).go();
      await db.delete(db.restaurantTables).go();
      await db.delete(db.floors).go();
      await db.delete(db.productModifierGroups).go();
      await db.delete(db.comboItems).go();
      await db.delete(db.productSpecifications).go();
      await db.delete(db.productPrices).go();
      await db.delete(db.modifiers).go();
      await db.delete(db.modifierGroups).go();
      await db.delete(db.products).go();
      await db.delete(db.categories).go();
      await db.delete(db.taxProfiles).go();
      await db.delete(db.orderTypeRules).go();
      await db.delete(db.syncQueue).go();
      await db.delete(db.syncMetadata).go();
      await db.delete(db.auditLog).go();
      await db.delete(db.users).go();
      await db.delete(db.tenants).go();
    });
  }

  // -------------------------------------------------------------------------
  // Internal orchestration
  // -------------------------------------------------------------------------

  Future<void> _seed() async {
    await _seedTenant();
    await _seedUsers();
    await _seedCategories();
    await _seedProducts();
    await _seedModifiers();
    await _seedFloors();
    await _seedTables();
    await _seedTaxProfiles();
    await _seedDemoOrders();
  }

  // -------------------------------------------------------------------------
  // PIN helper
  // -------------------------------------------------------------------------

  /// SHA-256 hash for PIN codes.
  static String hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

  // -------------------------------------------------------------------------
  // Tenant
  // -------------------------------------------------------------------------

  Future<void> _seedTenant() async {
    _tenantId = IdGenerator.generateId();
    final now = DateTime.now();
    await db.into(db.tenants).insert(
      TenantsCompanion(
        id: Value(_tenantId),
        name: const Value('Demo Restaurant Zürich'),
        address: const Value('Bahnhofstrasse 42, 8001 Zürich'),
        phone: const Value('+41 44 123 45 67'),
        defaultTaxRate: const Value(8.1),
        currencyCode: const Value('CHF'),
        countryCode: const Value('CH'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Staff / Users
  // -------------------------------------------------------------------------

  Future<void> _seedUsers() async {
    final now = DateTime.now();

    // (name, pin, role, avatarAsset)
    final staff = [
      (
        name: 'Klaus Wagner',
        pin: '0000',
        role: 'admin',
        avatar: 'assets/images/staff/default.svg',
      ),
      (
        name: 'Max Müller',
        pin: '1234',
        role: 'manager',
        avatar: 'assets/images/staff/max_mueller.svg',
      ),
      (
        name: 'Sarah Weber',
        pin: '5678',
        role: 'cashier',
        avatar: 'assets/images/staff/sarah_weber.svg',
      ),
      (
        name: 'Luca Bernasconi',
        pin: '9012',
        role: 'waiter',
        avatar: 'assets/images/staff/luca_bernasconi.svg',
      ),
      (
        name: 'Anna Fischer',
        pin: '3456',
        role: 'waiter',
        avatar: 'assets/images/staff/anna_fischer.svg',
      ),
      (
        name: 'Thomas Keller',
        pin: '7890',
        role: 'waiter',
        avatar: 'assets/images/staff/thomas_keller.svg',
      ),
    ];

    for (final s in staff) {
      final id = IdGenerator.generateId();
      if (s.role == 'cashier') _cashierId = id;
      if (s.role == 'waiter') _waiterIds.add(id);

      await db.into(db.users).insert(
        UsersCompanion(
          id: Value(id),
          tenantId: Value(_tenantId),
          name: Value(s.name),
          pinHash: Value(hashPin(s.pin)),
          role: Value(s.role),
          avatarPath: Value(s.avatar),
          isActive: const Value(true),
          createdAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Categories
  // -------------------------------------------------------------------------

  Future<void> _seedCategories() async {
    final now = DateTime.now();

    _catVorspeisedId = IdGenerator.generateId();
    _catHauptId = IdGenerator.generateId();
    _catPizzaPastaId = IdGenerator.generateId();
    _catDessertId = IdGenerator.generateId();
    _catGetraenkeId = IdGenerator.generateId();

    final cats = [
      (
        id: _catVorspeisedId,
        name: 'Vorspeisen',
        icon: '\uD83E\uDD57', // 🥗
        color: '#34C759',
        order: 0,
      ),
      (
        id: _catHauptId,
        name: 'Hauptspeisen',
        icon: '\uD83C\uDF56', // 🍖
        color: '#FF3B30',
        order: 1,
      ),
      (
        id: _catPizzaPastaId,
        name: 'Pizza & Pasta',
        icon: '\uD83C\uDF55', // 🍕
        color: '#FF6B35',
        order: 2,
      ),
      (
        id: _catDessertId,
        name: 'Desserts',
        icon: '\uD83C\uDF70', // 🍰
        color: '#FF375F',
        order: 3,
      ),
      (
        id: _catGetraenkeId,
        name: 'Getränke',
        icon: '\uD83E\uDD64', // 🥤
        color: '#4F8CFF',
        order: 4,
      ),
    ];

    for (final c in cats) {
      await db.into(db.categories).insert(
        CategoriesCompanion(
          id: Value(c.id),
          tenantId: Value(_tenantId),
          name: Value(c.name),
          icon: Value(c.icon),
          color: Value(c.color),
          displayOrder: Value(c.order),
          isActive: const Value(true),
          createdAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Products
  // -------------------------------------------------------------------------

  Future<void> _seedProducts() async {
    final now = DateTime.now();
    var order = 0;

    Future<String> add({
      required String catId,
      required String name,
      required int price, // rappen (CHF cents)
      String? description,
      String taxGroup = 'food',
      String printerGroup = 'kitchen',
      int? prepTime,
      String? imagePath,
    }) async {
      final id = IdGenerator.generateId();
      await db.into(db.products).insert(
        ProductsCompanion(
          id: Value(id),
          tenantId: Value(_tenantId),
          categoryId: Value(catId),
          name: Value(name),
          description: Value(description),
          price: Value(price),
          costPrice: Value((price * 0.35).round()),
          taxGroup: Value(taxGroup),
          imagePath: Value(imagePath),
          isActive: const Value(true),
          displayOrder: Value(order++),
          prepTimeMinutes: Value(prepTime),
          printerGroup: Value(printerGroup),
          createdAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
      return id;
    }

    // -- Vorspeisen --
    _prodCaesarSalatId = await add(
      catId: _catVorspeisedId,
      name: 'Caesar Salat',
      price: 1250,
      description: 'Römersalat, Croutons, Parmesan, Caesar-Dressing',
      prepTime: 8,
      printerGroup: 'cold',
      imagePath: 'assets/images/products/starter.svg',
    );
    await add(
      catId: _catVorspeisedId,
      name: 'Bruschetta',
      price: 850,
      description: 'Geröstetes Brot, Tomaten, Basilikum, Knoblauch',
      prepTime: 6,
      printerGroup: 'cold',
      imagePath: 'assets/images/products/starter.svg',
    );
    await add(
      catId: _catVorspeisedId,
      name: 'Tagessuppe',
      price: 700,
      description: 'Suppe des Tages mit frischem Brot',
      prepTime: 5,
      printerGroup: 'kitchen',
      imagePath: 'assets/images/products/starter.svg',
    );
    await add(
      catId: _catVorspeisedId,
      name: 'Gemischter Vorspeisenteller',
      price: 1500,
      description: 'Auswahl hausgemachter kalter Vorspeisen',
      prepTime: 8,
      printerGroup: 'cold',
      imagePath: 'assets/images/products/starter.svg',
    );

    // -- Hauptspeisen --
    _prodZuerichGeschId = await add(
      catId: _catHauptId,
      name: 'Zürich Geschnetzeltes',
      price: 2850,
      description: 'Kalbsgeschnetzeltes Zürcher Art, Rösti, Rahmsauce',
      prepTime: 18,
      printerGroup: 'grill',
      imagePath: 'assets/images/products/main_course.svg',
    );
    _grillIds.add(_prodZuerichGeschId);
    _mainIds.add(_prodZuerichGeschId);

    _prodWienerSchnitzelId = await add(
      catId: _catHauptId,
      name: 'Wiener Schnitzel',
      price: 2600,
      description: 'Paniertes Kalbsschnitzel, Kartoffelsalat, Zitrone',
      prepTime: 15,
      printerGroup: 'grill',
      imagePath: 'assets/images/products/main_course.svg',
    );
    _grillIds.add(_prodWienerSchnitzelId);
    _mainIds.add(_prodWienerSchnitzelId);

    final rindsfiletId = await add(
      catId: _catHauptId,
      name: 'Grilliertes Rindsfilet',
      price: 3800,
      description: '200g Rindsfilet vom Grill, Grillgemüse, Café-de-Paris-Butter',
      prepTime: 22,
      printerGroup: 'grill',
      imagePath: 'assets/images/products/main_course.svg',
    );
    _grillIds.add(rindsfiletId);
    _mainIds.add(rindsfiletId);

    final lachsId = await add(
      catId: _catHauptId,
      name: 'Lachsfilet',
      price: 3200,
      description: 'Atlantik-Lachs, Safransauce, Blattspinat, Basmati',
      prepTime: 18,
      printerGroup: 'kitchen',
      imagePath: 'assets/images/products/main_course.svg',
    );
    _mainIds.add(lachsId);

    final carbonaraId = await add(
      catId: _catHauptId,
      name: 'Pasta Carbonara',
      price: 1950,
      description: 'Spaghetti, Pancetta, Eigelb, Pecorino Romano',
      prepTime: 12,
      printerGroup: 'kitchen',
      imagePath: 'assets/images/products/main_course.svg',
    );
    _mainIds.add(carbonaraId);

    _burgerId = await add(
      catId: _catHauptId,
      name: 'Burger Classic',
      price: 2200,
      description: '180g Rindfleisch, Cheddar, Salat, Tomate, Pommes frites',
      prepTime: 14,
      printerGroup: 'grill',
      imagePath: 'assets/images/products/main_course.svg',
    );
    _grillIds.add(_burgerId!);
    _mainIds.add(_burgerId!);

    // -- Pizza & Pasta --
    _prodMargheritaId = await add(
      catId: _catPizzaPastaId,
      name: 'Margherita',
      price: 1600,
      description: 'Tomatensauce, Mozzarella, frisches Basilikum',
      prepTime: 10,
      printerGroup: 'kitchen',
      imagePath: 'assets/images/products/pizza.svg',
    );
    _pizzaIds.add(_prodMargheritaId);

    final quattroId = await add(
      catId: _catPizzaPastaId,
      name: 'Quattro Formaggi',
      price: 1900,
      description: 'Vier Käse: Mozzarella, Gorgonzola, Emmentaler, Parmesan',
      prepTime: 12,
      printerGroup: 'kitchen',
      imagePath: 'assets/images/products/pizza.svg',
    );
    _pizzaIds.add(quattroId);

    final prosciuttoId = await add(
      catId: _catPizzaPastaId,
      name: 'Prosciutto e Rucola',
      price: 2100,
      description: 'Parmaschinken, Rucola, Kirschtomaten, Parmesan',
      prepTime: 12,
      printerGroup: 'kitchen',
      imagePath: 'assets/images/products/pizza.svg',
    );
    _pizzaIds.add(prosciuttoId);

    await add(
      catId: _catPizzaPastaId,
      name: 'Pasta Bolognese',
      price: 1850,
      description: 'Pappardelle, Rindfleisch-Bolognese, Parmesan',
      prepTime: 15,
      printerGroup: 'kitchen',
      imagePath: 'assets/images/products/main_course.svg',
    );

    // -- Desserts --
    _prodTiramisuId = await add(
      catId: _catDessertId,
      name: 'Tiramisu',
      price: 950,
      description: 'Klassisches Tiramisu mit Mascarpone',
      prepTime: 3,
      printerGroup: 'dessert',
      imagePath: 'assets/images/products/dessert.svg',
    );
    await add(
      catId: _catDessertId,
      name: 'Crème Brûlée',
      price: 850,
      description: 'Vanille-Crème mit karamellisierter Zuckerkruste',
      prepTime: 3,
      printerGroup: 'dessert',
      imagePath: 'assets/images/products/dessert.svg',
    );
    await add(
      catId: _catDessertId,
      name: 'Schokoladen-Fondue',
      price: 1800,
      description: 'Schweizer Schokoladen-Fondue für 2 Personen, Früchte',
      prepTime: 8,
      printerGroup: 'dessert',
      imagePath: 'assets/images/products/dessert.svg',
    );
    await add(
      catId: _catDessertId,
      name: 'Apfelstrudel',
      price: 900,
      description: 'Hausgemachter Apfelstrudel, Vanillesauce, Zimt-Eis',
      prepTime: 5,
      printerGroup: 'dessert',
      imagePath: 'assets/images/products/dessert.svg',
    );

    // -- Getränke --
    _prodMineralwasserId = await add(
      catId: _catGetraenkeId,
      name: 'Mineralwasser',
      price: 350,
      description: 'Still oder Sprudel, 500ml',
      taxGroup: 'beverage',
      printerGroup: 'bar',
      imagePath: 'assets/images/products/beverage.svg',
    );
    _drinkIds.add(_prodMineralwasserId);

    final colaId = await add(
      catId: _catGetraenkeId,
      name: 'Coca-Cola',
      price: 450,
      description: '330ml Dose',
      taxGroup: 'beverage',
      printerGroup: 'bar',
      imagePath: 'assets/images/products/beverage.svg',
    );
    _drinkIds.add(colaId);

    _prodHausweinId = await add(
      catId: _catGetraenkeId,
      name: 'Hauswein',
      price: 600,
      description: '1dl Haus-Wein, Rot oder Weiss',
      taxGroup: 'alcohol',
      printerGroup: 'bar',
      imagePath: 'assets/images/products/beverage.svg',
    );
    _drinkIds.add(_prodHausweinId);

    final bierFassId = await add(
      catId: _catGetraenkeId,
      name: 'Bier vom Fass',
      price: 550,
      description: '3dl frisch vom Fass',
      taxGroup: 'alcohol',
      printerGroup: 'bar',
      imagePath: 'assets/images/products/beverage.svg',
    );
    _drinkIds.add(bierFassId);

    final espressoId = await add(
      catId: _catGetraenkeId,
      name: 'Espresso',
      price: 400,
      description: 'Doppelter Espresso',
      taxGroup: 'beverage',
      printerGroup: 'bar',
      imagePath: 'assets/images/products/beverage.svg',
    );
    _drinkIds.add(espressoId);

    _prodCappuccinoId = await add(
      catId: _catGetraenkeId,
      name: 'Cappuccino',
      price: 550,
      description: 'Mit feinem Milchschaum und Latte-Art',
      taxGroup: 'beverage',
      printerGroup: 'bar',
      imagePath: 'assets/images/products/beverage.svg',
    );
    _drinkIds.add(_prodCappuccinoId);
  }

  // -------------------------------------------------------------------------
  // Modifier Groups & Modifiers
  // -------------------------------------------------------------------------

  Future<void> _seedModifiers() async {
    final now = DateTime.now();

    Future<String> addGroup({
      required String name,
      required String selectionType,
      required int minSel,
      required int maxSel,
      required bool isRequired,
      required int displayOrder,
    }) async {
      final id = IdGenerator.generateId();
      await db.into(db.modifierGroups).insert(
        ModifierGroupsCompanion(
          id: Value(id),
          tenantId: Value(_tenantId),
          name: Value(name),
          selectionType: Value(selectionType),
          minSelections: Value(minSel),
          maxSelections: Value(maxSel),
          isRequired: Value(isRequired),
          displayOrder: Value(displayOrder),
          createdAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
      return id;
    }

    Future<void> addOption({
      required String groupId,
      required String name,
      required int priceDelta,
      required bool isDefault,
      required int displayOrder,
    }) async {
      await db.into(db.modifiers).insert(
        ModifiersCompanion(
          id: Value(IdGenerator.generateId()),
          tenantId: Value(_tenantId),
          groupId: Value(groupId),
          name: Value(name),
          priceDelta: Value(priceDelta),
          isDefault: Value(isDefault),
          displayOrder: Value(displayOrder),
          createdAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
    }

    Future<void> linkGroup(String productId, String groupId, int order) async {
      await db.into(db.productModifierGroups).insert(
        ProductModifierGroupsCompanion(
          id: Value(IdGenerator.generateId()),
          productId: Value(productId),
          modifierGroupId: Value(groupId),
          displayOrder: Value(order),
        ),
      );
    }

    // -- 1. Zusätzliche Zutaten (optional, multiple, max 5) -----------------
    _mgZutatenId = await addGroup(
      name: 'Zusätzliche Zutaten',
      selectionType: 'multiple',
      minSel: 0,
      maxSel: 5,
      isRequired: false,
      displayOrder: 0,
    );
    for (final o in [
      (name: 'Käse', delta: 250, def: false, order: 0),
      (name: 'Champignons', delta: 150, def: false, order: 1),
      (name: 'Zwiebeln', delta: 100, def: false, order: 2),
      (name: 'Peperoni', delta: 100, def: false, order: 3),
      (name: 'Avocado', delta: 300, def: false, order: 4),
    ]) {
      await addOption(
        groupId: _mgZutatenId,
        name: o.name,
        priceDelta: o.delta,
        isDefault: o.def,
        displayOrder: o.order,
      );
    }

    // -- 2. Sauce (required, single) ----------------------------------------
    _mgSauceId = await addGroup(
      name: 'Sauce',
      selectionType: 'single',
      minSel: 1,
      maxSel: 1,
      isRequired: true,
      displayOrder: 1,
    );
    for (final o in [
      (name: 'Ketchup', delta: 0, def: true, order: 0),
      (name: 'Mayonnaise', delta: 0, def: false, order: 1),
      (name: 'BBQ', delta: 0, def: false, order: 2),
      (name: 'Ranch', delta: 0, def: false, order: 3),
      (name: 'Knoblauch', delta: 0, def: false, order: 4),
    ]) {
      await addOption(
        groupId: _mgSauceId,
        name: o.name,
        priceDelta: o.delta,
        isDefault: o.def,
        displayOrder: o.order,
      );
    }

    // -- 3. Garpunkt (required, single) -------------------------------------
    _mgGarpunktId = await addGroup(
      name: 'Garpunkt',
      selectionType: 'single',
      minSel: 1,
      maxSel: 1,
      isRequired: true,
      displayOrder: 2,
    );
    for (final o in [
      (name: 'Rare (blutig)', delta: 0, def: false, order: 0),
      (name: 'Medium', delta: 0, def: true, order: 1),
      (name: 'Well Done', delta: 0, def: false, order: 2),
    ]) {
      await addOption(
        groupId: _mgGarpunktId,
        name: o.name,
        priceDelta: o.delta,
        isDefault: o.def,
        displayOrder: o.order,
      );
    }

    // -- 4. Getränkegrösse (required, single) --------------------------------
    _mgGroesseId = await addGroup(
      name: 'Getränkegrösse',
      selectionType: 'single',
      minSel: 1,
      maxSel: 1,
      isRequired: true,
      displayOrder: 3,
    );
    for (final o in [
      (name: 'Klein', delta: 0, def: true, order: 0),
      (name: 'Mittel', delta: 100, def: false, order: 1),
      (name: 'Gross', delta: 200, def: false, order: 2),
    ]) {
      await addOption(
        groupId: _mgGroesseId,
        name: o.name,
        priceDelta: o.delta,
        isDefault: o.def,
        displayOrder: o.order,
      );
    }

    // -- 5. Beilage (optional, multiple, max 3) ------------------------------
    _mgBeilageId = await addGroup(
      name: 'Beilage',
      selectionType: 'multiple',
      minSel: 0,
      maxSel: 3,
      isRequired: false,
      displayOrder: 4,
    );
    for (final o in [
      (name: 'Pommes frites', delta: 450, def: false, order: 0),
      (name: 'Salat', delta: 350, def: false, order: 1),
      (name: 'Reis', delta: 300, def: false, order: 2),
      (name: 'Suppe', delta: 400, def: false, order: 3),
    ]) {
      await addOption(
        groupId: _mgBeilageId,
        name: o.name,
        priceDelta: o.delta,
        isDefault: o.def,
        displayOrder: o.order,
      );
    }

    // -----------------------------------------------------------------------
    // Link modifier groups to products
    // -----------------------------------------------------------------------

    // Burger Classic → Garpunkt + Zutaten + Sauce + Beilage
    if (_burgerId != null) {
      await linkGroup(_burgerId!, _mgGarpunktId, 0);
      await linkGroup(_burgerId!, _mgZutatenId, 1);
      await linkGroup(_burgerId!, _mgSauceId, 2);
      await linkGroup(_burgerId!, _mgBeilageId, 3);
    }

    // Grilliertes Rindsfilet & Zürich Geschnetzeltes → Garpunkt + Beilage
    for (final id in _grillIds) {
      if (id == _burgerId) continue;
      await linkGroup(id, _mgGarpunktId, 0);
      await linkGroup(id, _mgBeilageId, 1);
    }

    // Other Hauptspeisen (non-grill) → Beilage only
    for (final id in _mainIds) {
      if (_grillIds.contains(id)) continue;
      await linkGroup(id, _mgBeilageId, 0);
    }

    // Pizzen → Zusätzliche Zutaten
    for (final id in _pizzaIds) {
      await linkGroup(id, _mgZutatenId, 0);
    }

    // Getränke → Getränkegrösse
    for (final id in _drinkIds) {
      await linkGroup(id, _mgGroesseId, 0);
    }
  }

  // -------------------------------------------------------------------------
  // Floors
  // -------------------------------------------------------------------------

  String _floorHauptraumId = '';
  String _floorTerasseId = '';

  Future<void> _seedFloors() async {
    final now = DateTime.now();
    _floorHauptraumId = IdGenerator.generateId();
    _floorTerasseId = IdGenerator.generateId();

    await db.into(db.floors).insert(
      FloorsCompanion(
        id: Value(_floorHauptraumId),
        tenantId: Value(_tenantId),
        name: const Value('Hauptraum'),
        displayOrder: const Value(0),
        createdAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(0),
        isDeleted: const Value(false),
      ),
    );
    await db.into(db.floors).insert(
      FloorsCompanion(
        id: Value(_floorTerasseId),
        tenantId: Value(_tenantId),
        name: const Value('Terrasse'),
        displayOrder: const Value(1),
        createdAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(0),
        isDeleted: const Value(false),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tables
  // -------------------------------------------------------------------------

  Future<void> _seedTables() async {
    final now = DateTime.now();

    // Hauptraum: M1–M10 (10 Tische)
    final hauptraumTables = [
      (name: 'M1', cap: 4, x: 50.0, y: 50.0, w: 120.0, h: 80.0, shape: 'rectangle'),
      (name: 'M2', cap: 4, x: 200.0, y: 50.0, w: 120.0, h: 80.0, shape: 'rectangle'),
      (name: 'M3', cap: 2, x: 350.0, y: 50.0, w: 100.0, h: 70.0, shape: 'rectangle'),
      (name: 'M4', cap: 6, x: 500.0, y: 50.0, w: 140.0, h: 90.0, shape: 'rectangle'),
      (name: 'M5', cap: 4, x: 50.0, y: 180.0, w: 120.0, h: 80.0, shape: 'rectangle'),
      (name: 'M6', cap: 2, x: 200.0, y: 180.0, w: 100.0, h: 70.0, shape: 'rectangle'),
      (name: 'M7', cap: 4, x: 350.0, y: 180.0, w: 120.0, h: 80.0, shape: 'rectangle'),
      (name: 'M8', cap: 8, x: 500.0, y: 180.0, w: 160.0, h: 100.0, shape: 'rectangle'),
      (name: 'M9', cap: 4, x: 50.0, y: 320.0, w: 120.0, h: 80.0, shape: 'rectangle'),
      (name: 'M10', cap: 2, x: 200.0, y: 320.0, w: 100.0, h: 70.0, shape: 'rectangle'),
    ];

    for (final t in hauptraumTables) {
      final id = IdGenerator.generateId();
      if (t.name == 'M2') _tableM2Id = id;
      if (t.name == 'M7') _tableM7Id = id;

      await db.into(db.restaurantTables).insert(
        RestaurantTablesCompanion(
          id: Value(id),
          tenantId: Value(_tenantId),
          floorId: Value(_floorHauptraumId),
          name: Value(t.name),
          capacity: Value(t.cap),
          shape: Value(t.shape),
          posX: Value(t.x),
          posY: Value(t.y),
          width: Value(t.w),
          height: Value(t.h),
          status: const Value('available'),
          createdAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
    }

    // Terrasse: T1–T5 (5 Tische)
    final terrasseTables = [
      (name: 'T1', cap: 4, shape: 'circle', x: 80.0, y: 60.0, w: 100.0, h: 100.0),
      (name: 'T2', cap: 6, shape: 'rectangle', x: 240.0, y: 60.0, w: 140.0, h: 90.0),
      (name: 'T3', cap: 2, shape: 'circle', x: 80.0, y: 200.0, w: 90.0, h: 90.0),
      (name: 'T4', cap: 4, shape: 'square', x: 240.0, y: 200.0, w: 110.0, h: 110.0),
      (name: 'T5', cap: 8, shape: 'rectangle', x: 400.0, y: 60.0, w: 160.0, h: 100.0),
    ];

    for (final t in terrasseTables) {
      final id = IdGenerator.generateId();
      if (t.name == 'T1') _tableT1Id = id;

      await db.into(db.restaurantTables).insert(
        RestaurantTablesCompanion(
          id: Value(id),
          tenantId: Value(_tenantId),
          floorId: Value(_floorTerasseId),
          name: Value(t.name),
          capacity: Value(t.cap),
          shape: Value(t.shape),
          posX: Value(t.x),
          posY: Value(t.y),
          width: Value(t.w),
          height: Value(t.h),
          status: const Value('available'),
          createdAt: Value(now),
          updatedAt: Value(now),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Tax Profiles — Switzerland (CH)
  // MWST 2026: 2.6% (Takeaway/Delivery Lebensmittel), 3.8% (Beherbergung),
  //            8.1% (Restaurant/Standard)
  // -------------------------------------------------------------------------

  Future<void> _seedTaxProfiles() async {
    final now = DateTime.now();

    Future<void> addProfile({
      required String orderType,
      required String taxGroup,
      required double rate,
      required String name,
    }) async {
      await db.into(db.taxProfiles).insert(
        TaxProfilesCompanion(
          id: Value(IdGenerator.generateId()),
          tenantId: Value(_tenantId),
          countryCode: const Value('CH'),
          orderType: Value(orderType),
          productTaxGroup: Value(taxGroup),
          taxRate: Value(rate),
          taxName: Value(name),
          isDefault: const Value(false),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }

    // Dine-in: Normalsatz 8.1% für alle Produktgruppen
    for (final grp in ['food', 'beverage', 'alcohol']) {
      await addProfile(
        orderType: 'dine_in',
        taxGroup: grp,
        rate: 8.1,
        name: 'MWST 8.1% (Restaurant)',
      );
    }

    // Takeaway: Lebensmittel/Getränke 2.6%, Alkohol 8.1%
    await addProfile(
      orderType: 'takeaway',
      taxGroup: 'food',
      rate: 2.6,
      name: 'MWST 2.6% (Takeaway)',
    );
    await addProfile(
      orderType: 'takeaway',
      taxGroup: 'beverage',
      rate: 2.6,
      name: 'MWST 2.6% (Takeaway)',
    );
    await addProfile(
      orderType: 'takeaway',
      taxGroup: 'alcohol',
      rate: 8.1,
      name: 'MWST 8.1% (Alkohol)',
    );

    // Delivery: gleich wie Takeaway
    await addProfile(
      orderType: 'delivery',
      taxGroup: 'food',
      rate: 2.6,
      name: 'MWST 2.6% (Lieferung)',
    );
    await addProfile(
      orderType: 'delivery',
      taxGroup: 'beverage',
      rate: 2.6,
      name: 'MWST 2.6% (Lieferung)',
    );
    await addProfile(
      orderType: 'delivery',
      taxGroup: 'alcohol',
      rate: 8.1,
      name: 'MWST 8.1% (Alkohol)',
    );

    // Beherbergung (Hotel/Accommodation): Sondersatz 3.8%
    for (final grp in ['food', 'beverage', 'alcohol']) {
      await addProfile(
        orderType: 'accommodation',
        taxGroup: grp,
        rate: 3.8,
        name: 'MWST 3.8% (Beherbergung)',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Demo Orders — 3 abgeschlossene Bestellungen für Beispieldaten
  // -------------------------------------------------------------------------

  Future<void> _seedDemoOrders() async {
    // Require key IDs to be set
    if (_tenantId.isEmpty ||
        _cashierId.isEmpty ||
        _waiterIds.isEmpty ||
        _prodZuerichGeschId.isEmpty) {
      return;
    }

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final waiterId = _waiterIds.first;

    // -----------------------------------------------------------
    // Order 1: Tisch M2 · 2 Gäste · Dine-in · Bar bezahlt
    // Zürich Geschnetzeltes ×2 + Hauswein ×2 → CHF 69.00 + MWST
    // -----------------------------------------------------------
    if (_tableM2Id.isNotEmpty &&
        _prodZuerichGeschId.isNotEmpty &&
        _prodHausweinId.isNotEmpty) {
      final t1Id = IdGenerator.generateId();
      final item1aId = IdGenerator.generateId();
      final item1bId = IdGenerator.generateId();
      final item1cId = IdGenerator.generateId();
      final item1dId = IdGenerator.generateId();
      final bill1Id = IdGenerator.generateId();
      final kt1Id = IdGenerator.generateId();

      // subtotal = 2×2850 + 2×600 = 5700 + 1200 = 6900 rappen
      // tax = round(6900 × 0.081) = round(558.9) = 559 rappen
      // total = 6900 + 559 = 7459 rappen
      const sub1 = 6900;
      const tax1 = 559;
      const total1 = 7459;

      await db.into(db.tickets).insert(
        TicketsCompanion(
          id: Value(t1Id),
          tenantId: Value(_tenantId),
          orderNumber: const Value(1001),
          orderType: const Value('dine_in'),
          tableId: Value(_tableM2Id),
          waiterId: Value(waiterId),
          guestCount: const Value(2),
          status: const Value('fully_paid'),
          channel: const Value('pos'),
          subtotal: const Value(sub1),
          taxAmount: const Value(tax1),
          discountAmount: const Value(0),
          total: const Value(total1),
          openedAt: Value(yesterday.copyWith(hour: 12, minute: 15)),
          closedAt: Value(yesterday.copyWith(hour: 13, minute: 5)),
          deviceId: const Value('demo-device-001'),
          createdAt: Value(yesterday.copyWith(hour: 12, minute: 15)),
          updatedAt: Value(yesterday.copyWith(hour: 13, minute: 5)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );

      for (final item in [
        (id: item1aId, pid: _prodZuerichGeschId, name: 'Zürich Geschnetzeltes', qty: 1.0, price: 2850),
        (id: item1bId, pid: _prodZuerichGeschId, name: 'Zürich Geschnetzeltes', qty: 1.0, price: 2850),
        (id: item1cId, pid: _prodHausweinId, name: 'Hauswein', qty: 1.0, price: 600),
        (id: item1dId, pid: _prodHausweinId, name: 'Hauswein', qty: 1.0, price: 600),
      ]) {
        await db.into(db.orderItems).insert(
          OrderItemsCompanion(
            id: Value(item.id),
            tenantId: Value(_tenantId),
            ticketId: Value(t1Id),
            productId: Value(item.pid),
            productName: Value(item.name),
            quantity: Value(item.qty),
            unitPrice: Value(item.price),
            subtotal: Value(item.price),
            taxAmount: Value((item.price * 0.081).round()),
            status: const Value('served'),
            sentToKitchen: const Value(true),
            course: const Value(1),
            createdAt: Value(yesterday.copyWith(hour: 12, minute: 15)),
            updatedAt: Value(yesterday.copyWith(hour: 12, minute: 35)),
            syncStatus: const Value(0),
            isDeleted: const Value(false),
          ),
        );
      }

      await db.into(db.kitchenTickets).insert(
        KitchenTicketsCompanion(
          id: Value(kt1Id),
          tenantId: Value(_tenantId),
          ticketId: Value(t1Id),
          kitchenTableName: const Value('M2'),
          orderNumber: const Value(1001),
          printerGroup: const Value('grill'),
          status: const Value('completed'),
          sentAt: Value(yesterday.copyWith(hour: 12, minute: 16)),
          startedAt: Value(yesterday.copyWith(hour: 12, minute: 20)),
          completedAt: Value(yesterday.copyWith(hour: 12, minute: 34)),
          createdAt: Value(yesterday.copyWith(hour: 12, minute: 16)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );

      await db.into(db.bills).insert(
        BillsCompanion(
          id: Value(bill1Id),
          tenantId: Value(_tenantId),
          ticketId: Value(t1Id),
          billNumber: const Value(1001),
          subtotal: const Value(sub1),
          taxAmount: const Value(tax1),
          discountAmount: const Value(0),
          total: const Value(total1),
          status: const Value('paid'),
          createdAt: Value(yesterday.copyWith(hour: 13, minute: 0)),
          updatedAt: Value(yesterday.copyWith(hour: 13, minute: 5)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );

      await db.into(db.payments).insert(
        PaymentsCompanion(
          id: Value(IdGenerator.generateId()),
          tenantId: Value(_tenantId),
          billId: Value(bill1Id),
          ticketId: Value(t1Id),
          paymentMethod: const Value('cash'),
          amount: const Value(total1),
          tipAmount: const Value(0),
          tenderedAmount: const Value(8000),
          changeAmount: const Value(8000 - total1),
          receivedBy: Value(_cashierId),
          paidAt: Value(yesterday.copyWith(hour: 13, minute: 5)),
          createdAt: Value(yesterday.copyWith(hour: 13, minute: 5)),
          updatedAt: Value(yesterday.copyWith(hour: 13, minute: 5)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
    }

    // -----------------------------------------------------------
    // Order 2: Terrasse T1 · 3 Gäste · Dine-in · Karte bezahlt
    // Margherita ×2 + Cappuccino ×3 → CHF 48.50 + MWST
    // -----------------------------------------------------------
    if (_tableT1Id.isNotEmpty &&
        _prodMargheritaId.isNotEmpty &&
        _prodCappuccinoId.isNotEmpty) {
      final t2Id = IdGenerator.generateId();
      final bill2Id = IdGenerator.generateId();
      final kt2Id = IdGenerator.generateId();

      // 2×1600 + 3×550 = 3200 + 1650 = 4850
      // tax = round(4850 × 0.081) = 393
      // total = 5243
      const sub2 = 4850;
      const tax2 = 393;
      const total2 = 5243;

      await db.into(db.tickets).insert(
        TicketsCompanion(
          id: Value(t2Id),
          tenantId: Value(_tenantId),
          orderNumber: const Value(1002),
          orderType: const Value('dine_in'),
          tableId: Value(_tableT1Id),
          waiterId: Value(waiterId),
          guestCount: const Value(3),
          status: const Value('fully_paid'),
          channel: const Value('pos'),
          subtotal: const Value(sub2),
          taxAmount: const Value(tax2),
          discountAmount: const Value(0),
          total: const Value(total2),
          openedAt: Value(yesterday.copyWith(hour: 19, minute: 0)),
          closedAt: Value(yesterday.copyWith(hour: 20, minute: 15)),
          deviceId: const Value('demo-device-001'),
          createdAt: Value(yesterday.copyWith(hour: 19, minute: 0)),
          updatedAt: Value(yesterday.copyWith(hour: 20, minute: 15)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );

      for (final item in [
        (pid: _prodMargheritaId, name: 'Margherita', qty: 1.0, price: 1600),
        (pid: _prodMargheritaId, name: 'Margherita', qty: 1.0, price: 1600),
        (pid: _prodCappuccinoId, name: 'Cappuccino', qty: 1.0, price: 550),
        (pid: _prodCappuccinoId, name: 'Cappuccino', qty: 1.0, price: 550),
        (pid: _prodCappuccinoId, name: 'Cappuccino', qty: 1.0, price: 550),
      ]) {
        await db.into(db.orderItems).insert(
          OrderItemsCompanion(
            id: Value(IdGenerator.generateId()),
            tenantId: Value(_tenantId),
            ticketId: Value(t2Id),
            productId: Value(item.pid),
            productName: Value(item.name),
            quantity: Value(item.qty),
            unitPrice: Value(item.price),
            subtotal: Value(item.price),
            taxAmount: Value((item.price * 0.081).round()),
            status: const Value('served'),
            sentToKitchen: const Value(true),
            course: const Value(1),
            createdAt: Value(yesterday.copyWith(hour: 19, minute: 0)),
            updatedAt: Value(yesterday.copyWith(hour: 19, minute: 25)),
            syncStatus: const Value(0),
            isDeleted: const Value(false),
          ),
        );
      }

      await db.into(db.kitchenTickets).insert(
        KitchenTicketsCompanion(
          id: Value(kt2Id),
          tenantId: Value(_tenantId),
          ticketId: Value(t2Id),
          kitchenTableName: const Value('T1'),
          orderNumber: const Value(1002),
          printerGroup: const Value('kitchen'),
          status: const Value('completed'),
          sentAt: Value(yesterday.copyWith(hour: 19, minute: 1)),
          startedAt: Value(yesterday.copyWith(hour: 19, minute: 5)),
          completedAt: Value(yesterday.copyWith(hour: 19, minute: 15)),
          createdAt: Value(yesterday.copyWith(hour: 19, minute: 1)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );

      await db.into(db.bills).insert(
        BillsCompanion(
          id: Value(bill2Id),
          tenantId: Value(_tenantId),
          ticketId: Value(t2Id),
          billNumber: const Value(1002),
          subtotal: const Value(sub2),
          taxAmount: const Value(tax2),
          discountAmount: const Value(0),
          total: const Value(total2),
          status: const Value('paid'),
          createdAt: Value(yesterday.copyWith(hour: 20, minute: 10)),
          updatedAt: Value(yesterday.copyWith(hour: 20, minute: 15)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );

      await db.into(db.payments).insert(
        PaymentsCompanion(
          id: Value(IdGenerator.generateId()),
          tenantId: Value(_tenantId),
          billId: Value(bill2Id),
          ticketId: Value(t2Id),
          paymentMethod: const Value('card'),
          amount: const Value(total2),
          tipAmount: const Value(0),
          tenderedAmount: const Value(total2),
          changeAmount: const Value(0),
          receivedBy: Value(_cashierId),
          paidAt: Value(yesterday.copyWith(hour: 20, minute: 15)),
          createdAt: Value(yesterday.copyWith(hour: 20, minute: 15)),
          updatedAt: Value(yesterday.copyWith(hour: 20, minute: 15)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
    }

    // -----------------------------------------------------------
    // Order 3: Tisch M7 · 2 Gäste · Dine-in · TWINT bezahlt
    // Wiener Schnitzel ×1 + Caesar Salat ×1 + Tiramisu ×2
    // + Mineralwasser ×2 → CHF 64.50 + MWST
    // -----------------------------------------------------------
    if (_tableM7Id.isNotEmpty &&
        _prodWienerSchnitzelId.isNotEmpty &&
        _prodCaesarSalatId.isNotEmpty &&
        _prodTiramisuId.isNotEmpty &&
        _prodMineralwasserId.isNotEmpty) {
      final t3Id = IdGenerator.generateId();
      final bill3Id = IdGenerator.generateId();
      final kt3GrillId = IdGenerator.generateId();
      final kt3ColdId = IdGenerator.generateId();
      final kt3DessertId = IdGenerator.generateId();

      // 2600 + 1250 + 2×950 + 2×350 = 2600+1250+1900+700 = 6450
      // tax = round(6450 × 0.081) = round(522.45) = 522
      // total = 6972
      const sub3 = 6450;
      const tax3 = 522;
      const total3 = 6972;

      await db.into(db.tickets).insert(
        TicketsCompanion(
          id: Value(t3Id),
          tenantId: Value(_tenantId),
          orderNumber: const Value(1003),
          orderType: const Value('dine_in'),
          tableId: Value(_tableM7Id),
          waiterId: Value(waiterId),
          guestCount: const Value(2),
          status: const Value('fully_paid'),
          channel: const Value('pos'),
          subtotal: const Value(sub3),
          taxAmount: const Value(tax3),
          discountAmount: const Value(0),
          total: const Value(total3),
          openedAt: Value(yesterday.copyWith(hour: 20, minute: 0)),
          closedAt: Value(yesterday.copyWith(hour: 21, minute: 30)),
          deviceId: const Value('demo-device-001'),
          createdAt: Value(yesterday.copyWith(hour: 20, minute: 0)),
          updatedAt: Value(yesterday.copyWith(hour: 21, minute: 30)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );

      for (final item in [
        (pid: _prodWienerSchnitzelId, name: 'Wiener Schnitzel', qty: 1.0, price: 2600),
        (pid: _prodCaesarSalatId, name: 'Caesar Salat', qty: 1.0, price: 1250),
        (pid: _prodTiramisuId, name: 'Tiramisu', qty: 1.0, price: 950),
        (pid: _prodTiramisuId, name: 'Tiramisu', qty: 1.0, price: 950),
        (pid: _prodMineralwasserId, name: 'Mineralwasser', qty: 1.0, price: 350),
        (pid: _prodMineralwasserId, name: 'Mineralwasser', qty: 1.0, price: 350),
      ]) {
        await db.into(db.orderItems).insert(
          OrderItemsCompanion(
            id: Value(IdGenerator.generateId()),
            tenantId: Value(_tenantId),
            ticketId: Value(t3Id),
            productId: Value(item.pid),
            productName: Value(item.name),
            quantity: Value(item.qty),
            unitPrice: Value(item.price),
            subtotal: Value(item.price),
            taxAmount: Value((item.price * 0.081).round()),
            status: const Value('served'),
            sentToKitchen: const Value(true),
            course: const Value(1),
            createdAt: Value(yesterday.copyWith(hour: 20, minute: 0)),
            updatedAt: Value(yesterday.copyWith(hour: 20, minute: 45)),
            syncStatus: const Value(0),
            isDeleted: const Value(false),
          ),
        );
      }

      // KDS: Grill (Wiener Schnitzel), Cold (Caesar Salat), Dessert (Tiramisu)
      for (final kt in [
        (id: kt3GrillId, group: 'grill', orderNum: 1003),
        (id: kt3ColdId, group: 'cold', orderNum: 1003),
        (id: kt3DessertId, group: 'dessert', orderNum: 1003),
      ]) {
        await db.into(db.kitchenTickets).insert(
          KitchenTicketsCompanion(
            id: Value(kt.id),
            tenantId: Value(_tenantId),
            ticketId: Value(t3Id),
            kitchenTableName: const Value('M7'),
            orderNumber: Value(kt.orderNum),
            printerGroup: Value(kt.group),
            status: const Value('completed'),
            sentAt: Value(yesterday.copyWith(hour: 20, minute: 2)),
            startedAt: Value(yesterday.copyWith(hour: 20, minute: 10)),
            completedAt: Value(yesterday.copyWith(hour: 20, minute: 35)),
            createdAt: Value(yesterday.copyWith(hour: 20, minute: 2)),
            syncStatus: const Value(0),
            isDeleted: const Value(false),
          ),
        );
      }

      await db.into(db.bills).insert(
        BillsCompanion(
          id: Value(bill3Id),
          tenantId: Value(_tenantId),
          ticketId: Value(t3Id),
          billNumber: const Value(1003),
          subtotal: const Value(sub3),
          taxAmount: const Value(tax3),
          discountAmount: const Value(0),
          total: const Value(total3),
          status: const Value('paid'),
          createdAt: Value(yesterday.copyWith(hour: 21, minute: 25)),
          updatedAt: Value(yesterday.copyWith(hour: 21, minute: 30)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );

      await db.into(db.payments).insert(
        PaymentsCompanion(
          id: Value(IdGenerator.generateId()),
          tenantId: Value(_tenantId),
          billId: Value(bill3Id),
          ticketId: Value(t3Id),
          paymentMethod: const Value('twint'),
          amount: const Value(total3),
          tipAmount: const Value(0),
          tenderedAmount: const Value(total3),
          changeAmount: const Value(0),
          receivedBy: Value(_cashierId),
          paidAt: Value(yesterday.copyWith(hour: 21, minute: 30)),
          createdAt: Value(yesterday.copyWith(hour: 21, minute: 30)),
          updatedAt: Value(yesterday.copyWith(hour: 21, minute: 30)),
          syncStatus: const Value(0),
          isDeleted: const Value(false),
        ),
      );
    }
  }
}
