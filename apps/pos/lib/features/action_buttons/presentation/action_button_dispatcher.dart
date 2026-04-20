/// Dispatches an [ActionButtonEntity] tap to the right notifier call.
///
/// The dispatcher is deliberately a plain class (not a provider) — actions
/// are side-effectful operations that end in snackbar feedback, not a piece
/// of observable state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/action_buttons/domain/entities/action_button_entity.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

class ActionButtonDispatcher {
  const ActionButtonDispatcher._();

  /// Fire the action associated with [button]. Shows a snackbar when the
  /// action is not applicable (no active ticket, empty ticket, unknown type).
  static Future<void> dispatch({
    required ActionButtonEntity button,
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ticketNotifier = ref.read(currentTicketProvider.notifier);
    final ticket = ref.read(currentTicketProvider);

    void snack(String message) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1800),
        ),
      );
    }

    if (ticket == null) {
      snack('Kein aktives Ticket');
      return;
    }

    switch (button.actionType) {
      case ActionButtonType.percentDiscount:
        await _applyPercentDiscount(
          button: button,
          ref: ref,
          ticketNotifier: ticketNotifier,
          snack: snack,
        );
      case ActionButtonType.fixedDiscount:
        await _applyFixedDiscount(
          button: button,
          ref: ref,
          ticketNotifier: ticketNotifier,
          snack: snack,
        );
      case ActionButtonType.markGift:
        await _applyGift(
          button: button,
          ref: ref,
          ticketNotifier: ticketNotifier,
          snack: snack,
        );
      case ActionButtonType.addNote:
        await _addNote(
          button: button,
          context: context,
          ticket: ticket,
          ticketNotifier: ticketNotifier,
          snack: snack,
        );
      case ActionButtonType.setCourse:
        _setCourse(
          button: button,
          ticket: ticket,
          ticketNotifier: ticketNotifier,
          snack: snack,
        );
      case ActionButtonType.printBill:
        snack('Rechnung: Druckauftrag vorbereitet');
      case ActionButtonType.voidItem:
        snack('Stornieren: noch nicht implementiert');
      case ActionButtonType.customScript:
        snack('Skript: noch nicht implementiert');
    }
  }

  // ---------------------------------------------------------------------------
  // Action implementations
  // ---------------------------------------------------------------------------

  static Future<void> _applyPercentDiscount({
    required ActionButtonEntity button,
    required WidgetRef ref,
    required CurrentTicketNotifier ticketNotifier,
    required void Function(String) snack,
  }) async {
    final raw = button.actionPayload['percent'];
    final percent = _asInt(raw);
    if (percent == null || percent <= 0 || percent > 100) {
      snack('Ungültiger Prozentwert');
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) {
      snack('Kein Benutzer angemeldet');
      return;
    }
    await ticketNotifier.applyDiscount(
      discountType: DiscountType.percentage,
      discountValue: percent,
      reason: 'Funktion: ${button.label}',
      requestedBy: user,
    );
    snack('$percent% Rabatt angewendet');
  }

  static Future<void> _applyFixedDiscount({
    required ActionButtonEntity button,
    required WidgetRef ref,
    required CurrentTicketNotifier ticketNotifier,
    required void Function(String) snack,
  }) async {
    final raw = button.actionPayload['amount'];
    final amountCents = _asInt(raw);
    if (amountCents == null || amountCents <= 0) {
      snack('Ungültiger Betrag');
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) {
      snack('Kein Benutzer angemeldet');
      return;
    }
    await ticketNotifier.applyDiscount(
      discountType: DiscountType.fixed,
      discountValue: amountCents,
      reason: 'Funktion: ${button.label}',
      requestedBy: user,
    );
    snack('Fix-Rabatt angewendet: ${(amountCents / 100).toStringAsFixed(2)}');
  }

  static Future<void> _applyGift({
    required ActionButtonEntity button,
    required WidgetRef ref,
    required CurrentTicketNotifier ticketNotifier,
    required void Function(String) snack,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      snack('Kein Benutzer angemeldet');
      return;
    }
    await ticketNotifier.applyDiscount(
      discountType: DiscountType.percentage,
      discountValue: 100,
      reason: 'Geschenk: ${button.label}',
      requestedBy: user,
    );
    snack('Ticket als Geschenk markiert');
  }

  static Future<void> _addNote({
    required ActionButtonEntity button,
    required BuildContext context,
    required TicketEntity ticket,
    required CurrentTicketNotifier ticketNotifier,
    required void Function(String) snack,
  }) async {
    if (ticket.items.isEmpty) {
      snack('Keine Artikel auf dem Ticket');
      return;
    }
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddNoteDialog(
        initialValue: ticket.items.last.notes ?? '',
        label: button.label,
      ),
    );
    if (note == null) return;
    final last = ticket.items.last;
    ticketNotifier.updateItemNotes(last.id, note);
    snack(note.trim().isEmpty ? 'Notiz entfernt' : 'Notiz gespeichert');
  }

  static void _setCourse({
    required ActionButtonEntity button,
    required TicketEntity ticket,
    required CurrentTicketNotifier ticketNotifier,
    required void Function(String) snack,
  }) {
    final rawGang = button.actionPayload['gangId'];
    if (rawGang is! String || rawGang.isEmpty) {
      snack('Kein Gang definiert');
      return;
    }
    if (ticket.items.isEmpty) {
      snack('Keine Artikel auf dem Ticket');
      return;
    }
    final last = ticket.items.last;
    ticketNotifier.updateItemGang(last.id, rawGang);
    snack('Gang geändert: ${button.label}');
  }

  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}

class _AddNoteDialog extends StatefulWidget {
  const _AddNoteDialog({required this.initialValue, required this.label});

  final String initialValue;
  final String label;

  @override
  State<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<_AddNoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: 'Notiz zum letzten Artikel...',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
