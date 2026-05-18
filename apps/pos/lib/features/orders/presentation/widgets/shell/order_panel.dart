/// Left-column ticket panel — Kinetic Grid treatment.
///
/// Ticket sidebar with Gang (course) grouping, selected-item left-border,
/// voided strikethrough, and a bold Work Sans balance-due at the bottom.
/// All surfaces use the Kinetic tonal palette; no 1px dividers, only
/// surface shifts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/core/utils/error_handler.dart';
import 'package:gastrocore_pos/features/gang/domain/entities/gang_template_entity.dart';
import 'package:gastrocore_pos/features/gang/presentation/providers/gang_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/open_item_dialog.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/service_charge.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

String _resolveGangLabel(
  BuildContext context,
  RestaurantSettings? settings,
  int oneBasedIndex,
) {
  final overrides = settings?.gangLabels ?? const <String>[];
  final idx = oneBasedIndex - 1;
  if (idx >= 0 && idx < overrides.length) {
    final label = overrides[idx].trim();
    if (label.isNotEmpty) return label;
  }
  return AppLocalizations.of(context).gangLabel(oneBasedIndex);
}

List<int> _gangSlots(RestaurantSettings? settings) {
  final configured = (settings?.maxGangs ?? 3).clamp(1, kGangsUpperBound);
  return [for (var i = 1; i <= configured; i++) i];
}

final activeGangProvider = StateProvider<int>((ref) => 1);
final heldGangsProvider = StateProvider<Set<int>>((ref) => <int>{});

/// Selected ticket item id — drives the left-border highlight.
final selectedTicketItemProvider = StateProvider<String?>((ref) => null);

class OrderPanel extends ConsumerWidget {
  const OrderPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final activeGang = ref.watch(activeGangProvider);
    final settings = ref.watch(restaurantSettingsProvider).valueOrNull;
    final gangsEnabled = settings?.gangsEnabled ?? false;
    final slots = _gangSlots(settings);

    return Container(
      width: AppTokens.orderPanelWidth,
      color: GcColors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ticket != null) _CoverHeader(ticket: ticket),
          if (gangsEnabled)
            _GangChipRow(
              slots: slots,
              activeGang: activeGang,
              settings: settings,
              onSelect: (g) =>
                  ref.read(activeGangProvider.notifier).state = g,
            ),
          Expanded(
            child: ColoredBox(
              color: GcColors.surfaceContainerLowest,
              child: ticket == null
                  ? const _EmptyTicketState()
                  : gangsEnabled
                      ? _GangGroupedList(
                          ticket: ticket,
                          slots: slots,
                          settings: settings,
                        )
                      : _FlatItemList(ticket: ticket),
            ),
          ),
          if (ticket != null) const _OpenItemRow(),
          _TotalsFooter(ticket: ticket),
        ],
      ),
    );
  }
}

/// "Açık Tutar" call-to-action — adds an ad-hoc charge to the active
/// ticket without going through the menu (catering, custom requests,
/// anything not on the product grid).
class _OpenItemRow extends StatelessWidget {
  const _OpenItemRow();

