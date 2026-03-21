/// Centralised audit logging service for GastroCore POS.
///
/// Every module that needs to record an auditable event calls [log].
/// The service writes an [AuditLogEntryCompanion] to the database via
/// [AuditLogDao] and swallows all exceptions so audit failures never crash
/// the calling feature.
///
/// Usage:
/// ```dart
/// final audit = ref.read(auditServiceProvider);
/// await audit.log(
///   action: AuditAction.orderCancelled,
///   entityType: 'ticket',
///   entityId: ticket.id,
///   oldValueJson: jsonEncode(ticket.toJson()),
///   reason: 'Customer request',
/// );
/// ```
library;

import 'package:drift/drift.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';

class AuditService {
  AuditService({
    required AppDatabase db,
    required String tenantId,
    required String deviceId,
  })  : _db = db,
        _tenantId = tenantId,
        _deviceId = deviceId;

  final AppDatabase _db;
  final String _tenantId;
  final String _deviceId;

  // Current session context — set after login, cleared after logout.
  String _userId = '';
  String _userName = '';

  /// Call after a successful login to bind user context to every subsequent log.
  void setUser({required String userId, required String userName}) {
    _userId = userId;
    _userName = userName;
  }

  /// Call after logout to clear user context.
  void clearUser() {
    _userId = '';
    _userName = '';
  }

  // ---------------------------------------------------------------------------
  // Core logging method
  // ---------------------------------------------------------------------------

  /// Write a single audit log entry to the database.
  ///
  /// [userId] / [userName] override the session context when the acting user
  /// differs from the logged-in user (e.g. manager overrides).
  Future<void> log({
    required AuditAction action,
    required String entityType,
    required String entityId,
    String? oldValueJson,
    String? newValueJson,
    String? reason,
    String? ipAddress,
    String? userId,
    String? userName,
    String? branchId,
  }) async {
    final companion = AuditLogCompanion.insert(
      id: IdGenerator.generateId(),
      tenantId: _tenantId,
      branchId: Value(branchId),
      deviceId: _deviceId,
      userId: userId ?? _userId,
      userName: userName ?? _userName,
      action: action.name,
      entityType: entityType,
      entityId: entityId,
      oldValueJson: Value(oldValueJson),
      newValueJson: Value(newValueJson),
      reason: Value(reason),
      ipAddress: Value(ipAddress),
      timestamp: DateTime.now(),
    );

    try {
      await _db.auditLogDao.insertEntry(companion);
    } catch (_) {
      // Audit logging must never throw and crash the calling feature.
    }
  }

  // ---------------------------------------------------------------------------
  // Convenience shortcuts
  // ---------------------------------------------------------------------------

  Future<void> logOrderCreated(String ticketId, {String? newValueJson}) => log(
        action: AuditAction.orderCreated,
        entityType: 'ticket',
        entityId: ticketId,
        newValueJson: newValueJson,
      );

  Future<void> logOrderEdited(
    String ticketId, {
    String? oldValueJson,
    String? newValueJson,
    String? reason,
  }) =>
      log(
        action: AuditAction.orderEdited,
        entityType: 'ticket',
        entityId: ticketId,
        oldValueJson: oldValueJson,
        newValueJson: newValueJson,
        reason: reason,
      );

  Future<void> logOrderCancelled(String ticketId, {String? reason}) => log(
        action: AuditAction.orderCancelled,
        entityType: 'ticket',
        entityId: ticketId,
        reason: reason,
      );

  Future<void> logOrderVoided(String ticketId, {String? reason}) => log(
        action: AuditAction.orderVoided,
        entityType: 'ticket',
        entityId: ticketId,
        reason: reason,
      );

  Future<void> logPaymentReceived(String paymentId, {String? newValueJson}) =>
      log(
        action: AuditAction.paymentReceived,
        entityType: 'payment',
        entityId: paymentId,
        newValueJson: newValueJson,
      );

  Future<void> logPaymentRefunded(String paymentId, {String? reason}) => log(
        action: AuditAction.paymentRefunded,
        entityType: 'payment',
        entityId: paymentId,
        reason: reason,
      );

  Future<void> logDiscountApplied(String ticketId, {String? newValueJson}) =>
      log(
        action: AuditAction.discountApplied,
        entityType: 'ticket',
        entityId: ticketId,
        newValueJson: newValueJson,
      );

  Future<void> logShiftOpened(String shiftId, {String? newValueJson}) => log(
        action: AuditAction.shiftOpened,
        entityType: 'shift',
        entityId: shiftId,
        newValueJson: newValueJson,
      );

  Future<void> logShiftClosed(String shiftId, {String? newValueJson}) => log(
        action: AuditAction.shiftClosed,
        entityType: 'shift',
        entityId: shiftId,
        newValueJson: newValueJson,
      );

  Future<void> logPriceChanged(
    String productId, {
    String? oldValueJson,
    String? newValueJson,
  }) =>
      log(
        action: AuditAction.priceChanged,
        entityType: 'product',
        entityId: productId,
        oldValueJson: oldValueJson,
        newValueJson: newValueJson,
      );

  Future<void> logUserLoggedIn(String userId, String name) => log(
        action: AuditAction.userLoggedIn,
        entityType: 'user',
        entityId: userId,
        userId: userId,
        userName: name,
      );

  Future<void> logUserLoggedOut(String userId, String name) => log(
        action: AuditAction.userLoggedOut,
        entityType: 'user',
        entityId: userId,
        userId: userId,
        userName: name,
      );

  Future<void> logManagerOverride(String entityId, {String? reason}) => log(
        action: AuditAction.managerOverride,
        entityType: 'override',
        entityId: entityId,
        reason: reason,
      );

  Future<void> logSettingChanged(
    String settingKey, {
    String? oldValueJson,
    String? newValueJson,
  }) =>
      log(
        action: AuditAction.settingChanged,
        entityType: 'setting',
        entityId: settingKey,
        oldValueJson: oldValueJson,
        newValueJson: newValueJson,
      );

  Future<void> logCashDrawerOpened(String shiftId) => log(
        action: AuditAction.cashDrawerOpened,
        entityType: 'shift',
        entityId: shiftId,
      );
}
