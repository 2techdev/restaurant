/// Left-column order panel — groups ticket items by Gang (1, 2, 3).
///
/// Fine-dining service is coursed: the cashier adds items tagged with a Gang
/// number (Swiss-German for "course"). Each Gang has its own Fire/Hold
/// controls so the kitchen receives courses in order, not all at once.
///
/// Product decision 2026-04-17: cap at [kMaxGangs] = 3. Ordering unassigned
/// items (course = 0) land under a "Bağımsız" (unassigned) section at the top.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/pos_mode/pos_mode.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

/// The currently-focused Gang — new items are added to this Gang by default.
final activeGangProvider = StateProvider<int>((ref) => 1);

/// Client-side "hold" state for Gangs. A Gang in this set is visibly marked
/// as on hold so the operator knows not to fire it yet. v1 does not block
/// the fire action — it's a soft signal. Persistence is intentionally
/// per-session; a reload returns to a clean state.
final heldGangsProvider = StateProvider<Set<int>>((ref) => <int>{});

class OrderPanel extends ConsumerWidget {
  const OrderPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final activeGang = ref.watch(activeGangProvider);

    return Container(
      width: AppTokens.orderPanelWidth,
      color: AppColors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CoverHeader(ticket: ticket),
          _GangChipRow(
            activeGang: activeGang,
            onSelect: (g) =>
                ref.read(activeGangProvider.notifier).state = g,
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: ticket == null
                ? const _EmptyTicketState()
                : _GangGroupedList(ticket: ticket),
          ),
          const Divider(height: 1, color: AppColors.border),
          _TotalsFooter(ticket: ticket),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cover header — table info
// ---------------------------------------------------------------------------

class _CoverHeader extends ConsumerWidget {
  const _CoverHeader({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tableLabel = ticket?.tableId != null
        ? 'Masa ${ticket!.tableId}'
        : 'Paket Servis';
    final cover = ticket?.guestCount ?? 0;
    return Container(
      padding: AppInsets.h16v12,
      color: AppColors.surfaceContainer,
      child: Row(
        children: [
          const Icon(Icons.restaurant_rounded,
              color: AppColors.primary, size: 22),
          const SizedBox(width: AppTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tableLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (ticket != null)
                  Text(
                    '${ticket!.orderNumber} · $cover kişi',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (ticket != null)
            _CoverStepper(
              count: cover,
              onChanged: (next) {
                ref
                    .read(currentTicketProvider.notifier)
                    .updateGuestCount(next);
              },
            ),
        ],
      ),
    );
  }
}

/// Compact ± stepper for the cover (guest) count. Clamped to [1, kMaxCover].
class _CoverStepper extends StatelessWidget {
  const _CoverStepper({required this.count, required this.onChanged});

  static const int _min = 1;
  static const int _max = 20;

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepButton(
            icon: Icons.remove_rounded,
            enabled: count > _min,
            onTap: () => onChanged(count - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_alt_rounded,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  '$count',
                  key: const Key('cover_count_value'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          _stepButton(
            icon: Icons.add_rounded,
            enabled: count < _max,
            onTap: () => onChanged(count + 1),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 24,
        height: 24,
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.primary : AppColors.textDim,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gang chip row — select active Gang
// ---------------------------------------------------------------------------

class _GangChipRow extends StatelessWidget {
  const _GangChipRow({required this.activeGang, required this.onSelect});
  final int activeGang;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space12,
        vertical: AppTokens.space8,
      ),
      child: Row(
        children: [
          for (final g in kGangNumbers) ...[
            Expanded(
              child: _GangChip(
                label: AppLocalizations.of(context).gangLabel(g),
                selected: g == activeGang,
                onTap: () => onSelect(g),
              ),
            ),
            if (g != kGangNumbers.last)
              const SizedBox(width: AppTokens.space8),
          ],
        ],
      ),
    );
  }
}

class _GangChip extends StatelessWidget {
  const _GangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primaryContainer
          : AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: SizedBox(
          height: AppTokens.touchSmall,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gang-grouped item list
// ---------------------------------------------------------------------------

class _GangGroupedList extends ConsumerWidget {
  const _GangGroupedList({required this.ticket});
  final TicketEntity ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byGang = <int, List<OrderItemEntity>>{};
    for (final item in ticket.items) {
      final gang = item.course.clamp(1, kMaxGangs);
      byGang.putIfAbsent(gang, () => []).add(item);
    }
    final held = ref.watch(heldGangsProvider);

    // Render every slot even when empty so the operator sees the structure.
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space8),
      children: [
        for (final g in kGangNumbers)
          _GangSection(
            gang: g,
            items: byGang[g] ?? const [],
            isHeld: held.contains(g),
            onFire: () => _fireGang(context, ref, g),
            onHold: () => _holdGang(context, ref, g),
          ),
      ],
    );
  }

  Future<void> _fireGang(BuildContext ctx, WidgetRef ref, int gang) async {
    final messenger = ScaffoldMessenger.of(ctx);
    final label = AppLocalizations.of(ctx).gangLabel(gang);
    try {
      await ref.read(currentTicketProvider.notifier).fireGang(gang);
      // Clear the "held" mark when fired — the gang is now on its way.
      final held = ref.read(heldGangsProvider);
      if (held.contains(gang)) {
        ref.read(heldGangsProvider.notifier).state = {...held}..remove(gang);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('$label mutfağa gönderildi.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$label gönderilemedi: $e'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  void _holdGang(BuildContext ctx, WidgetRef ref, int gang) {
    final held = ref.read(heldGangsProvider);
    final next = {...held};
    final willHold = !next.contains(gang);
    if (willHold) {
      next.add(gang);
    } else {
      next.remove(gang);
    }
    ref.read(heldGangsProvider.notifier).state = next;
    final label = AppLocalizations.of(ctx).gangLabel(gang);
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(
          willHold
              ? '$label beklemeye alındı.'
              : '$label beklemeden çıkarıldı.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _GangSection extends StatelessWidget {
  const _GangSection({
    required this.gang,
    required this.items,
    required this.isHeld,
    required this.onFire,
    required this.onHold,
  });

  final int gang;
  final List<OrderItemEntity> items;
  final bool isHeld;
  final VoidCallback onFire;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context) {
    final allSent = items.isNotEmpty && items.every((i) => i.sentToKitchen);
    final hasUnsent = items.any((i) => !i.sentToKitchen);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: AppTokens.space8,
              bottom: AppTokens.space4,
            ),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context).gangLabel(gang),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
                if (allSent) ...[
                  const SizedBox(width: AppTokens.space8),
                  const _StatusBadge(
                    label: 'Gönderildi',
                    color: AppColors.green,
                  ),
                ],
                if (isHeld) ...[
                  const SizedBox(width: AppTokens.space8),
                  const _StatusBadge(
                    label: 'Beklemede',
                    color: AppColors.orange,
                  ),
                ],
                const Spacer(),
                if (items.isNotEmpty) ...[
                  _SmallButton(
                    label: isHeld ? 'Devam' : 'Bekle',
                    onTap: onHold,
                    tone: _SmallButtonTone.neutral,
                  ),
                  const SizedBox(width: AppTokens.space4),
                  if (hasUnsent)
                    _SmallButton(
                      label: 'Gönder',
                      onTap: onFire,
                      tone: _SmallButtonTone.primary,
                    ),
                ],
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '—',
                style: TextStyle(
                  color: AppColors.textDim.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            for (final item in items) _OrderItemRow(item: item),
          const Divider(
            height: AppTokens.space16,
            color: AppColors.border,
            indent: 0,
            endIndent: 0,
          ),
        ],
      ),
    );
  }
}

class _OrderItemRow extends ConsumerWidget {
  const _OrderItemRow({required this.item});
  final OrderItemEntity item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final seatCount = ticket?.guestCount ?? 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${item.quantity.toStringAsFixed(0)}×',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (item.modifiers.isNotEmpty)
                  Text(
                    item.modifiers.map((m) => m.modifierName).join(', '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (item.notes != null && item.notes!.isNotEmpty)
                  Text(
                    '“${item.notes}”',
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.space8),
          _SeatChip(
            seatNumber: item.seatNumber,
            seatCount: seatCount,
            onTap: () => _pickSeat(context, ref, item, seatCount),
          ),
          const SizedBox(width: AppTokens.space8),
          Text(
            _formatCHF(item.subtotal),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickSeat(
    BuildContext context,
    WidgetRef ref,
    OrderItemEntity item,
    int seatCount,
  ) async {
    final picked = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      builder: (sheetCtx) => _SeatPickerSheet(
        current: item.seatNumber,
        seatCount: seatCount,
      ),
    );
    if (picked == null && item.seatNumber == null) return;
    await ref
        .read(currentTicketProvider.notifier)
        .updateItemSeat(item.id, picked);
  }

  static String _formatCHF(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }
}

/// Compact badge showing the seat number, or "—" when unassigned.
class _SeatChip extends StatelessWidget {
  const _SeatChip({
    required this.seatNumber,
    required this.seatCount,
    required this.onTap,
  });
  final int? seatNumber;
  final int seatCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = seatNumber == null ? '—' : '#$seatNumber';
    final assigned = seatNumber != null;
    return Material(
      color: assigned
          ? AppColors.primaryContainer.withValues(alpha: 0.22)
          : AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: seatCount <= 0 ? null : onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            label,
            key: ValueKey('seat_chip_${seatNumber ?? 'none'}'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: assigned ? AppColors.primary : AppColors.textDim,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet picker for seat assignment (1..seatCount + "Kaldır").
class _SeatPickerSheet extends StatelessWidget {
  const _SeatPickerSheet({required this.current, required this.seatCount});
  final int? current;
  final int seatCount;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.space16,
          AppTokens.space16,
          AppTokens.space16,
          AppTokens.space16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppTokens.space12),
              child: Text(
                'Koltuk seç',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Wrap(
              spacing: AppTokens.space8,
              runSpacing: AppTokens.space8,
              children: [
                for (var s = 1; s <= seatCount; s++)
                  _pickerButton(
                    context: context,
                    label: '#$s',
                    selected: current == s,
                    value: s,
                  ),
                _pickerButton(
                  context: context,
                  label: 'Kaldır',
                  selected: current == null,
                  value: null,
                  isClear: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerButton({
    required BuildContext context,
    required String label,
    required bool selected,
    required int? value,
    bool isClear = false,
  }) {
    return SizedBox(
      width: 72,
      height: 48,
      child: Material(
        color: selected
            ? AppColors.primaryContainer
            : (isClear
                ? AppColors.surfaceContainerHigh
                : AppColors.surfaceContainerHigh),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: InkWell(
          onTap: () => Navigator.of(context).pop(value),
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Totals footer (subtotal, service charge placeholder, total)
// ---------------------------------------------------------------------------

class _TotalsFooter extends StatelessWidget {
  const _TotalsFooter({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context) {
    final subtotal = ticket?.subtotal ?? 0;
    final total = ticket?.total ?? 0;
    final serviceFee = ticket?.serviceFeeAmount ?? 0;
    final tax = ticket?.taxAmount ?? 0;

    return Container(
      padding: AppInsets.h16v12,
      color: AppColors.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('Ara toplam', subtotal, bold: false),
          if (serviceFee > 0) _row('Servis', serviceFee, bold: false),
          if (tax > 0)
            _row('MWST (dahil)', tax,
                bold: false, dim: true, suffix: 'bilgi'),
          const SizedBox(height: AppTokens.space8),
          _row('Toplam', total, bold: true, large: true),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    int cents, {
    bool bold = false,
    bool dim = false,
    bool large = false,
    String? suffix,
  }) {
    final textStyle = TextStyle(
      fontSize: large ? 17 : 13,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      color: dim
          ? AppColors.textDim
          : (bold ? AppColors.textPrimary : AppColors.textSecondary),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: textStyle),
          if (suffix != null) ...[
            const SizedBox(width: 4),
            Text(
              '· $suffix',
              style: textStyle.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          Text(_formatCHF(cents), style: textStyle),
        ],
      ),
    );
  }

  static String _formatCHF(int cents) {
    final whole = cents ~/ 100;
    final frac = (cents % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

enum _SmallButtonTone { primary, neutral }

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.onTap,
    required this.tone,
  });

  final String label;
  final VoidCallback onTap;
  final _SmallButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final bg = tone == _SmallButtonTone.primary
        ? AppColors.primaryContainer
        : AppColors.surfaceContainerHigh;
    final fg = tone == _SmallButtonTone.primary
        ? Colors.white
        : AppColors.textPrimary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppTokens.radiusXs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusXs),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _EmptyTicketState extends StatelessWidget {
  const _EmptyTicketState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: AppInsets.all16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 48, color: AppColors.textDim),
            SizedBox(height: AppTokens.space8),
            Text(
              'Masa seçin veya ürün ekleyin',
              style: TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
