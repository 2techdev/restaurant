import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_online/app.dart';
import 'package:gastrocore_online/core/api/api_client.dart';
import 'package:gastrocore_online/core/api/mock_api_client.dart';
import 'package:gastrocore_online/providers/menu_provider.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_buildApiClient()),
      ],
      child: const OnlineOrderingApp(),
    ),
  );
}

/// Builds the appropriate API client based on the current hostname.
/// - localhost / 127.*  → real ApiClient → http://localhost:8080 (mock_server.py)
/// - pos.2tech.ch       → MockApiClient  → embedded Swiss demo data
/// - gastrocore.ch      → real ApiClient → https://api.gastrocore.ch
/// - everything else    → MockApiClient  → embedded demo data, no backend needed
///
/// To connect pos.2tech.ch to the real backend once it's configured:
/// change the 2tech.ch branch to:
///   return ApiClient(baseUrl: 'https://pos.2tech.ch');
ApiClient _buildApiClient() {
  try {
    // ignore: undefined_prefixed_name
    final host = Uri.base.host;
    if (host.contains('localhost') || host.startsWith('127.')) {
      return ApiClient(baseUrl: 'http://localhost:8080');
    }
    if (host.contains('gastrocore.ch')) {
      return ApiClient(baseUrl: 'https://api.gastrocore.ch');
    }
  } catch (_) {}
  // pos.2tech.ch and all other hosts → demo mode with embedded Swiss data
  return MockApiClient();
}
