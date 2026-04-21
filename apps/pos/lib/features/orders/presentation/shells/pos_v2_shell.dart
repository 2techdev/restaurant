/// POS v2 shell — pixel-for-pixel port of the HTML/React reference at
/// `E:/Project/Restaurant/.design/pos-v2/POS.html` (+ `pos/parts.jsx`).
///
/// The shell is a top-level five-zone grid mirroring the CSS
/// `grid-template-areas: "rail topbar topbar" / "rail order menu" / "rail footer menu"`:
///
///   * [_Rail]         — 80dp dark navigation rail (full height).
///   * [_TopBar]       — 60dp chrome header (brand, ticket, mode switch, user).
///   * [_OrderPanel]   — 380dp white ticket column (BESTELLUNG + totals).
///   * [_Footer]       — 72dp white footer under the order column only.
///   * [_MenuArea]     — remainder: 300dp cats / Schnellmenü / items grid.
///
/// No wrapping scaffold decoration, no Material theming — this layer owns
/// every colour, padding, and font explicitly to guarantee the visual match.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/features/action_buttons/domain/entities/action_button_entity.dart';
import 'package:gastrocore_pos/features/action_buttons/presentation/widgets/action_button_strip.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/theme/pos_v2_theme.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/favorites_bar.dart'
    show allActiveProductsProvider;
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/order_panel.dart'
    show activeGangProvider, heldGangsProvider;
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';

// ---------------------------------------------------------------------------
// Local providers — selection state that the panel needs but no global store
// tracks yet. Scoped to this shell.
// ---------------------------------------------------------------------------

/// Currently-highlighted line item (`line-item.selected` in the CSS).
final v2SelectedLineIdProvider = StateProvider<String?>((ref) => null);

/// Active rail destination — matches the `.rail-btn.active` state. Pilot
/// default is `sale` (Verkauf).
final v2RailActiveProvider = StateProvider<String>((ref) => 'sale');

/// Tweaks — show product image thumbnails on grid cards.
final productImagesEnabledProvider = StateProvider<bool>((ref) => false);

/// Tweaks — palette selector. Only Ivory styled for pilot; Midnight reserved.
enum PosPalette { ivory, midnight }

final posPaletteProvider =
    StateProvider<PosPalette>((ref) => PosPalette.ivory);

// ---------------------------------------------------------------------------
// Root shell
// ---------------------------------------------------------------------------

class PosV2Shell extends ConsumerWidget {
  const PosV2Shell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: context.v2.bg,
      child: const SafeArea(
        child: _V2Layout(),
      ),
    );
  }
}

/// 3-column × 3-row grid: rail spans full height, topbar spans cols 2–3,
/// order + footer stack in col 2, menu fills cols 2–3 rows 2–3 on the right.
///
/// In left-hand mode the rail + order column flip to the right edge so a
/// left-handed operator's tapping hand stays over the high-frequency
/// controls. Mirroring is a straight row-children reversal — no
/// [Directionality] swap — so text and numerals keep their natural RTL /
/// LTR layout regardless of operator handedness.
class _V2Layout extends ConsumerWidget {
  const _V2Layout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(appSettingsProvider).valueOrNull ??
        const AppSettings();
    final leftHanded = appSettings.handedness == AppHandedness.left;

    return LayoutBuilder(
      builder: (context, bc) {
        // Responsive column widths matching the CSS breakpoints.
        final w = bc.maxWidth;
        final railW = w >= 1400 ? 80.0 : (w >= 1200 ? 72.0 : 64.0);
        final orderW = w >= 1400 ? 380.0 : (w >= 1200 ? 340.0 : 320.0);

        final railSlot = SizedBox(width: railW, child: const _Rail());
        final orderSlot = SizedBox(
          width: orderW,
          child: _OrderColumn(leftHanded: leftHanded),
        );
        const menuSlot = Expanded(child: _MenuArea());

        final innerRowChildren = leftHanded
            ? <Widget>[menuSlot, orderSlot]
            : <Widget>[orderSlot, menuSlot];

        final mainColumn = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60, child: _TopBar()),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: innerRowChildren,
                ),
              ),
            ],
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: leftHanded
              ? <Widget>[mainColumn, railSlot]
              : <Widget>[railSlot, mainColumn],
        );
      },
    );
  }
}

/// Order column = order panel stacked on top of the compact footer.
class _OrderColumn extends StatelessWidget {
  const _OrderColumn({this.leftHanded = false});

  /// When true, the hairline divider sits on the order column's left edge
  /// (facing the menu area on its right); the default places it on the
  /// right edge (right-hand mode).
  final bool leftHanded;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    final side = BorderSide(color: v2.line);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: v2.surface,
        border: leftHanded ? Border(left: side) : Border(right: side),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _OrderPanel()),
          SizedBox(height: 72, child: _Footer()),
        ],
      ),
    );
  }
}

