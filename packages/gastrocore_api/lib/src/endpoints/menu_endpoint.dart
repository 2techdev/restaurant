/// Menu endpoint methods.
library;

import 'package:gastrocore_models/gastrocore_models.dart';
import '../client/gastrocore_client.dart';

class MenuEndpoint {
  final GastrocoreClient _client;

  const MenuEndpoint(this._client);

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  Future<List<CategoryEntity>> getCategories(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/menu/categories',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) => CategoryEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<CategoryEntity> createCategory(CategoryEntity category) async {
    final json = await _client.post(
      '/api/v1/menu/categories',
      category.toJson(),
    );
    return CategoryEntity.fromJson(json);
  }

  Future<CategoryEntity> updateCategory(CategoryEntity category) async {
    final json = await _client.put(
      '/api/v1/menu/categories/${category.id}',
      category.toJson(),
    );
    return CategoryEntity.fromJson(json);
  }

  Future<void> deleteCategory(String categoryId) async {
    await _client.delete('/api/v1/menu/categories/$categoryId');
  }

  // ---------------------------------------------------------------------------
  // Products
  // ---------------------------------------------------------------------------

  Future<List<ProductEntity>> getProducts(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/menu/products',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) => ProductEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ProductEntity> getProduct(String productId) async {
    final json = await _client.get('/api/v1/menu/products/$productId');
    return ProductEntity.fromJson(json);
  }

  Future<ProductEntity> createProduct(ProductEntity product) async {
    final json = await _client.post(
      '/api/v1/menu/products',
      product.toJson(),
    );
    return ProductEntity.fromJson(json);
  }

  Future<ProductEntity> updateProduct(ProductEntity product) async {
    final json = await _client.put(
      '/api/v1/menu/products/${product.id}',
      product.toJson(),
    );
    return ProductEntity.fromJson(json);
  }

  Future<void> deleteProduct(String productId) async {
    await _client.delete('/api/v1/menu/products/$productId');
  }

  // ---------------------------------------------------------------------------
  // Modifiers
  // ---------------------------------------------------------------------------

  Future<List<ModifierGroupEntity>> getModifierGroups(
      String tenantId) async {
    final list = await _client.getList(
      '/api/v1/menu/modifier-groups',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) =>
            ModifierGroupEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ModifierGroupEntity> createModifierGroup(
      ModifierGroupEntity group) async {
    final json = await _client.post(
      '/api/v1/menu/modifier-groups',
      group.toJson(),
    );
    return ModifierGroupEntity.fromJson(json);
  }

  Future<ModifierGroupEntity> updateModifierGroup(
      ModifierGroupEntity group) async {
    final json = await _client.put(
      '/api/v1/menu/modifier-groups/${group.id}',
      group.toJson(),
    );
    return ModifierGroupEntity.fromJson(json);
  }
}
