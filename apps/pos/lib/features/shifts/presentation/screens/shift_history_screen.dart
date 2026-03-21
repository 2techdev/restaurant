/// Shift History Screen for GastroCore POS.
///
/// Displays all past shifts for the tenant in a scrollable list,
/// with optional filtering to show only this device's shifts.
/// Each row shows date/time range, cashier, device, total sales,
/// order count, status badge, and cash variance (if closed).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';

// ---------------------------------------------------------------------------
// Shift History Screen
// ---------------------------------------------------------------------------

class ShiftHistoryScreen extends ConsumerStatefulWidget {
  const ShiftHistoryScreen({super.key});

  @override
  ConsumerState<ShiftHistoryScreen> createState() =>
      _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends ConsumerState<ShiftHistoryScreen> {
  bool _showOnlyThisDevice = false;

  @override
  Widget build(BuildContext context) {
    final currentDeviceId = ref.watch(deviceIdProvider);

    final shiftsAsync = _showOnlyThisDevice
        ? ref.watch(deviceShiftsProvider)
        : ref.watch(shiftHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(context, currentDeviceId),
          Expanded(
            child: shiftsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Error loading shifts: $e',
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
              data: (shifts) => shifts.isEmpty
                  ? _buildEmptyState()
                  : _buildShiftList(shifts),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar(BuildContext context, String currentDeviceId) {
    return Container(
      height: 56,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Back button
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => context.pop(),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Shift History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          // Device filter toggle
          GestureDetector(
            onTap: () =>
                setState(() => _showOnlyThisDevice = !_showOnlyThisDevice),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _showOnlyThisDevice
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: _showOnlyThisDevice
                    ? Border.all(
                        color: AppColors.accent.withValues(alpha: 0.4))
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.point_of_sale,
                    size: 14,
                    color: _showOnlyThisDevice
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showOnlyThisDevice
                        ? 'This terminal only'
                        : 'All terminals',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _showOnlyThisDevice
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Refresh button
          Material(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                ref.invalidate(shiftHistoryProvider);
                ref.invalidate(deviceShiftsProvider);
              },
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Shift list
  // -------------------------------------------------------------------------

  Widget _buildShiftList(List<ShiftEntity> shifts) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: shifts.length,
      itemBuilder: (context, index) => _ShiftHistoryCard(shift: shifts[index]),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 48, color: AppColors.textDim),
          SizedBox(height: 16),
          Text(
            'No shifts found',
            style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
          ),
          SizedBox(height: 8),
          Text(
            'Shifts appear here after they are opened.',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shift history card
// ---------------------------------------------------------------------------

class _ShiftHistoryCard extends StatelessWidget {
  const _ShiftHistoryCard({required this.shift});

  final ShiftEntity shift;

  @override
  Widget build(BuildContext context) {
    final isOpen = shift.status == ShiftStatus.open;
    final openTime = _fmtTime(shift.openedAt);
    final closeTime =
        shift.closedAt != null ? _fmtTime(shift.closedAt!) : '—';
    final dateStr = _fmtDate(shift.openedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: isOpen
            ? Border.all(
                color: AppColors.green.withValues(alpha: 0.3),
                width: 1,
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Status badge
                _StatusBadge(status: shift.status),
                const SizedBox(width: 12),
                // Date
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$openTime – $closeTime',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                // Device chip
                _InfoChip(
                  icon: Icons.point_of_sale,
                  label: shift.deviceId,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Stats row
            Row(
              children: [
                _StatCell(
                  label: 'Total Sales',
                  value: _fmtCents(shift.totalSales),
                  valueColor: AppColors.green,
                  large: true,
                ),
                const SizedBox(width: 24),
                _StatCell(
                  label: 'Orders',
                  value: shift.totalOrders.toString(),
                ),
                const SizedBox(width: 24),
                _StatCell(
                  label: 'Opening Cash',
                  value: _fmtCents(shift.openingCash),
                ),
                if (shift.difference != null) ...[
                  const SizedBox(width: 24),
                  _StatCell(
                    label: 'Variance',
                    value: _fmtVariance(shift.difference!),
                    valueColor: _varianceColor(shift.difference!),
                  ),
                ],
                const Spacer(),
                // User chip
                _InfoChip(
                  icon: Icons.person_outline,
                  label: shift.userId.length > 8
                      ? '…${shift.userId.substring(shift.userId.length - 6)}'
                      : shift.userId,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  String _fmtCents(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }

  String _fmtVariance(int cents) {
    final prefix = cents >= 0 ? '+' : '';
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    final sign = cents < 0 ? '-' : '';
    return '$prefix${sign}CHF $whole.$frac';
  }

  Color _varianceColor(int cents) {
    if (cents == 0) return AppColors.green;
    if (cents < 0) return AppColors.red;
    return AppColors.orange;
  }
}

// ---------------------------------------------------------------------------
// Reusable sub-widgets
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ShiftStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      ShiftStatus.open => ('OPEN', AppColors.green, AppColors.greenDim),
      ShiftStatus.closing => (
          'CLOSING',
          AppColors.orange,
          AppColors.orangeDim
        ),
      ShiftStatus.closed => ('CLOSED', AppColors.textDim, AppColors.surface),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textDim),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.valueColor,
    this.large = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textDim,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: large ? 18 : 14,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