// ===========================================================================
// RAIL  — parts.jsx `Rail`
// ===========================================================================

class _Rail extends ConsumerWidget {
  const _Rail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(v2RailActiveProvider);
    return Container(
      color: context.v2.chrome,
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
      child: Column(
        children: [
          const _RailLogo(),
          const SizedBox(height: 10),
          _RailBtn(
            id: 'tables',
            label: 'Tische',
            icon: Icons.table_restaurant_outlined,
            active: active == 'tables',
            onTap: () {
              ref.read(v2RailActiveProvider.notifier).state = 'tables';
              context.push(AppRoutes.tables);
            },
          ),
          _RailBtn(
            id: 'sale',
            label: 'Verkauf',
            icon: Icons.point_of_sale_outlined,
            active: active == 'sale',
            onTap: () =>
                ref.read(v2RailActiveProvider.notifier).state = 'sale',
          ),
          _RailBtn(
            id: 'bill',
            label: 'Bon',
            icon: Icons.receipt_long_outlined,
            active: active == 'bill',
            onTap: () =>
                ref.read(v2RailActiveProvider.notifier).state = 'bill',
          ),
          _RailBtn(
            id: 'cash',
            label: 'Kasse',
            icon: Icons.payments_outlined,
            active: active == 'cash',
            onTap: () =>
                ref.read(v2RailActiveProvider.notifier).state = 'cash',
          ),
          _RailBtn(
            id: 'menu',
            label: 'Menü',
            icon: Icons.restaurant_menu_outlined,
            active: active == 'menu',
            onTap: () =>
                ref.read(v2RailActiveProvider.notifier).state = 'menu',
          ),
          _RailBtn(
            id: 'report',
            label: 'Bericht',
            icon: Icons.insert_chart_outlined,
            active: active == 'report',
            onTap: () =>
                ref.read(v2RailActiveProvider.notifier).state = 'report',
          ),
          const Spacer(),
          _RailBtn(
            id: 'cancel',
            label: 'Stornieren',
            icon: Icons.block_outlined,
            danger: true,
            active: false,
            onTap: () {},
          ),
          _RailBtn(
            id: 'print',
            label: 'Drucken',
            icon: Icons.print_outlined,
            active: false,
            onTap: () {},
          ),
          _RailBtn(
            id: 'comp',
            label: 'Gratis',
            icon: Icons.card_giftcard_outlined,
            active: false,
            onTap: () {},
          ),
          _RailBtn(
            id: 'lock',
            label: 'Sperren',
            icon: Icons.lock_outline,
            active: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _RailLogo extends StatelessWidget {
  const _RailLogo();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: V2.accent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1AFFFFFF),
                offset: Offset(0, 0),
                blurRadius: 0,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'G',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: context.v2.chrome,
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBtn extends StatelessWidget {
  const _RailBtn({
    required this.id,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active
        ? context.v2.chromeInk
        : danger
            ? const Color(0xFFE07070)
            : const Color(0xFFBCA087);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 1, 10, 1),
      child: Material(
        color: active ? const Color(0x0FFFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: const Color(0x10FFFFFF),
          highlightColor: const Color(0x08FFFFFF),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 9),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(height: 5),
                    Text(
                      label.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Positioned(
                  left: -10,
                  top: 11,
                  bottom: 11,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: V2.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// TOPBAR  — parts.jsx `Topbar`
// ===========================================================================

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final user = ref.watch(currentUserProvider);
    final v2 = context.v2;
    return Container(
      decoration: BoxDecoration(
        color: v2.chrome,
        border: Border(bottom: BorderSide(color: v2.chrome2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          const _BrandLockup(),
          const SizedBox(width: 18),
          _TicketMeta(ticket: ticket, user: user?.name),
          const SizedBox(width: 18),
          _ModeSwitch(ticket: ticket),
          const Spacer(),
          _TopIcon(
            icon: Icons.tune,
            onTap: () => showDialog<void>(
              context: context,
              barrierColor: Colors.transparent,
              builder: (_) => const _TweaksOverlay(),
            ),
          ),
          const SizedBox(width: 4),
          const _TopSearchField(),
          const SizedBox(width: 8),
          const _TopIcon(icon: Icons.refresh),
          const SizedBox(width: 4),
          _TopIcon(
            icon: Icons.settings_outlined,
            onTap: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(width: 12),
          if (kDebugMode) const _DiagnosticBadge(),
          const SizedBox(width: 8),
          _UserPill(label: user?.name ?? 'Admin'),
        ],
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(right: 18),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0x1FFFFFFF)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          RichText(
            text: const TextSpan(
              style: V2Text.brandName,
              children: [
                TextSpan(text: 'Gastro'),
                TextSpan(text: 'Core', style: V2Text.brandAccent),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Text('POS · v2', style: V2Text.brandTag),
        ],
      ),
    );
  }
}

class _TicketMeta extends StatelessWidget {
  const _TicketMeta({required this.ticket, this.user});
  final TicketEntity? ticket;
  final String? user;

  @override
  Widget build(BuildContext context) {
    final tid = ticket?.orderNumber ?? '—';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('TICKET $tid', style: V2Text.ticketId),
        const SizedBox(width: 10),
        Text('Terminal 01 · ${user ?? 'Admin'}', style: V2Text.ticketSub),
      ],
    );
  }
}

class _ModeSwitch extends ConsumerWidget {
  const _ModeSwitch({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ticket?.orderType ?? OrderType.dineIn;
    return Container(
      decoration: BoxDecoration(
        color: context.v2.chrome2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeBtn(context, ref, OrderType.dineIn, 'Im Haus', active),
          _modeBtn(context, ref, OrderType.takeaway, 'Takeaway', active),
          _modeBtn(context, ref, OrderType.delivery, 'Theke', active),
        ],
      ),
    );
  }

  Widget _modeBtn(
    BuildContext context,
    WidgetRef ref,
    OrderType type,
    String label,
    OrderType active,
  ) {
    final on = type == active;
    return Material(
      color: on ? const Color(0x29FFFFFF) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () {
          if (ticket != null) {
            ref.read(currentTicketProvider.notifier).updateOrderType(type);
          }
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(label, style: on ? V2Text.modeOn : V2Text.modeOff),
        ),
      ),
    );
  }
}

class _TopSearchField extends StatelessWidget {
  const _TopSearchField();
  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Container(
      width: 280,
      height: 36,
      decoration: BoxDecoration(
        color: v2.chrome2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: Color(0x73FFFFFF)),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Produkt oder Bon suchen…',
                hintStyle: TextStyle(
                  color: Color(0x66FFFFFF),
                  fontSize: 13,
                  fontFamily: 'Inter',
                ),
              ),
              style: TextStyle(
                color: v2.chromeInk,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
              cursorColor: V2.sel,
              cursorWidth: 1.2,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: v2.chrome2,
              border: Border.all(color: const Color(0x1FFFFFFF)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              '⌘K',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Color(0x8CFFFFFF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: const Color(0xB3FFFFFF)),
        ),
      ),
    );
  }
}

class _UserPill extends StatelessWidget {
  const _UserPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final initials = _initials(label);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: V2.sel,
            ),
            child: Text(
              initials,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12.5,
              color: Color(0xCCFFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return 'A';
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return t.substring(0, t.length.clamp(0, 1)).toUpperCase();
  }
}

/// Small amber diagnostic chip behind `kDebugMode`. Kept so release builds
/// never show it.
class _DiagnosticBadge extends ConsumerWidget {
  const _DiagnosticBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId = ref.watch(tenantIdProvider);
    final tail =
        tenantId.length > 8 ? tenantId.substring(tenantId.length - 8) : tenantId;
    final cats = ref.watch(categoriesProvider).asData?.value.length ?? -1;
    final prods = ref.watch(productsProvider).asData?.value.length ?? -1;
    final tbls = ref.watch(allTablesProvider).asData?.value.length ?? -1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.amber.shade200,
      child: Text(
        'T:$tail C:$cats P:$prods TBL:$tbls',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      ),
    );
  }
}

// ===========================================================================
// ORDER PANEL  — parts.jsx `OrderPanel`
// ===========================================================================

class _OrderPanel extends ConsumerWidget {
  const _OrderPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OrderHead(ticket: ticket),
        Expanded(child: _OrderList(ticket: ticket)),
        _OrderFoot(ticket: ticket),
      ],
    );
  }
}

class _OrderHead extends ConsumerWidget {
  const _OrderHead({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeGangProvider);
    final guests = ticket?.guestCount ?? 1;
    // Derive 3 gang tabs sized like the React implementation (per-gang
    // counts).
    final items = ticket?.items ?? const <OrderItemEntity>[];
    int countFor(int g) => items.where((i) => i.course == g).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.v2.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('BESTELLUNG', style: V2Text.orderH2),
              const Spacer(),
              _GuestStepper(
                value: guests,
                onChanged: (v) => ref
                    .read(currentTicketProvider.notifier)
                    .updateGuestCount(v.clamp(1, 20)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GangTabs(
            active: active,
            onSelect: (g) =>
                ref.read(activeGangProvider.notifier).state = g,
            countFor: countFor,
          ),
        ],
      ),
    );
  }
}