  String _label(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    switch (lang) {
      case 'de':
        return 'Offener Betrag';
      case 'en':
        return 'Open Item';
      case 'fr':
        return 'Montant libre';
      case 'it':
        return 'Importo libero';
      default:
        return 'Açık Tutar';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GcColors.surfaceContainer,
      child: InkWell(
        onTap: () => showOpenItemDialog(context),
        child: Padding(
          padding: AppInsets.h16v12,
          child: Row(
            children: [
              const Icon(
                Icons.add_circle_outline_rounded,
                color: GcColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _label(context),
                style: GcText.button.copyWith(
                  fontSize: 13,
                  color: GcColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — Ticket # / Table / Covers
// ---------------------------------------------------------------------------

class _CoverHeader extends ConsumerWidget {
  const _CoverHeader({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tableLabel = ticket?.tableId != null
        ? 'MASA ${ticket!.tableId}'
        : 'PAKET SERVİS';
    final cover = ticket?.guestCount ?? 0;
    return Container(
      padding: AppInsets.h16v12,
      color: GcColors.surfaceContainer,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ticket != null)
                  Text(
                    'TICKET #${ticket!.orderNumber}',
                    style: GcText.labelTiny,
                  ),
                Text(tableLabel, style: GcText.headline),
                if (ticket != null)
                  Text(
                    '$cover KİŞİ',
                    style: GcText.labelTiny,
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

class _CoverStepper extends StatelessWidget {
  const _CoverStepper({required this.count, required this.onChanged});

  static const int _min = 1;
  static const int _max = 20;

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GcColors.surfaceContainerLowest,
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
            child: Text(
              '$count',
              key: const Key('cover_count_value'),
              style: GcText.button.copyWith(
                fontSize: 14,
                color: GcColors.primary,
              ),
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
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? GcColors.primary : GcColors.outlineVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gang chip row
// ---------------------------------------------------------------------------

class _GangChipRow extends StatelessWidget {
  const _GangChipRow({
    required this.slots,
    required this.activeGang,
    required this.settings,
    required this.onSelect,
  });
  final List<int> slots;
  final int activeGang;
  final RestaurantSettings? settings;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final lastSlot = slots.isEmpty ? 0 : slots.last;
    return Container(
      color: GcColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space8,
        vertical: AppTokens.space8,
      ),
      child: Row(
        children: [
          for (final g in slots) ...[
            Expanded(
              child: _GangChip(
                label: _resolveGangLabel(context, settings, g),
                selected: g == activeGang,
                onTap: () => onSelect(g),
              ),
            ),
            if (g != lastSlot) const SizedBox(width: 4),
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
      color: selected ? GcColors.primary : GcColors.surfaceContainerLowest,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Center(
            child: Text(
              label.toUpperCase(),
              style: GcText.button.copyWith(
                fontSize: 12,
                color: selected ? GcColors.onPrimary : GcColors.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gang-grouped list
// ---------------------------------------------------------------------------

class _GangGroupedList extends ConsumerWidget {
  const _GangGroupedList({
    required this.ticket,
    required this.slots,
    required this.settings,
  });
  final TicketEntity ticket;
  final List<int> slots;
  final RestaurantSettings? settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxSlot = slots.isEmpty ? 1 : slots.last;
    final byGang = <int, List<OrderItemEntity>>{};
    for (final item in ticket.items) {
      final gang = item.course.clamp(1, maxSlot);
      byGang.putIfAbsent(gang, () => []).add(item);
    }
    final held = ref.watch(heldGangsProvider);

    // Build a course → GangOrderStatus map by joining:
    //   gang_templates.sortOrder  →  order_gang_states.gangTemplateId.status
    // Gangs that have no state row yet fall through as null, which the
    // section treats as "pending" / not-yet-fired.
    final templates = ref.watch(gangTemplatesProvider).valueOrNull ?? const [];
    final states = ref
            .watch(orderGangStatesProvider(ticket.id))
            .valueOrNull ??
        const <String, OrderGangStateEntity>{};
    final statusByCourse = <int, GangOrderStatus>{};
    if (templates.isNotEmpty && states.isNotEmpty) {
      final sortByTemplateId = <String, int>{
        for (final t in templates) t.id: t.sortOrder,
      };
      for (final s in states.values) {
        final course = sortByTemplateId[s.gangTemplateId];
        if (course != null) statusByCourse[course] = s.status;
      }
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final g in slots)
          _GangSection(
            gang: g,
            label: _resolveGangLabel(context, settings, g),
            items: byGang[g] ?? const [],
            isHeld: held.contains(g),
            status: statusByCourse[g],
            onFire: () => _fireGang(context, ref, g),
            onHold: () => _holdGang(context, ref, g),
            onServe: () => _serveGang(context, ref, g),
          ),
      ],
    );
  }

  Future<void> _fireGang(BuildContext ctx, WidgetRef ref, int gang) async {
    final label = _resolveGangLabel(ctx, settings, gang);
    final ok = await ErrorHandler.run(
      ctx,
      () => ref.read(currentTicketProvider.notifier).fireGang(gang),
      onSuccess: '$label mutfağa gönderildi.',
      failureLabel: '$label gönderilemedi',
    );
    if (ok) {
      final held = ref.read(heldGangsProvider);
      if (held.contains(gang)) {
        ref.read(heldGangsProvider.notifier).state = {...held}..remove(gang);
      }
    }
  }

  Future<void> _serveGang(BuildContext ctx, WidgetRef ref, int gang) async {
    final label = _resolveGangLabel(ctx, settings, gang);
    await ErrorHandler.run(
      ctx,
      () => ref.read(currentTicketProvider.notifier).markGangServed(gang),
      onSuccess: '$label servis edildi.',
      failureLabel: '$label servis edilemedi',
    );
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
    final label = _resolveGangLabel(ctx, settings, gang);
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

class _FlatItemList extends StatelessWidget {
  const _FlatItemList({required this.ticket});
  final TicketEntity ticket;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final item in ticket.items) _OrderItemRow(item: item),
      ],
    );
  }
}

class _GangSection extends StatelessWidget {
  const _GangSection({
    required this.gang,
    required this.label,
    required this.items,
    required this.isHeld,
    required this.status,
    required this.onFire,
    required this.onHold,
    required this.onServe,
  });

  final int gang;
  final String label;
  final List<OrderItemEntity> items;
  final bool isHeld;
  final GangOrderStatus? status;
  final VoidCallback onFire;
  final VoidCallback onHold;
  final VoidCallback onServe;

  @override
  Widget build(BuildContext context) {
    final allSent = items.isNotEmpty && items.every((i) => i.sentToKitchen);
    final hasUnsent = items.any((i) => !i.sentToKitchen);
    final isServed = status == GangOrderStatus.served;
    // Show the SERVE action once the kitchen has acknowledged the gang
    // (fired / inPrep / ready) and it has not yet been delivered.
    final canServe = !isServed &&
        allSent &&
        status != null &&
        status != GangOrderStatus.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: GcColors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space12,
            vertical: AppTokens.space8,
          ),
          child: Row(
            children: [
              Text(
                label.toUpperCase(),
                style: GcText.labelTiny.copyWith(color: GcColors.onSurface),
              ),
              if (isServed) ...[
                const SizedBox(width: AppTokens.space8),
                const _StatusBadge(
                  label: 'SERVİS EDİLDİ',
                  color: GcColors.catGreen,
                ),
              ] else if (allSent) ...[
                const SizedBox(width: AppTokens.space8),
                const _StatusBadge(
                  label: 'GÖNDERİLDİ',
                  color: GcColors.catGreen,
                ),
              ],
              if (isHeld) ...[
                const SizedBox(width: AppTokens.space8),
                const _StatusBadge(
                  label: 'BEKLEMEDE',
                  color: GcColors.catOrange,
                ),
              ],
              const Spacer(),
              if (items.isNotEmpty && !isServed) ...[
                _SmallButton(
                  label: isHeld ? 'DEVAM' : 'BEKLE',
                  onTap: onHold,
                  tone: _SmallButtonTone.neutral,
                ),
                const SizedBox(width: 4),
                if (hasUnsent)
                  _SmallButton(
                    label: 'GÖNDER',
                    onTap: onFire,
                    tone: _SmallButtonTone.primary,
                  )
                else if (canServe)
                  _SmallButton(
                    label: 'SERVİS ET',
                    onTap: onServe,
                    tone: _SmallButtonTone.primary,
                  ),
              ],
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space12,
              vertical: 8,
            ),
            child: Text(
              '—',
              style: GcText.bodySmall
                  .copyWith(color: GcColors.outlineVariant),
            ),
          )
        else
          for (final item in items) _OrderItemRow(item: item),
      ],
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
    final selectedId = ref.watch(selectedTicketItemProvider);
    final isSelected = selectedId == item.id;
    final isVoid = item.status == OrderItemStatus.voidStatus;

    final fg = isVoid ? GcColors.error : GcColors.onSurface;
    final qtyFg =
        isSelected && !isVoid ? GcColors.primary : fg;

    return Material(
      color: _rowFill(isSelected, isVoid),
      child: InkWell(
        onTap: () {
          ref.read(selectedTicketItemProvider.notifier).state =
              isSelected ? null : item.id;
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color:
                    isSelected ? GcColors.primary : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space12,
            vertical: 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${item.quantity.toStringAsFixed(0)}×',
                  style: GcText.price.copyWith(
                    fontSize: 14,
                    color: qtyFg,
                    decoration:
                        isVoid ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              Expanded(
                child: Opacity(
                  opacity: isVoid ? 0.6 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: GcText.body.copyWith(
                          color: fg,
                          decoration: isVoid
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (isVoid)
                        Text(
                          'VOID — MUTFAK',
                          style: GcText.labelTiny
                              .copyWith(color: GcColors.error),
                        ),
                      if (item.modifiers.isNotEmpty)
                        Text(
                          item.modifiers
                              .map((m) => '+ ${m.modifierName}')
                              .join('  '),
                          style: GcText.bodySmall,
                        ),
                      if (item.notes != null && item.notes!.isNotEmpty)
                        Text(
                          '"${item.notes}"',
                          style: GcText.bodySmall.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
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
                style: GcText.price.copyWith(
                  color: fg,
                  decoration: isVoid ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _rowFill(bool selected, bool isVoid) {
    if (isVoid) return GcColors.surfaceContainerLowest;
    if (selected) return GcColors.surfaceContainerHighest;
    return GcColors.surfaceContainerLowest;
  }

  Future<void> _pickSeat(
    BuildContext context,
    WidgetRef ref,
    OrderItemEntity item,
    int seatCount,
  ) async {
    final picked = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: GcColors.surfaceContainerLowest,
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
      color: assigned ? GcColors.primary : GcColors.surfaceContainerHigh,
      child: InkWell(
        onTap: seatCount <= 0 ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            label,
            key: ValueKey('seat_chip_${seatNumber ?? 'none'}'),
            style: GcText.button.copyWith(
              fontSize: 11,
              color: assigned ? GcColors.onPrimary : GcColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatPickerSheet extends StatelessWidget {
  const _SeatPickerSheet({required this.current, required this.seatCount});
  final int? current;
  final int seatCount;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppTokens.space12),
              child: Text('KOLTUK SEÇ', style: GcText.headline),
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
  }) {
    return SizedBox(
      width: 72,
      height: 48,
      child: Material(
        color: selected ? GcColors.primary : GcColors.surfaceContainerHigh,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(value),
          child: Center(
            child: Text(
              label,
              style: GcText.button.copyWith(
                color: selected ? GcColors.onPrimary : GcColors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Totals footer — Balance Due in Work Sans Black
// ---------------------------------------------------------------------------

class _TotalsFooter extends ConsumerWidget {
  const _TotalsFooter({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtotal = ticket?.subtotal ?? 0;
    final tax = ticket?.taxAmount ?? 0;

    // POS v2: show Netto / Service / MWST / Zu bezahlen as an inline
    // block. The subtotal field already stores the gross (MWST inkl).
    // Service charge is derived live from RestaurantSettings here —
    // ticket.serviceFeeAmount stays as the persisted value stamped at
    // payment time so historical receipts don't drift.
    final settings = ref.watch(restaurantSettingsProvider).valueOrNull;
    final liveServiceFee = computeServiceFeeAmount(
      subtotalCents: subtotal,
      settings: settings,
    );
    // Prefer the persisted ticket value once it has been stamped (>0),
    // otherwise show the live preview as the operator builds the cart.
    final serviceFee = (ticket?.serviceFeeAmount ?? 0) > 0
        ? ticket!.serviceFeeAmount
        : liveServiceFee;

    final ticketTotal = ticket?.total ?? 0;
    // Live preview while building the cart: ticket.total doesn't include
    // the unstamped service charge, so add it here so the cashier sees
    // the real number the customer will pay.
    final total = ticketTotal +
        (ticket != null && ticket!.serviceFeeAmount == 0
            ? liveServiceFee
            : 0);

    final netto = subtotal - tax;
    return Container(
      color: GcColors.surfaceContainerHigh,
      padding: AppInsets.h16v12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('Netto', netto),
          if (serviceFee > 0)
            _row(
              settings != null && settings.serviceChargePercent > 0
                  ? 'Service ${_fmtPercent(settings.serviceChargePercent)}%'
                  : 'Service',
              serviceFee,
            ),
          if (tax > 0) _row('MWST 8.1 % (inkl.)', tax, dim: true),
          const SizedBox(height: AppTokens.space8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: GcColors.ghostBorder, width: 1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Zu bezahlen', style: GcText.labelTiny),
                const Spacer(),
                Text(
                  _formatCHF(total),
                  style: GcText.displayBlack,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtPercent(double pct) {
    return pct.truncateToDouble() == pct
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);
  }

  Widget _row(String label, int cents, {bool dim = false}) {
    final style = GcText.bodySmall.copyWith(
      color: dim ? GcColors.outline : GcColors.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(_formatCHF(cents), style: style),
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
        ? GcColors.primary
        : GcColors.surfaceContainerLowest;
    final fg = tone == _SmallButtonTone.primary
        ? GcColors.onPrimary
        : GcColors.onSurface;
    // a11y: the gang-row buttons (GÖNDER, SERVİS ET, BEKLE, DEVAM) are
    // styled as Material + InkWell without a default button semantic.
    // Mark them explicitly so TalkBack / VoiceOver announces them as
    // buttons and exposes the onTap action.
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: bg,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: ExcludeSemantics(
              child: Text(
                label,
                style: GcText.button.copyWith(fontSize: 11, color: fg),
              ),
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
      color: color,
      child: Text(
        label,
        style: GcText.button.copyWith(
          fontSize: 10,
          color: GcColors.onPrimary,
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
                size: 48, color: GcColors.outlineVariant),
            SizedBox(height: AppTokens.space8),
            Text(
              'Masa seçin veya ürün ekleyin',
              style: GcText.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
