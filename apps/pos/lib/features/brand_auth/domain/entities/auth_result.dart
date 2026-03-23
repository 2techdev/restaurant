/// Result returned by login / register operations.
library;

import 'package:gastrocore_pos/features/brand_auth/domain/entities/store_context.dart';

/// Successful authentication result.
class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.storeContext,
  });

  final String accessToken;
  final String refreshToken;
  final StoreContext storeContext;
}
