import 'package:drift/drift.dart';

@DataClassName('Product')
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  TextColumn get categoryId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get price => integer()(); // cents: 1500 = CHF 15.00
  IntColumn get costPrice => integer().withDefault(const Constant(0))(); // cents
  TextColumn get taxGroup => text().withDefault(const Constant('default'))();
  TextColumn get imagePath => text().nullable()();
  TextColumn get barcode => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Operator-facing "sold out / 86'd" flag. When false the product is
  /// still listed on the menu (isActive), but temporarily cannot be
  /// ordered — the POS grid greys it out and blocks taps. Default true
  /// so existing rows behave as before.
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();

  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  IntColumn get prepTimeMinutes => integer().nullable()();
  TextColumn get printerGroup => text().withDefault(const Constant('kitchen'))();

  /// Default Gang assignment for this product (references gang_templates.id).
  /// Null means fall back to category default or no Gang.
  TextColumn get defaultGangId => text().nullable()();

  /// Flags this product as a combo/set menu. When true, the POS must load
  /// the component list from [ComboItems] (keyed by [comboProductId]) at
  /// add-to-cart time and expand the cart line into its bundled items.
  /// Default false so existing single-item products keep their behaviour.
  BoolColumn get isCombo => boolean().withDefault(const Constant(false))();

  /// Optional flat discount applied at the combo level, in cents. The
  /// bundle is priced as `sum(components) - comboDiscountCents`, floored
  /// at zero. Null / zero means no bundle discount (combo sells at the
  /// combo product's own [price] instead). Kept as a nullable int so
  /// schema migration does not need to backfill a sentinel.
  IntColumn get comboDiscountCents => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// Cloud-master menu version this product was last applied from.
  /// Null for legacy rows authored before sync was enabled, or for rows
  /// created locally in `RestaurantSettings.menuEditMode = local|hybrid`.
  /// Stamped on every successful apply by [MenuSyncService] (v20).
  IntColumn get cloudVersion => integer().nullable()();

  /// "Online'da popüler" — surfaced in the read-only "Online ek bilgiler"
  /// overlay tab in the product detail screen. Authored by the cashier
  /// or marketing team in the Gastro Hub admin panel and pushed via the
  /// menu-sync pipeline (server-side migration 026). The POS treats this
  /// as a display-only signal — not used for ordering / pricing logic.
  /// Default false for legacy and locally-authored rows.
  BoolColumn get isPopularOnline =>
      boolean().withDefault(const Constant(false))();

  /// JSON-encoded allergen list from the online catalogue. Format mirrors
  /// the Postgres JSONB column on the cloud side
  /// (`{"contains":["gluten","lactose"],"mayContain":["nuts"],"freeFrom":["..."]}`).
  /// Null = no allergen info synced yet. The POS deserialises only inside
  /// the overlay tab; everything else ignores it. Source of truth is the
  /// admin panel — the POS UI is read-only, with a tooltip pointing at
  /// gastro.2hub.ch for edits.
  TextColumn get allergenInfo => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
