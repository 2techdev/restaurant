/// Consistent user-facing feedback for async operations.
///
/// Repositories throw; the UI layer has to decide what to say. Before this
/// util every feature screen re-implemented the same try/catch/SnackBar
/// wrapper, so error copy and colour drifted. [ErrorHandler] gives all
/// screens one entry point:
///
///   await ErrorHandler.run(
///     context,
///     () => repo.save(entity),
///     onSuccess: 'Gespeichert.',
///     failureLabel: 'Konnte nicht speichern',
///   );
///
/// The helper reads the [ScaffoldMessenger] before the await, so we never
/// touch a stale BuildContext after work completes.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/error/failures.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';

/// Static helpers — the util is never instantiated.
abstract final class ErrorHandler {
  /// Show a short success snackbar.
  static void showSuccess(BuildContext context, String message) {
    _show(context, message, backgroundColor: null);
  }

  /// Show an error snackbar. [error] can be anything thrown from a
  /// repository; the util maps [Failure] subtypes to friendly copy and
  /// falls back to [fallback] (or [error.toString()]) for raw exceptions.
  static void showError(
    BuildContext context,
    Object error, {
    String? fallback,
  }) {
    final message = describe(error, fallback: fallback);
    _show(context, message, backgroundColor: GcColors.error);
  }

  /// Run [action], surface a success snackbar on completion and an error
  /// snackbar on throw. Returns `true` if [action] completed normally.
  ///
  /// [failureLabel] is prepended to the error description so the user sees
  /// which operation failed (e.g. "Konnte nicht speichern: ..."), matching
  /// the house pattern used across the POS shell.
  static Future<bool> run(
    BuildContext context,
    Future<void> Function() action, {
    String? onSuccess,
    String? failureLabel,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      if (messenger != null && onSuccess != null) {
        _showVia(messenger, onSuccess, backgroundColor: null);
      }
      return true;
    } catch (e) {
      if (messenger != null) {
        final prefix = failureLabel == null ? '' : '$failureLabel: ';
        final message = '$prefix${describe(e)}';
        _showVia(messenger, message, backgroundColor: GcColors.error);
      }
      return false;
    }
  }

  /// Map any error to a user-facing string. Kept public so features can
  /// reuse the mapping without showing a snackbar (e.g. inside dialogs).
  static String describe(Object error, {String? fallback}) {
    if (error is Failure) {
      return error.message;
    }
    if (fallback != null && fallback.isNotEmpty) return fallback;
    // Keep the raw toString for developer diagnostics — the pilot runs in
    // operator-sight-only mode so leaking the exception type is fine and
    // dramatically improves triage during early adoption.
    return error.toString();
  }

  static void _show(
    BuildContext context,
    String message, {
    required Color? backgroundColor,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _showVia(messenger, message, backgroundColor: backgroundColor);
  }

  static void _showVia(
    ScaffoldMessengerState messenger,
    String message, {
    required Color? backgroundColor,
  }) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.fixed,
        ),
      );
  }
}