class _GuestStepper extends StatelessWidget {
  const _GuestStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Gäste',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12.5,
            color: v2.ink2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: v2.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: v2.line),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepBtn(context, Icons.remove, () => onChanged(value - 1)),
              SizedBox(
                width: 22,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    color: v2.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _stepBtn(context, Icons.add, () => onChanged(value + 1)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(icon, size: 13, color: context.v2.ink2),
        ),
      ),
    );
  }
}

class _GangTabs extends StatelessWidget {
  const _GangTabs({
    required this.active,
    required this.onSelect,
    required this.countFor,
  });
  final int active;
  final ValueChanged<int> onSelect;
  final int Function(int) countFor;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Container(
      decoration: BoxDecoration(
        color: v2.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: v2.line),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: _GangTab(
              label: 'Gang 1',
              count: countFor(1),
              on: active == 1,
              onTap: () => onSelect(1),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _GangTab(
              label: 'Gang 2',
              count: countFor(2),
              on: active == 2,
              onTap: () => onSelect(2),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _GangTab(
              label: 'Gang 3',
              count: countFor(3),
              on: active == 3,
              onTap: () => onSelect(3),
            ),
          ),
          const SizedBox(width: 2),
          const _GangAddTab(),
        ],
      ),
    );
  }
}

class _GangTab extends StatelessWidget {
  const _GangTab({
    required this.label,
    required this.count,
    required this.on,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? context.v2.chrome : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: on
                    ? V2Text.gangOn
                    : V2Text.gangLabel.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: V2Text.gangCount.copyWith(
                  color: on
                      ? const Color(0xB3FFFFFF)
                      : V2Text.gangCount.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GangAddTab extends StatelessWidget {
  const _GangAddTab();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.add, size: 16, color: context.v2.ink3),
        ),
      ),
    );
  }
}

