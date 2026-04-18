/// Store context – holds brand/store identity obtained after JWT login.
library;

import 'package:equatable/equatable.dart';

/// The role of the authenticated brand user.
enum BrandUserRole {
  owner,
  manager,
  staff,
}

/// Immutable value object that describes the currently active store session.
///
/// Obtained after a successful brand-level email/password login and persisted
/// in Flutter Secure Storage so it survives app restarts. All sync operations
/// and WebSocket connections are scoped to [storeId].
class StoreContext extends Equatable {
  const StoreContext({
    required this.brandId,
    required this.storeId,
    required this.storeName,
    required this.brandName,
    required this.userRole,
    required this.isOnlineMode,
    this.lastSyncAt,
  });

  final String brandId;
  final String storeId;
  final String storeName;
  final String brandName;
  final BrandUserRole userRole;

  /// Whether the app is running in online mode (connected to the GastroCore
  /// backend; default host `api.2hub.ch`, see `AppEndpoints`).
  final bool isOnlineMode;

  final DateTime? lastSyncAt;

  StoreContext copyWith({
    String? brandId,
    String? storeId,
    String? storeName,
    String? brandName,
    BrandUserRole? userRole,
    bool? isOnlineMode,
    DateTime? lastSyncAt,
  }) {
    return StoreContext(
      brandId: brandId ?? this.brandId,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      brandName: brandName ?? this.brandName,
      userRole: userRole ?? this.userRole,
      isOnlineMode: isOnlineMode ?? this.isOnlineMode,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  @override
  List<Object?> get props => [
        brandId,
        storeId,
        storeName,
        brandName,
        userRole,
        isOnlineMode,
        lastSyncAt,
      ];
}
