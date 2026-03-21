import 'package:flutter/material.dart';

import 'package:gastrocore_pos/features/reservations/domain/entities/reservation_entity.dart';

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
    final (label, color) = _labelAndColor(status);
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

  static (String, MaterialColor) _labelAndColor(ReservationStatus status) {
    return switch (status) {
      ReservationStatus.pending => ('Pending', Colors.orange),
      ReservationStatus.confirmed => ('Confirmed', Colors.blue),
      ReservationStatus.seated => ('Seated', Colors.green),
      ReservationStatus.cancelled => ('Cancelled', Colors.red),
      ReservationStatus.noShow => ('No-Show', Colors.grey),
    };
  }
}
