/// Tables endpoint methods.
library;

import 'package:gastrocore_models/gastrocore_models.dart';
import '../client/gastrocore_client.dart';

class TablesEndpoint {
  final GastrocoreClient _client;

  const TablesEndpoint(this._client);

  Future<List<FloorEntity>> getFloors(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/tables/floors',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) => FloorEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<FloorEntity> createFloor(FloorEntity floor) async {
    final json = await _client.post('/api/v1/tables/floors', floor.toJson());
    return FloorEntity.fromJson(json);
  }

  Future<FloorEntity> updateFloor(FloorEntity floor) async {
    final json = await _client.put(
        '/api/v1/tables/floors/${floor.id}', floor.toJson());
    return FloorEntity.fromJson(json);
  }

  Future<void> deleteFloor(String floorId) async {
    await _client.delete('/api/v1/tables/floors/$floorId');
  }

  Future<List<RestaurantTableEntity>> getTables(String tenantId) async {
    final list = await _client.getList(
      '/api/v1/tables',
      queryParams: {'tenant_id': tenantId},
    );
    return list
        .map((j) =>
            RestaurantTableEntity.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<RestaurantTableEntity> createTable(
      RestaurantTableEntity table) async {
    final json =
        await _client.post('/api/v1/tables', table.toJson());
    return RestaurantTableEntity.fromJson(json);
  }

  Future<RestaurantTableEntity> updateTable(
      RestaurantTableEntity table) async {
    final json = await _client.put(
        '/api/v1/tables/${table.id}', table.toJson());
    return RestaurantTableEntity.fromJson(json);
  }

  Future<RestaurantTableEntity> updateTableStatus(
    String tableId,
    TableStatus status, {
    String? currentOrderId,
  }) async {
    final json = await _client.patch('/api/v1/tables/$tableId/status', {
      'status': status.name,
      if (currentOrderId != null) 'current_order_id': currentOrderId,
    });
    return RestaurantTableEntity.fromJson(json);
  }

  Future<void> deleteTable(String tableId) async {
    await _client.delete('/api/v1/tables/$tableId');
  }
}
