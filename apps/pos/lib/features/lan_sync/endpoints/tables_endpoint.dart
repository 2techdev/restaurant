/// Shelf endpoint handlers for table status on the LAN sync server.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

/// GET /tables            — returns all tables with current status.
/// POST /table-status     — updates a table's occupancy status.
class TablesEndpoint {
  const TablesEndpoint({
    required this.fetchTables,
    required this.updateTableStatus,
  });

  /// Returns a list of table JSON maps (id, name, status, currentOrderId, …).
  final Future<List<Map<String, dynamic>>> Function() fetchTables;

  /// Called when a secondary pushes a table-status change.
  /// [json] must contain at least `table_id` and `status`.
  final Future<void> Function(Map<String, dynamic> json) updateTableStatus;

  // ---------------------------------------------------------------------------

  Future<Response> getTables(Request request) async {
    try {
      final tables = await fetchTables();
      return Response.ok(
        jsonEncode({'tables': tables, 'count': tables.length}),
        headers: _json,
      );
    } catch (e) {
      return _serverError(e);
    }
  }

  Future<Response> postTableStatus(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (!json.containsKey('table_id') || !json.containsKey('status')) {
        return Response(
          400,
          body: jsonEncode({'error': 'table_id and status are required'}),
          headers: _json,
        );
      }
      await updateTableStatus(json);
      return Response.ok(
        jsonEncode({'status': 'updated'}),
        headers: _json,
      );
    } catch (e) {
      return _serverError(e);
    }
  }
}

const _json = {'Content-Type': 'application/json'};

Response _serverError(Object e) => Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: _json,
    );
