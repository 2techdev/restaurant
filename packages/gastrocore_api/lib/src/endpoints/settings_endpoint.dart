/// Settings endpoints — SettingsEntity bag + typed RestaurantSettings.
library;

import 'package:gastrocore_models/gastrocore_models.dart';

import '../client/gastrocore_client.dart';

class SettingsEndpoint {
  final GastrocoreClient _client;

  const SettingsEndpoint(this._client);

  /// Fetch the raw settings bag for a tenant (optionally narrowed to a store).
  Future<SettingsEntity> get({
    required String tenantId,
    String? storeId,
  }) async {
    final json = await _client.get(
      '/api/v1/settings',
      queryParams: {
        'tenant_id': tenantId,
        if (storeId != null) 'store_id': storeId,
      },
    );
    return SettingsEntity.fromJson(json);
  }

  /// Replace the entire settings bag. Apps typically prefer [patch].
  Future<SettingsEntity> put(SettingsEntity settings) async {
    final json = await _client.put('/api/v1/settings', settings.toJson());
    return SettingsEntity.fromJson(json);
  }

  /// Patch a subset of keys. Unset keys are preserved server-side.
  Future<SettingsEntity> patch({
    required String tenantId,
    String? storeId,
    required Map<String, SettingValue> values,
  }) async {
    final json = await _client.patch('/api/v1/settings', {
      'tenant_id': tenantId,
      if (storeId != null) 'store_id': storeId,
      'values': values.map((k, v) => MapEntry(k, v.toJson())),
    });
    return SettingsEntity.fromJson(json);
  }

  // ---------------------------------------------------------------------------
  // Typed helpers
  // ---------------------------------------------------------------------------

  /// Fetch the typed [RestaurantSettings] projection.
  Future<RestaurantSettings> getRestaurantSettings({
    required String tenantId,
    String? storeId,
  }) async {
    final entity = await get(tenantId: tenantId, storeId: storeId);
    return RestaurantSettings.fromSettings(entity);
  }

  /// Persist [settings] by patching the keys it owns. Other keys in the
  /// bag are preserved.
  Future<RestaurantSettings> putRestaurantSettings({
    required String tenantId,
    String? storeId,
    required RestaurantSettings settings,
  }) async {
    final entity = await patch(
      tenantId: tenantId,
      storeId: storeId,
      values: settings.toSettingsMap(),
    );
    return RestaurantSettings.fromSettings(entity);
  }

  // ---------------------------------------------------------------------------
  // Tax catalog (associated metadata)
  // ---------------------------------------------------------------------------

  Future<List<TaxEntity>> listTaxes(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/settings/taxes',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) => TaxEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<TaxEntity> upsertTax(TaxEntity tax) async {
    final json = await _client.put(
      '/api/v1/settings/taxes/${tax.id}',
      tax.toJson(),
    );
    return TaxEntity.fromJson(json);
  }

  // ---------------------------------------------------------------------------
  // Service charges
  // ---------------------------------------------------------------------------

  Future<List<ServiceChargeEntity>> listServiceCharges(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/settings/service-charges',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) =>
            ServiceChargeEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceChargeEntity> upsertServiceCharge(
    ServiceChargeEntity charge,
  ) async {
    final json = await _client.put(
      '/api/v1/settings/service-charges/${charge.id}',
      charge.toJson(),
    );
    return ServiceChargeEntity.fromJson(json);
  }

  // ---------------------------------------------------------------------------
  // Discount catalog
  // ---------------------------------------------------------------------------

  Future<List<DiscountEntity>> listDiscounts(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/settings/discounts',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) => DiscountEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<DiscountEntity> upsertDiscount(DiscountEntity discount) async {
    final json = await _client.put(
      '/api/v1/settings/discounts/${discount.id}',
      discount.toJson(),
    );
    return DiscountEntity.fromJson(json);
  }
}
