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
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';

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
  ///
  /// [approver] is the manager / admin who authorised the action.  When
  /// supplied, [managerId] and [managerName] are populated on the log row.
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
    // Manager / admin who authorised this action (voids, discounts, etc.)
    UserEntity? approver,
    String? managerId,
    String? managerName,
  }) async {
    final effectiveManagerId = approver?.id ?? managerId;
    final effectiveManagerName = approver?.name ?? managerName;

    final companion = AuditLogCompanion.insert(
      id: IdGenerator.generateId(),
      tenantId: _tenantId,
      branchId: Value(branchId),
      deviceId: _deviceId,
      userId: userId ?? _userId,
      userName: userName ?? _userName,
      managerId: Value(effectiveManagerId),
      managerName: Value(effectiveManagerName),
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

  Future<void> logOrderVoided(
    String ticketId, {
    String? reason,
    UserEntity? approver,
  }) =>
      log(
        action: AuditAction.orderVoided,
        entityType: 'ticket',
        entityId: ticketId,
        reason: reason,
        approver: approver,
      );

  Future<void> logItemVoided(
    String orderItemId, {
    String? ticketId,
    String? reason,
    UserEntity? approver,
  }) =>
      log(
        action: AuditAction.itemVoided,
        entityType: 'order_item',
        entityId: orderItemId,
        reason: reason,
        approver: approver,
        newValueJson: ticketId != null ? '{"ticketId":"$ticketId"}' : null,
      );

  Future<void> logPaymentReceived(String paymentId, {String? newValueJson}) =>
      log(
        action: AuditAction.paymentReceived,
        entityType: 'payment',
        entityId: paymentId,
        newValueJson: newValueJson,
      );

  Future<void> logPaymentRefunded(
    String paymentId, {
    String? reason,
    UserEntity? approver,
  }) =>
      log(
        action: AuditAction.paymentRefunded,
        entityType: 'payment',
        entityId: paymentId,
        reason: reason,
        approver: approver,
      );

  Future<void> logItemRefunded(
    String orderItemId, {
    String? ticketId,
    String? reason,
    UserEntity? approver,
  }) =>
      log(
        action: AuditAction.itemRefunded,
        entityType: 'order_item',
        entityId: orderItemId,
        reason: reason,
        approver: approver,
        newValueJson: ticketId != null ? '{"ticketId":"$ticketId"}' : null,
      );

  Future<void> logDiscountApplied(
    String ticketId, {
    String? newValueJson,
    UserEntity? approver,
  }) =>
      log(
        action: AuditAction.discountApplied,
        entityType: 'ticket',
        entityId: ticketId,
        newValueJson: newValueJson,
        approver: approver,
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

  Future<void> logDayOpened(String shiftId, {String? cashierName}) => log(
        action: AuditAction.dayOpened,
        entityType: 'shift',
        entityId: shiftId,
        newValueJson:
            cashierName != null ? '{"cashier":"$cashierName"}' : null,
      );

  Future<void> logDayClosed(String shiftId, {String? newValueJson}) => log(
        action: AuditAction.dayClosed,
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

  /// Explicit Mesai (shift) start — distinct from login. Emitted by the
  /// clock panel only; login does NOT auto-clock so operators can share a
  /// session across relief breaks without polluting time sheets.
  Future<void> logUserClockedIn(String userId, String name) => log(
        action: AuditAction.userClockedIn,
        entityType: 'user',
        entityId: userId,
        userId: userId,
        userName: name,
      );

  /// Explicit Mesai (shift) end — distinct from logout.
  Future<void> logUserClockedOut(
    String userId,
    String name, {
    String? reason,
  }) =>
      log(
        action: AuditAction.userClockedOut,
        entityType: 'user',
        entityId: userId,
        userId: userId,
        userName: name,
        reason: reason,
      );

  /// Open an unpaid break for [userId]. Accrual stops until the matching
  /// [logUserBreakEnded] fires. The reducer swallows paired break events
  /// so worked-today only counts active time.
  Future<void> logUserBreakStarted(
    String userId,
    String name, {
    String? reason,
  }) =>
      log(
        action: AuditAction.userBreakStarted,
        entityType: 'user',
        entityId: userId,
        userId: userId,
        userName: name,
        reason: reason,
      );

  /// Close the currently-open break for [userId]. No-op downstream if no
  /// break is open (the reducer drops orphans but still records the
  /// audit trail).
  Future<void> logUserBreakEnded(
    String userId,
    String name, {
    String? reason,
  }) =>
      log(
        action: AuditAction.userBreakEnded,
        entityType: 'user',
        entityId: userId,
        userId: userId,
        userName: name,
        reason: reason,
      );

  Future<void> logManagerOverride(
    String entityId, {
    String? reason,
    UserEntity? approver,
  }) =>
      log(
        action: AuditAction.managerOverride,
        entityType: 'override',
        entityId: entityId,
        reason: reason,
        approver: approver,
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

  Future<void> logBackupCreated(String backupName) => log(
        action: AuditAction.backupCreated,
        entityType: 'backup',
        entityId: backupName,
      );

  Future<void> logBackupRestored(String backupName) => log(
        action: AuditAction.backupRestored,
        entityType: 'backup',
        entityId: backupName,
      );
}