class _OrderList extends ConsumerWidget {
  const _OrderList({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ticket == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: Text(
          'Leer — Artikel aus dem Menü hinzufügen',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12.5,
            color: context.v2.ink4,
          ),
        ),
      );
    }

    final byGang = <int, List<OrderItemEntity>>{};
    for (final it in ticket!.items) {
      final g = it.course.clamp(1, 3);
      byGang.putIfAbsent(g, () => []).add(it);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
      children: [
        for (final g in [1, 2, 3])
          _GangSection(
            gang: g,
            items: byGang[g] ?? const [],
          ),
      ],
    );
  }
}

class _GangSection extends ConsumerWidget {
  const _GangSection({required this.gang, required this.items});
  final int gang;
  final List<OrderItemEntity> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final held = ref.watch(heldGangsProvider).contains(gang);
    final hasItems = items.isNotEmpty;
    final allSent = hasItems && items.every((i) => i.sentToKitchen);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'GANG $gang · ${items.length} POS.',
                    style: V2Text.gangHead,
                  ),
                ),
                if (allSent)
                  const _ChipSent()
                else ...[
                  _Chip(
                    label: held ? 'HALTEN ✓' : 'HALTEN',
                    onTap: () {
                      final cur = ref.read(heldGangsProvider);
                      final next = {...cur};
                      if (held) {
                        next.remove(gang);
                      } else {
                        next.add(gang);
                      }
                      ref.read(heldGangsProvider.notifier).state = next;
                    },
                  ),
                  const SizedBox(width: 4),
                  _ChipSend(
                    onTap: hasItems
                        ? () async {
                            try {
                              await ref
                                  .read(currentTicketProvider.notifier)
                                  .fireGang(gang);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Gang $gang an Küche gesendet'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            } catch (_) {}
                          }
                        : null,
                  ),
                ],
              ],
            ),
          ),
          if (!hasItems)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Text(
                'Leer — Artikel aus dem Menü hinzufügen',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  color: context.v2.ink4,
                ),
              ),
            )
          else
            ...items.map((i) => _LineItem(item: i)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Material(
      color: v2.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: v2.line),
          ),
          child: Text(label, style: V2Text.chip),
        ),
      ),
    );
  }
}

class _ChipSend extends StatelessWidget {
  const _ChipSend({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2.accent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text('SENDEN', style: V2Text.chipSend),
        ),
      ),
    );
  }
}

class _ChipSent extends StatelessWidget {
  const _ChipSent();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: V2.okWeak,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('GESENDET', style: V2Text.chipSent),
    );
  }
}

