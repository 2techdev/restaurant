import 'package:flutter/material.dart';

import 'package:gastrocore_pos/features/reservations/domain/entities/reservation_entity.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

class ReservationStatusChip extends StatelessWidget {
  final ReservationStatus status;
  final bool compact;

  const ReservationStatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, color) = _labelAndColor(l10n, status);
    return Chip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 10 : 12,
          color: color.shade900,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: color.shade100,
      side: BorderSide(color: color.shade300),
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 0)
          : null,
      visualDensity: compact ? VisualDensity.compact : null,
    );
  }

  static (String, MaterialColor) _labelAndColor(
    AppLocalizations l10n,
    ReservationStatus status,
  ) {
    return switch (status) {
      ReservationStatus.pending => (l10n.reservationStatusPending, Colors.orange),
      ReservationStatus.confirmed => (l10n.reservationStatusConfirmed, Colors.blue),
      ReservationStatus.seated => (l10n.reservationStatusSeated, Colors.green),
      ReservationStatus.cancelled => (l10n.reservationStatusCancelled, Colors.red),
      ReservationStatus.noShow => (l10n.reservationStatusNoShow, Colors.grey),
    };
  }
}
