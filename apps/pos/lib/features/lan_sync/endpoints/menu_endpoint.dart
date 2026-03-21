/// Shelf endpoint handler for menu data on the LAN sync server.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

/// GET /menu — returns the full menu (categories + products).
///
/// Menu is read-only from the secondary's perspective; only the primary
/// (which manages the back-office) can modify it.
class MenuEndpoint {
  const MenuEndpoint({required this.fetchMenu});

  /// Returns a map with `categories` and `products` lists.
  final Future<Map<String, dynamic>> Function() fetchMenu;

  // ---------------------------------------------------------------------------

  Future<Response> getMenu(Request request) async {
    try {
      final menu = await fetchMenu();
      return Response.ok(jsonEncode(menu), headers: _json);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _json,
      );
    }
  }
}

const _json = {'Content-Type': 'application/json'};