class _LineItem extends ConsumerWidget {
  const _LineItem({required this.item});
  final OrderItemEntity item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(v2SelectedLineIdProvider);
    final selected = selectedId == item.id;
    final sent = item.sentToKitchen;
    final v2 = context.v2;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final cur = ref.read(v2SelectedLineIdProvider);
        ref.read(v2SelectedLineIdProvider.notifier).state =
            cur == item.id ? null : item.id;
      },
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 1),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: selected ? V2.accentWeak : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? V2.accent : Colors.transparent,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${item.quantity.toStringAsFixed(0)}×',
                    textAlign: TextAlign.center,
                    style: V2Text.lineQty.copyWith(
                      color: selected
                          ? V2.accentInk
                          : (sent ? v2.ink2 : v2.ink3),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: V2Text.lineTitle.copyWith(
                          color: sent ? v2.ink2 : v2.ink,
                        ),
                      ),
                      if (item.notes != null && item.notes!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(item.notes!, style: V2Text.lineNote),
                        ),
                      if (item.modifiers.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.modifiers
                                .map((m) => m.modifierName)
                                .join(', '),
                            style: V2Text.lineNote,
                          ),
                        ),
                      if (selected) const SizedBox(height: 6),
                      if (selected) _LineActions(item: item),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'CHF ${v2Chf(item.subtotal)}',
                  style: V2Text.linePrice.copyWith(
                    color: sent ? v2.ink2 : v2.ink2,
                  ),
                ),
              ],
            ),
          ),
          if (sent)
            Positioned(
              left: 4,
              top: 14,
              bottom: 14,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: V2.ok.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LineActions extends ConsumerWidget {
  const _LineActions({required this.item});
  final OrderItemEntity item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _act(context, '−', () {
          final next = (item.quantity - 1).clamp(0, 999).toDouble();
          if (next == 0) {
            ref.read(currentTicketProvider.notifier).removeItem(item.id);
            ref.read(v2SelectedLineIdProvider.notifier).state = null;
          } else {
            ref
                .read(currentTicketProvider.notifier)
                .updateItemQuantity(item.id, next);
          }
        }),
        const SizedBox(width: 4),
        _act(context, '+', () {
          ref
              .read(currentTicketProvider.notifier)
              .updateItemQuantity(item.id, item.quantity + 1);
        }),
        const SizedBox(width: 4),
        _act(context, 'LÖSCHEN', () {
          ref.read(currentTicketProvider.notifier).removeItem(item.id);
          ref.read(v2SelectedLineIdProvider.notifier).state = null;
        }),
      ],
    );
  }

  Widget _act(BuildContext context, String label, VoidCallback onTap) {
    final v2 = context.v2;
    return Material(
      color: v2.surface,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: v2.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              color: v2.ink3,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderFoot extends StatelessWidget {
  const _OrderFoot({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context) {
    final subtotal = ticket?.subtotal ?? 0;
    // MWST 8.1% inclusive: net = subtotal / 1.081, mwst = subtotal - net.
    final net = (subtotal / 1.081).round();
    final mwst = subtotal - net;
    final v2 = context.v2;
    return Container(
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border(top: BorderSide(color: v2.line)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kvRow('Netto', 'CHF ${v2Chf(net)}'),
          const SizedBox(height: 6),
          _kvRow('MWST (8.1 %, inkl.)', 'CHF ${v2Chf(mwst)}'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: v2.line, style: BorderStyle.solid),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Expanded(
                  child: Text('ZU BEZAHLEN', style: V2Text.kvTotalK),
                ),
                Text('CHF ${v2Chf(subtotal)}', style: V2Text.kvTotalV),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(k, style: V2Text.kv)),
        Text(v, style: V2Text.kv),
      ],
    );
  }
}

// ===========================================================================
// FOOTER  — parts.jsx `Footer`
// ===========================================================================

class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final hasItems = ticket != null && ticket.items.isNotEmpty;
    final hasUnsent =
        hasItems && ticket.items.any((i) => !i.sentToKitchen);
    final v2 = context.v2;
    return Container(
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border(top: BorderSide(color: v2.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _FlatBtn(
            icon: Icons.close,
            label: 'Schliessen',
            danger: true,
            onTap: () => _onClose(context, ref, hasItems: hasItems),
          ),
          const SizedBox(width: 4),
          _FlatBtn(
            icon: Icons.add,
            label: 'Neuer Bon',
            onTap: () => _onNewTicket(context, ref, hasItems: hasItems),
          ),
          const SizedBox(width: 4),
          _FlatBtn(
            icon: Icons.local_fire_department_outlined,
            label: 'Senden',
            enabled: hasUnsent,
            onTap: hasUnsent ? () => _onSend(context, ref) : null,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Future<void> _onClose(
    BuildContext context,
    WidgetRef ref, {
    required bool hasItems,
  }) async {
    if (hasItems) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bon schliessen?'),
          content: const Text(
            'Der aktuelle Bon hat noch nicht bezahlte Artikel. '
            'Bon trotzdem verwerfen?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Zurück'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Schliessen'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _onNewTicket(
    BuildContext context,
    WidgetRef ref, {
    required bool hasItems,
  }) async {
    if (hasItems) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Neuen Bon starten?'),
          content: const Text(
            'Der aktuelle Bon hat noch Artikel. Beim Start eines '
            'neuen Bons gehen nicht gesendete Änderungen verloren.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Neu starten'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final user = ref.read(currentUserProvider);
    await ref.read(currentTicketProvider.notifier).createNewTicket(
          deviceId: 'DEV-POS-01',
          waiterId: user?.id,
        );
  }

  Future<void> _onSend(BuildContext context, WidgetRef ref) async {
    await ref.read(currentTicketProvider.notifier).sendToKitchen();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('An die Küche gesendet'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _FlatBtn extends StatelessWidget {
  const _FlatBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    final fg = !enabled
        ? v2.ink4
        : (danger ? V2.danger : v2.ink);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// MENU AREA  — right pane: cats / quickbar / items grid
// ===========================================================================

class _MenuArea extends StatelessWidget {
  const _MenuArea();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, bc) {
        final catW = bc.maxWidth >= 1400 ? 300.0 : (bc.maxWidth >= 1200 ? 280.0 : 240.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: catW, child: const _CategoryList()),
            const Expanded(child: _ItemsWrap()),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// CATEGORY LIST  — parts.jsx `CategoryList`
// ---------------------------------------------------------------------------

class _CategoryList extends ConsumerWidget {
  const _CategoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    // Counts should reflect the full menu, not just the selected category —
    // so we use the category-independent provider. `productsProvider` is
    // filtered by [selectedCategoryProvider], which would zero-out every
    // other badge the moment the user picks a category.
    final productsAsync = ref.watch(allActiveProductsProvider);
    final selected = ref.watch(selectedCategoryProvider);
    final ticket = ref.watch(currentTicketProvider);
    final total = ticket?.total ?? 0;

    final cats = categoriesAsync.asData?.value ?? const <CategoryEntity>[];
    final allProducts =
        productsAsync.asData?.value ?? const <ProductEntity>[];

    // Count products per category for the `.cat .n` badge.
    final countBy = <String, int>{};
    for (final p in allProducts) {
      countBy[p.categoryId] = (countBy[p.categoryId] ?? 0) + 1;
    }

    final v2 = context.v2;
    return Container(
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border(right: BorderSide(color: v2.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _CatGrid(
              cats: cats,
              selectedId: selected,
              countBy: countBy,
              onTap: (id) =>
                  ref.read(selectedCategoryProvider.notifier).state = id,
            ),
          ),
          const SizedBox(height: 12),
          _CatsFooter(
            total: total,
            onTap: () {
              if (ticket == null) return;
              HapticFeedback.selectionClick();
              context.push(AppRoutes.paymentFor(ticket.id));
            },
          ),
        ],
      ),
    );
  }
}

class _CatGrid extends StatelessWidget {
  const _CatGrid({
    required this.cats,
    required this.selectedId,
    required this.countBy,
    required this.onTap,
  });

  final List<CategoryEntity> cats;
  final String? selectedId;
  final Map<String, int> countBy;
  final ValueChanged<String?> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.3,
      ),
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final c = cats[i];
        final palette = v2CategoryPalette(c.color, i);
        return _CatTile(
          name: c.name,
          count: countBy[c.id] ?? 0,
          bg: palette.bg,
          on: selectedId == c.id,
          onTap: () => onTap(selectedId == c.id ? null : c.id),
        );
      },
    );
  }
}

class _CatTile extends StatelessWidget {
  const _CatTile({
    required this.name,
    required this.count,
    required this.bg,
    required this.on,
    required this.onTap,
  });
  final String name;
  final int count;
  final Color bg;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        splashColor: const Color(0x22FFFFFF),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: on
                    ? Border.all(color: Colors.white, width: 3)
                    : null,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    offset: Offset(0, 1),
                    blurRadius: 0,
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Stack(
                children: [
                  // Top inset highlight.
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: SizedBox(
                      height: 1,
                      child: ColoredBox(color: Color(0x24FFFFFF)),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: V2Text.catName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text('$count', style: V2Text.catN),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (on)
              Positioned(
                top: 8,
                right: 10,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 12,
                    color: bg,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatsFooter extends StatelessWidget {
  const _CatsFooter({required this.total, required this.onTap});
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.v2.line)),
      ),
      child: Material(
        color: V2.pay,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  offset: Offset(0, 2),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.payments_outlined,
                    size: 20, color: V2.payInk),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Zur Kasse · CHF ${v2Chf(total)}',
                    style: V2Text.btnAccent,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ITEMS WRAP  — header + Schnellmenü + grid (wraps parts.jsx ItemsGrid +
// parts.jsx QuickBar since both share `grid-area: items/quick` in the CSS).
// ---------------------------------------------------------------------------

class _ItemsWrap extends ConsumerWidget {
  const _ItemsWrap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(filteredProductsProvider);
    // Schnellmenü is category-independent — it's a top-N shortcut row that
    // should never collapse when the user switches to an empty category.
    final allProductsAsync = ref.watch(allActiveProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final cats = categoriesAsync.asData?.value ?? const <CategoryEntity>[];
    final colorByCat = <String, String?>{
      for (final c in cats) c.id: c.color,
    };
    final colorIdx = <String, int>{
      for (var i = 0; i < cats.length; i++) cats[i].id: i,
    };

    final allProducts =
        allProductsAsync.asData?.value ?? const <ProductEntity>[];

    return ColoredBox(
      color: context.v2.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allProducts.isNotEmpty)
            SizedBox(
              height: 108,
              child: _SchnellBar(products: allProducts),
            ),
          const ActionButtonStrip(
            position: ActionButtonPosition.ticketScreen,
            label: 'FUNKTION',
          ),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return const _EmptyGrid();
                }
                return _ItemsGrid(
                  products: products,
                  colorByCat: colorByCat,
                  colorIdx: colorIdx,
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: V2.accent),
              ),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Menü konnte nicht geladen werden: $err',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: V2.danger,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _TweaksOverlay extends ConsumerWidget {
  const _TweaksOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(posPaletteProvider);
    final imagesOn = ref.watch(productImagesEnabledProvider);
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 12,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TWEAKS', style: _tweaksHeader),
                const SizedBox(height: 12),
                const Text('PALETTE', style: _tweaksLabel),
                const SizedBox(height: 6),
                _SegmentedPair<PosPalette>(
                  leftLabel: 'Ivory',
                  leftValue: PosPalette.ivory,
                  rightLabel: 'Midnight',
                  rightValue: PosPalette.midnight,
                  value: palette,
                  onChanged: (v) =>
                      ref.read(posPaletteProvider.notifier).state = v,
                ),
                const SizedBox(height: 14),
                const Text('PRODUKTBILDER', style: _tweaksLabel),
                const SizedBox(height: 6),
                _SegmentedPair<bool>(
                  leftLabel: 'Aus',
                  leftValue: false,
                  rightLabel: 'An',
                  rightValue: true,
                  value: imagesOn,
                  onChanged: (v) => ref
                      .read(productImagesEnabledProvider.notifier)
                      .state = v,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Intentionally hard-coded to light-palette ink: the tweaks overlay sits on
// a pinned white Material (see [_TweaksOverlay]), so it stays light in dark
// mode. Kept as module-level `const` to preserve cheap widget construction.
const TextStyle _tweaksHeader = TextStyle(
  fontFamily: 'Inter',
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.2,
  color: V2.ink3,
);
const TextStyle _tweaksLabel = TextStyle(
  fontFamily: 'Inter',
  fontSize: 10,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.1,
  color: V2.ink4,
);

class _SegmentedPair<T> extends StatelessWidget {
  const _SegmentedPair({
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
    required this.value,
    required this.onChanged,
  });
  final String leftLabel;
  final T leftValue;
  final String rightLabel;
  final T rightValue;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(leftLabel, value == leftValue, () => onChanged(leftValue)),
          _seg(rightLabel, value == rightValue, () => onChanged(rightValue)),
        ],
      ),
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? V2.sel : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              // V2.ink (not context.v2.ink) — parent overlay is pinned white.
              color: selected ? Colors.white : V2.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SCHNELLMENÜ — horizontal tile bar above the items grid. Pulls the first
// 8 products in the selected category (or across the menu if "Alle").
// Matches `.schnell-grid` + `.schnell-tile` exactly.
// ---------------------------------------------------------------------------

class _SchnellBar extends ConsumerWidget {
  const _SchnellBar({required this.products});

  final List<ProductEntity> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pick up to 8 "quick" products: first stable slice by displayOrder.
    final picks = [...products]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final top = picks.take(6).toList();

    if (top.isEmpty) return const SizedBox.shrink();

    final v2 = context.v2;
    return Container(
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border(bottom: BorderSide(color: v2.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _SchnellTile(
                product: top[i],
                onTap: () => _onTap(context, ref, top[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    ProductEntity product,
  ) async {
    final notifier = ref.read(currentTicketProvider.notifier);
    var ticket = ref.read(currentTicketProvider);
    final gang = ref.read(activeGangProvider);
    if (ticket == null) {
      final user = ref.read(currentUserProvider);
      await notifier.createNewTicket(
        deviceId: 'DEV-POS-01',
        waiterId: user?.id,
      );
      ticket = ref.read(currentTicketProvider);
    }
    if (ticket == null) return;
    notifier.addItem(product, course: gang);
  }
}

class _SchnellTile extends StatelessWidget {
  const _SchnellTile({required this.product, required this.onTap});
  final ProductEntity product;
  final VoidCallback onTap;

  static const Color _bg = Color(0xFFEEF4FB);
  static const Color _border = Color(0xFFDCE6F2);

  @override
  Widget build(BuildContext context) {
    // a11y: Schnellverkauf tiles live in a grid of many small cards. We
    // flatten each card into a single button node with a readable label
    // so screen readers announce "Espresso, CHF 4.50" instead of walking
    // through the name, currency, and price as three separate leaves.
    return Semantics(
      button: true,
      label: 'Schnellverkauf ${product.name}, CHF ${v2Chf(product.price)}',
      child: Material(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ExcludeSemantics(
                  child: Text(
                    product.name,
                    style: V2Text.schnellName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text('CHF', style: V2Text.schnellCur),
                      const SizedBox(width: 3),
                      Text(v2Chf(product.price), style: V2Text.schnellPrice),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ITEMS GRID — parts.jsx `ItemsGrid`. Auto-fill 180–200dp tiles.
// ---------------------------------------------------------------------------

class _ItemsGrid extends ConsumerWidget {
  const _ItemsGrid({
    required this.products,
    required this.colorByCat,
    required this.colorIdx,
  });

  final List<ProductEntity> products;
  final Map<String, String?> colorByCat;
  final Map<String, int> colorIdx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final cartQtys = <String, int>{};
    if (ticket != null) {
      for (final li in ticket.items) {
        if (li.sentToKitchen) continue;
        cartQtys[li.productId] =
            (cartQtys[li.productId] ?? 0) + li.quantity.round();
      }
    }

    return LayoutBuilder(
      builder: (context, bc) {
        final w = bc.maxWidth;
        final targetMin = w >= 1500 ? 200.0 : 180.0;
        const gap = 10.0;
        final cols = ((w - 44 + gap) / (targetMin + gap)).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: 130,
          ),
          itemCount: products.length,
          itemBuilder: (context, i) {
            final p = products[i];
            final qty = cartQtys[p.id] ?? 0;
            final palette = v2CategoryPalette(
              colorByCat[p.categoryId],
              colorIdx[p.categoryId] ?? 0,
            );
            return _PCard(
              product: p,
              qty: qty,
              palette: palette,
              onTap: () => _onAdd(context, ref, p),
            );
          },
        );
      },
    );
  }

  Future<void> _onAdd(
    BuildContext context,
    WidgetRef ref,
    ProductEntity product,
  ) async {
    final notifier = ref.read(currentTicketProvider.notifier);
    var ticket = ref.read(currentTicketProvider);
    final gang = ref.read(activeGangProvider);
    if (ticket == null) {
      final user = ref.read(currentUserProvider);
      await notifier.createNewTicket(
        deviceId: 'DEV-POS-01',
        waiterId: user?.id,
      );
      ticket = ref.read(currentTicketProvider);
    }
    if (ticket == null) return;
    notifier.addItem(product, course: gang);
  }
}

class _PCard extends ConsumerWidget {
  const _PCard({
    required this.product,
    required this.qty,
    required this.palette,
    required this.onTap,
  });

  final ProductEntity product;
  final int qty;
  final ({Color bg, Color bgWk}) palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = qty > 0;
    final imagesOn = ref.watch(productImagesEnabledProvider);
    final hasImage = imagesOn &&
        product.imagePath != null &&
        product.imagePath!.isNotEmpty;
    final subtitle = product.description ?? '';

    // a11y: flatten the product card to a single button node. Screen
    // readers announce "Espresso, CHF 4.50, 2 im Warenkorb" rather than
    // walking through the name, description, currency, price, and badge
    // as five separate leaves. excludeSemantics: true on the Semantics
    // wrapper suppresses every descendant's natural semantic tree.
    final cartHint = inCart ? ', $qty im Warenkorb' : '';
    final subtitleHint = subtitle.isNotEmpty ? ', $subtitle' : '';
    return Semantics(
      button: true,
      label:
          '${product.name}$subtitleHint, CHF ${v2Chf(product.price)}$cartHint',
      excludeSemantics: true,
      child: Material(
        color: palette.bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          splashColor: const Color(0x22FFFFFF),
          child: Stack(
          children: [
            if (hasImage)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    product.imagePath!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (hasImage)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.bg.withValues(alpha: 0.35),
                        palette.bg.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: inCart ? Border.all(color: V2.sel, width: 3) : null,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        style: V2Text.pName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: V2Text.pSub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text('CHF', style: V2Text.pCurrency),
                      const SizedBox(width: 3),
                      Text(v2Chf(product.price), style: V2Text.pPrice),
                    ],
                  ),
                ],
              ),
            ),
            if (inCart)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4D000000),
                        offset: Offset(0, 1),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  child: Text(
                    '$qty',
                    style: V2Text.inCart.copyWith(color: palette.bg),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _EmptyGrid extends StatelessWidget {
  const _EmptyGrid();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          'Keine Produkte in dieser Kategorie',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: context.v2.ink3,
          ),
        ),
      ),
    );
  }
}
