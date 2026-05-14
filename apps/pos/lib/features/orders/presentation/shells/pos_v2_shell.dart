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

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/utils/swiss_rounding.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/action_buttons/domain/entities/action_button_entity.dart';
import 'package:gastrocore_pos/features/action_buttons/presentation/action_button_dispatcher.dart';
import 'package:gastrocore_pos/features/action_buttons/presentation/providers/action_button_provider.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';
import 'package:gastrocore_pos/features/customers/presentation/providers/customer_provider.dart';
import 'package:gastrocore_pos/features/fast_sale/presentation/providers/restaurant_config_provider.dart';
import 'package:gastrocore_pos/features/fast_sale/presentation/widgets/delivery_customer_form.dart';
import 'package:gastrocore_pos/features/fast_sale/presentation/widgets/order_type_selector.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/category_entity.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/theme/pos_v2_theme.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/modifier_dialog.dart';
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/favorites_bar.dart'
    show allActiveProductsProvider;
import 'package:gastrocore_pos/features/orders/presentation/widgets/shell/order_panel.dart'
    show activeGangProvider, heldGangsProvider;
import 'package:gastrocore_pos/features/fast_sale/presentation/widgets/cash_payment_dialog.dart';
import 'package:gastrocore_pos/features/fast_sale/presentation/widgets/payment_success_dialog.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/payment_entity.dart';
import 'package:gastrocore_pos/features/payments/presentation/providers/refund_provider.dart';
import 'package:gastrocore_pos/features/payments/presentation/widgets/cash_collector_dialog.dart';
import 'package:gastrocore_pos/features/payments/presentation/widgets/mypos_payment_dialog.dart';
import 'package:gastrocore_pos/features/sync/presentation/providers/sync_provider.dart';
import 'package:gastrocore_pos/features/printing/data/receipt_print_facade.dart';
import 'package:gastrocore_pos/features/printing/domain/ch_receipt_renderer.dart' show ReceiptItem;
import 'package:gastrocore_pos/features/printing/printing_providers.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Local providers — selection state that the panel needs but no global store
// tracks yet. Scoped to this shell.
// ---------------------------------------------------------------------------

/// Currently-highlighted line item (`line-item.selected` in the CSS).
final v2SelectedLineIdProvider = StateProvider<String?>((ref) => null);

/// Active rail destination — matches the `.rail-btn.active` state. Pilot
/// default is `sale` (Verkauf).
final v2RailActiveProvider = StateProvider<String>((ref) => 'sale');

/// Tweaks — palette selector. Only Ivory styled for pilot; Midnight reserved.
enum PosPalette { ivory, midnight }

/// Round-5: persist the Tweaks overlay choices through `AppSettings`
/// (already disk-backed) so the cashier doesn't have to re-tap them
/// after every restart. The two providers below are pure derivations —
/// writes go through `AppSettingsNotifier.setTheme` /
/// `setShowProductImages` and the toggles in the Tweaks overlay rebuild
/// from the new persisted state.

/// Tweaks — show product image thumbnails on grid cards.
final productImagesEnabledProvider = Provider<bool>((ref) {
  return ref
          .watch(appSettingsProvider)
          .valueOrNull
          ?.posShowProductImages ??
      false;
});

/// Active palette derived from the persisted [AppThemeMode].
/// `light` ↔ Ivory, `dark` ↔ Midnight, `system` falls back to Ivory.
final posPaletteProvider = Provider<PosPalette>((ref) {
  final mode =
      ref.watch(appSettingsProvider).valueOrNull?.themeMode ??
          AppThemeMode.light;
  return mode == AppThemeMode.dark
      ? PosPalette.midnight
      : PosPalette.ivory;
});

/// Currently-active seat for new line items. `null` means "Tümü / All" —
/// items go onto the ticket without a seat assignment, matching the pre
/// multi-guest behaviour. When the operator picks a `Person N` tab the
/// shell adds new items with `seatNumber == N`, and the order panel
/// filters to that seat.
///
/// Cleared back to `null` automatically when the seat tab strip rebuilds
/// for a smaller `guestCount` — see `_SeatTabs` below.
final activeSeatProvider = StateProvider<int?>((ref) => null);

// ---------------------------------------------------------------------------
// Fast Sale flag — propagated down the widget tree via InheritedWidget.
// ---------------------------------------------------------------------------

/// Inherited carrier for the [PosV2Shell.fastSaleMode] flag. Lets nested
/// widgets (rail, topbar, order panel, footer) check `mode` without
/// drilling the bool through every constructor.
class FastSaleModeScope extends InheritedWidget {
  const FastSaleModeScope({
    super.key,
    required this.mode,
    required super.child,
  });

  /// `true` when the shell renders the simplified single-screen flow:
  /// no Tisch picker, no seat tabs, no Gang routing badges, no split bill.
  /// Order-type segmented stays prominent and a Lieferung-customer form
  /// appears under the order panel.
  final bool mode;

  static bool of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<FastSaleModeScope>();
    return scope?.mode ?? false;
  }

  @override
  bool updateShouldNotify(FastSaleModeScope oldWidget) =>
      oldWidget.mode != mode;
}

// ---------------------------------------------------------------------------
// Root shell
// ---------------------------------------------------------------------------

class PosV2Shell extends ConsumerStatefulWidget {
  const PosV2Shell({
    super.key,
    this.fastSaleMode = false,
  });

  /// When `true` the shell hides table-service affordances (Tisch / seat /
  /// gang / split) and surfaces the order-type segmented + delivery
  /// customer form. The full Bestellung panel layout is preserved so the
  /// 5-preset autoFit category grid + colored buttons keep working.
  final bool fastSaleMode;

  @override
  ConsumerState<PosV2Shell> createState() => _PosV2ShellState();
}

class _PosV2ShellState extends ConsumerState<PosV2Shell> {
  @override
  void initState() {
    super.initState();
    _applyImmersive();
  }

  /// Round-11: status bar still leaked through on round-10 because
  /// `immersiveSticky` swipes back to visible after a finger-near-edge
  /// gesture and the shell never re-applied it. Two fixes combined:
  ///   1. Use `immersive` (not Sticky) — the "stays hidden once dismissed"
  ///      contract is too lax for a kiosk till.
  ///   2. Re-apply on every build via post-frame callback so any nav
  ///      that briefly surfaced the chrome (snackbar, dialog dismiss)
  ///      bounces it back to hidden.
  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersive,
      overlays: const [],
    );
  }

  @override
  void dispose() {
    // Round-11: do NOT restore edgeToEdge here. App-wide fullscreen is
    // installed in `main()` and re-asserted on every Android focus
    // event by `MainActivity.onWindowFocusChanged`. Restoring would
    // make Bons / Reports / Settings briefly show the system bars
    // again — operator explicitly does not want that.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-apply on every rebuild — kiosk till keeps the chrome hidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyImmersive();
    });
    return FastSaleModeScope(
      mode: widget.fastSaleMode,
      child: ColoredBox(
        color: context.v2.bg,
        // Round-11: drop top/bottom SafeArea insets — the operator
        // explicitly asked for the entire screen to be POS chrome,
        // status-bar / nav-bar real estate included. Lateral insets
        // stay on for tablets with rounded corners / cutouts.
        child: const SafeArea(
          top: false,
          bottom: false,
          child: _V2Layout(),
        ),
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
        final menuSlot = Expanded(child: _MenuArea(leftHanded: leftHanded));

        final innerRowChildren = leftHanded
            ? <Widget>[menuSlot, orderSlot]
            : <Widget>[orderSlot, menuSlot];

        // Round-11 operator follow-up: topbar GONE in BOTH modes (round-10
        // only hid it in fast-sale). Operator: "table service'de de
        // istemiyorum". The rail head (avatar + Settings + Tweaks) now
        // covers user identity + global controls, the BESTELLUNG header
        // chip covers ticket id, and Tische / Schnellverkauf swap lives
        // on the rail divider. Tablet gains the full 60dp band in every
        // mode and the immersive system bar makes that band actually
        // count vertically.
        final mainColumn = Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: innerRowChildren,
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
class _OrderColumn extends ConsumerWidget {
  const _OrderColumn({this.leftHanded = false});

  /// When true, the hairline divider sits on the order column's left edge
  /// (facing the menu area on its right); the default places it on the
  /// right edge (right-hand mode).
  final bool leftHanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v2 = context.v2;
    final side = BorderSide(color: v2.line);
    final fastSale = FastSaleModeScope.of(context);
    final ticket = ref.watch(currentTicketProvider);
    final isDelivery =
        fastSale && ticket?.orderType == OrderType.delivery;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: v2.surface,
        border: leftHanded ? Border(left: side) : Border(right: side),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: _OrderPanel()),
          // Lieferung opens a collapsible customer form between the
          // order panel and the footer. Hidden in table-service.
          if (isDelivery)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: DeliveryCustomerForm(),
            ),
          // Round-5 operator feedback: "numpad kaldir + payment methods'u
          // oraya koy". The InlineNumpad used to sit sticky at the bottom
          // of the cart panel; cash dialog has its own numpad and the
          // cashier never asked for inline qty edits during the pilot.
          // Reclaim ~140dp so BAR/KARTE chips have natural breathing room.
          // Footer carries Schliessen / Neuer Bon / Senden which only make
          // sense in table-service. Reclaim the 72dp in fast-sale so the
          // cart can show two extra line items without scrolling.
          if (!fastSale) const SizedBox(height: 72, child: _Footer()),
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
    final ticket = ref.watch(currentTicketProvider);
    final hasItems = ticket != null && ticket.items.isNotEmpty;
    final fastSale = FastSaleModeScope.of(context);
    final user = ref.watch(currentUserProvider);
    final funktionButtons = ref.watch(visibleActionButtonsByPositionProvider(
        ActionButtonPosition.ticketScreen));
    // Round-9 operator request: "kafama gore aktif pasif yapabileyim".
    // Each rail entry now consults the operator's hide-list (negative
    // encoding so future additions default to visible). The fnGroup
    // toggle hides the whole dynamic FUNKTION block in one tap rather
    // than forcing per-button settings dance.
    final disabled =
        ref.watch(appSettingsProvider).valueOrNull?.disabledRailIds ??
            const <String>{};
    bool isOn(String id) => !disabled.contains(id);

    return Container(
      color: context.v2.chrome,
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Round-11: avatar + Settings + Tweaks are the rail head in
            // BOTH modes (round-10 only fast-sale; topbar now also gone
            // in table-service). The 4-element top stack covers what the
            // old topbar exposed.
            _RailUserAvatar(name: user?.name ?? 'Admin'),
            const SizedBox(height: 6),
            _RailIconBtn(
              icon: Icons.tune,
              label: 'Tweaks',
              onTap: () => showDialog<void>(
                context: context,
                barrierColor: Colors.transparent,
                builder: (_) => const _TweaksOverlay(),
              ),
            ),
            _RailIconBtn(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => context.push(AppRoutes.settings),
            ),
            const SizedBox(height: 8),
            const _RailDivider(),
            const SizedBox(height: 6),
            // Tische rail entry — only relevant for table-service mode.
            // Fast-sale runs counter / takeaway / delivery and never needs
            // a floor plan, so hide it there.
            if (!fastSale && isOn('tables'))
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
            // Round-12 operator request: "schnell verkaufa nasil
            // gecegim, solda bir yere hizli verkaufa gecme ayari
            // ekle". Topbar is gone — without this rail entry the
            // table-service operator cannot reach fast-sale anymore.
            // Symmetric to the `Tische` entry above (only renders in
            // the OPPOSITE shell so the rail never duplicates the
            // shell the operator is already in).
            if (!fastSale && isOn('fastSaleSwitch'))
              _RailBtn(
                id: 'fastSaleSwitch',
                label: 'Schnell',
                icon: Icons.flash_on_rounded,
                active: false,
                onTap: () => context.go(AppRoutes.fastSale),
              ),
            if (isOn('bill'))
              _RailBtn(
                id: 'bill',
                label: 'Bons',
                icon: Icons.receipt_long_outlined,
                active: active == 'bill',
                onTap: () {
                  ref.read(v2RailActiveProvider.notifier).state = 'bill';
                  context.push(AppRoutes.orderHistory);
                },
              ),
            // FUNKTION group — dynamic action buttons (operator-defined).
            // Hidden when no ticket-screen actions are configured OR when
            // the operator switches the whole group off in Tweaks → Rail.
            if (isOn('fnGroup') && funktionButtons.isNotEmpty) ...[
              const SizedBox(height: 6),
              const _RailDivider(),
              const SizedBox(height: 4),
              for (final b in funktionButtons)
                _RailBtn(
                  id: 'fn-${b.id}',
                  label: b.label,
                  icon: _railIconForActionButton(b),
                  active: false,
                  onTap: () => ActionButtonDispatcher.dispatch(
                    button: b,
                    context: context,
                    ref: ref,
                  ),
                ),
            ],
            const SizedBox(height: 6),
            const _RailDivider(),
            const SizedBox(height: 4),
            if (isOn('cancel'))
              _RailBtn(
                id: 'cancel',
                label: 'Storno',
                icon: Icons.block_outlined,
                danger: true,
                active: false,
                onTap: () => _onStorno(context, ref, ticket),
              ),
            if (isOn('print'))
              _RailBtn(
                id: 'print',
                label: 'Drucken',
                icon: Icons.print_outlined,
                active: false,
                onTap: hasItems
                    ? () => ref
                        .read(currentTicketProvider.notifier)
                        .sendToKitchen()
                    : null,
              ),
            if (isOn('lock'))
              _RailBtn(
                id: 'lock',
                label: 'Sperren',
                icon: Icons.lock_outline,
                active: false,
                onTap: () => context.go(AppRoutes.login),
              ),
            // Round-11: build marker — bumps every round so the cashier
            // can verify which APK is on the tablet without taking a
            // screenshot. Visible in BOTH modes now (round-10 only in
            // fast-sale; topbar's gone in table-service too).
            const SizedBox(height: 8),
            const Text(
              'v20',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Color(0x66BCA087),
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Storno entry from the rail. Routes the active ticket through the
  /// refund flow if one is open, otherwise drops the operator into the
  /// order-history list to pick a closed bon to refund.
  void _onStorno(BuildContext context, WidgetRef ref, TicketEntity? ticket) {
    if (ticket != null && ticket.id.isNotEmpty && ticket.items.isNotEmpty) {
      context.push(AppRoutes.refundFor(ticket.id));
    } else {
      context.push(AppRoutes.orderHistory);
    }
  }

}

/// Maps an action-button entity onto a Material icon for the vertical rail.
/// Mirrors the icon allow-list used by the (now-retired) horizontal strip.
IconData _railIconForActionButton(ActionButtonEntity b) {
  const map = <String, IconData>{
    'percent': Icons.percent,
    'card_giftcard': Icons.card_giftcard,
    'sticky_note_2': Icons.sticky_note_2,
    'receipt_long': Icons.receipt_long,
    'restaurant_menu': Icons.restaurant_menu,
    'local_offer': Icons.local_offer,
    'money_off': Icons.money_off,
    'delete_sweep': Icons.delete_sweep,
    'star': Icons.star,
    'bolt': Icons.bolt,
  };
  return b.iconName == null
      ? _defaultActionIcon(b.actionType)
      : (map[b.iconName!] ?? _defaultActionIcon(b.actionType));
}

IconData _defaultActionIcon(ActionButtonType t) {
  return switch (t) {
    ActionButtonType.percentDiscount => Icons.percent,
    ActionButtonType.fixedDiscount => Icons.money_off,
    ActionButtonType.markGift => Icons.card_giftcard,
    ActionButtonType.addNote => Icons.sticky_note_2,
    ActionButtonType.setCourse => Icons.restaurant_menu,
    ActionButtonType.printBill => Icons.receipt_long,
    ActionButtonType.voidItem => Icons.delete_sweep,
    ActionButtonType.customScript => Icons.bolt,
  };
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: Color(0x1AFFFFFF)),
      ),
    );
  }
}

/// Round-10 rail head avatar — replaces the topbar `_UserPill` in
/// fast-sale. Two-letter initials (KW for Klaus Wagner) so the cashier
/// can verify which employee is logged in at a glance. Tap → log out
/// (back to PIN screen). Single-letter fallback when the configured
/// employee has no surname.
class _RailUserAvatar extends StatelessWidget {
  const _RailUserAvatar({required this.name});
  final String name;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: Center(
        child: Material(
          color: V2.accent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => context.go(AppRoutes.login),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: Text(
                _initials,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon-only rail entry — used for Settings / Tweaks at the
/// rail head. Smaller than [_RailBtn] (no large vertical padding) so
/// the avatar + 2 utilities + divider fit in ~140dp at the top.
class _RailIconBtn extends StatelessWidget {
  const _RailIconBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Tooltip(
            message: label,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: const Color(0xCCBCA087)),
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final fg = disabled
        ? const Color(0x66BCA087)
        : active
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

// Round-11: topbar fully decommissioned. Kept around for the rare
// future use-case where some other shell might want to mount it; the
// `unused_element` ignore quiets the analyzer without deleting code.
// ignore: unused_element
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final user = ref.watch(currentUserProvider);
    final allowTemp = ref
            .watch(restaurantSettingsProvider)
            .valueOrNull
            ?.allowTemporaryTables ??
        true;
    final fastSale = FastSaleModeScope.of(context);
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
          const SizedBox(width: 14),
          _CustomerChip(ticket: ticket),
          const SizedBox(width: 14),
          // Round-6 operator request: "tisch seciminde zaten icerideyiz".
          // A ticket bound to a table is by definition dine-in — surfacing
          // an Im Haus / Mitnahme / Theke toggle on a table ticket is
          // meaningless and just lets the cashier mis-tap into the wrong
          // MWST rate. Hide the mode switch in two cases:
          //   * fast-sale shell — selector lives inside the BESTELLUNG
          //     header instead (`_CompactOrderTypeSelector`)
          //   * any ticket with a `tableId` — forced dine-in
          if (!fastSale && ticket?.tableId == null)
            _ModeSwitch(ticket: ticket),
          const SizedBox(width: 10),
          if (!fastSale && allowTemp)
            _TempTablePill(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const _TempTableDialog(),
              ),
            ),
          const SizedBox(width: 10),
          // Hybrid-mode escape hatch: a single tap drops the cashier
          // into the Schnellverkauf single-screen flow for a quick
          // walk-in / counter sale, then they can come back to the
          // floor plan. Hidden when featureTisch is off (Fast Sale is
          // already the only mode in that case) and when fastSaleMode
          // is already on (already there).
          if (!fastSale) const _FastSalePill(),
          // Inverse pill: in fast-sale, surface a "Tische" jump-back to
          // the floor plan. featureTisch gate stays so a pure Fast Sale
          // pilot keeps the bar clean.
          if (fastSale) const _TablesReturnPill(),
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

/// Inverse of [_FastSalePill]: surfaced inside fastSaleMode so the
/// cashier can jump back to the floor plan. Only rendered when
/// `featureTisch` is on — a Fast-Sale-only pilot has no Tische screen
/// to return to.
class _TablesReturnPill extends ConsumerWidget {
  const _TablesReturnPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(effectiveRestaurantConfigProvider);
    if (!cfg.featureTisch) return const SizedBox.shrink();
    final v2 = context.v2;
    return Material(
      color: v2.chrome2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => context.go(AppRoutes.orderCenter),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.table_restaurant_outlined,
                  size: 16, color: Color(0xCCFFFFFF)),
              SizedBox(width: 6),
              Text(
                'Tische',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  color: Color(0xCCFFFFFF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact pill button that flips the cashier into the Fast Sale
/// single-screen flow. Only rendered when `featureTisch` is on (i.e.
/// when the operator is already in hybrid mode); a Fast-Sale-only
/// pilot has no use for the toggle since /fast-sale is already the
/// only screen they ever see.
class _FastSalePill extends ConsumerWidget {
  const _FastSalePill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(effectiveRestaurantConfigProvider);
    if (!cfg.featureTisch) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final v2 = context.v2;
    return Material(
      color: v2.chrome2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => context.go(AppRoutes.fastSale),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flash_on,
                  size: 16, color: Color(0xCCFFFFFF)),
              const SizedBox(width: 6),
              Text(
                l10n.fastSaleTitle,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  color: Color(0xCCFFFFFF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact pill button next to the mode switch — opens the M4 numpad
/// dialog. Only rendered when `RestaurantSettings.allowTemporaryTables`
/// is on (default true; flipped off via Settings → Workflow).
class _TempTablePill extends StatelessWidget {
  const _TempTablePill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Material(
      color: v2.chrome2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.add_box_outlined,
                  size: 16, color: Color(0xCCFFFFFF)),
              SizedBox(width: 6),
              Text(
                'Tisch +',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  color: Color(0xCCFFFFFF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Numpad dialog that asks for an integer table number, validates
/// uniqueness, calls `createTemporaryTable`, then starts a fresh ticket
/// linked to the new row. Failures surface inline (duplicate / no
/// floor) so the operator can correct without dismissing the dialog.
class _TempTableDialog extends ConsumerStatefulWidget {
  const _TempTableDialog();

  @override
  ConsumerState<_TempTableDialog> createState() => _TempTableDialogState();
}

class _TempTableDialogState extends ConsumerState<_TempTableDialog> {
  String _input = '';
  String? _error;
  bool _busy = false;

  void _press(String digit) {
    if (_busy) return;
    setState(() {
      // Clamp at 4 digits — covers up to "9999" which is more than
      // any sane temp-table needs and prevents accidental long taps.
      if (_input.length >= 4) return;
      _input = '$_input$digit';
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _error = null;
    });
  }

  Future<void> _confirm() async {
    if (_busy || _input.isEmpty) return;
    final number = int.tryParse(_input);
    if (number == null || number <= 0) {
      setState(() => _error = 'Ungültige Tischnummer');
      return;
    }
    setState(() => _busy = true);
    final tableName = 'Tisch $number';
    final result = await ref
        .read(tableManagementProvider.notifier)
        .createTemporaryTable(name: tableName);

    if (!mounted) return;
    switch (result) {
      case TempTableCreateSuccess(:final table):
        // Audit + start ticket. Keep the audit reason verbose so the
        // entry still reads cleanly after the row is soft-deleted.
        await ref.read(auditServiceProvider).log(
              action: AuditAction.temporaryTableCreated,
              entityType: 'restaurant_table',
              entityId: table.id,
              reason: 'Geçici masa eklendi: $tableName',
            );
        if (!mounted) return;
        // Spin up a fresh ticket bound to the new table — operators
        // expect to land in the order panel ready to ring up.
        final notifier = ref.read(currentTicketProvider.notifier);
        final user = ref.read(currentUserProvider);
        await notifier.createNewTicket(
          deviceId: 'DEV-POS-01',
          waiterId: user?.id,
          tableId: table.id,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
      case TempTableCreateFailure(:final error, :final clashingTable):
        setState(() {
          _busy = false;
          _error = switch (error) {
            TempTableError.duplicate =>
              clashingTable?.isTemporary == true
                  ? '$tableName ist bereits offen'
                  : '$tableName existiert bereits',
            TempTableError.invalidName => 'Ungültige Tischnummer',
            TempTableError.noFloor =>
              'Kein Saal definiert — bitte zuerst einen Saal anlegen',
            TempTableError.dbError =>
              'Tisch konnte nicht angelegt werden',
          };
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Geçici Masa'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tischnummer eingeben — z. B. 150. Der Tisch verschwindet '
              'aus der Liste, sobald die Rechnung bezahlt ist.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD7DEE7)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _input.isEmpty ? '—' : 'Tisch $_input',
                key: const Key('temp-table-display'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const Key('temp-table-error'),
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFC62828)),
              ),
            ],
            const SizedBox(height: 12),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (final d in row)
                      Expanded(
                        child: _NumpadKey(
                          label: d,
                          onTap: () => _press(d),
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _NumpadKey(
                    label: '⌫',
                    onTap: _backspace,
                  ),
                ),
                Expanded(
                  child: _NumpadKey(
                    label: '0',
                    onTap: () => _press('0'),
                  ),
                ),
                Expanded(
                  child: _NumpadKey(
                    label: '00',
                    onTap: () => _press('00'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('temp-table-confirm'),
          onPressed: _busy || _input.isEmpty ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Tisch öffnen'),
        ),
      ],
    );
  }
}

class _NumpadKey extends StatelessWidget {
  const _NumpadKey({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: SizedBox(
        height: 44,
        child: Material(
          color: const Color(0xFFF1F4F8),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
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
          // Round-5 build marker (2026-05-07): operator was repeatedly
          // testing stale APKs and reporting fixes as "not done". Stamp
          // the topbar with a build tag so a glance tells everyone
          // whether they're on the latest build before re-filing bugs.
          const Text('POS · v11', style: V2Text.brandTag),
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

/// Topbar chip that attaches a loyalty customer to the current ticket.
///
/// Empty state (no customer linked): renders a dashed-outline "+ Kunde"
/// affordance. Tapping it opens [_CustomerSearchDialog]; selecting a
/// customer persists the link (`setCustomer`) and fires a
/// [AuditAction.customerLinkedToTicket] audit entry.
///
/// Linked state: renders name + puan balance. Tapping the chip unlinks
/// the customer (also audited) so the operator can re-pick or clear.
///
/// Disabled when no ticket is active — mirrors [_ModeSwitch] behaviour.
class _CustomerChip extends ConsumerWidget {
  const _CustomerChip({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerId = ticket?.customerId;
    if (customerId == null) {
      return _buildEmpty(context, ref);
    }
    final customerAsync = ref.watch(customerByIdProvider(customerId));
    return customerAsync.when(
      loading: () => _buildShell(
        context: context,
        ref: ref,
        onTap: null,
        child: const _LoadingChipContent(),
      ),
      error: (_, __) => _buildEmpty(context, ref),
      data: (customer) {
        if (customer == null) return _buildEmpty(context, ref);
        return _buildLinked(context, ref, customer);
      },
    );
  }

  Widget _buildEmpty(BuildContext context, WidgetRef ref) {
    return _buildShell(
      context: context,
      ref: ref,
      onTap: ticket == null
          ? null
          : () => _openSearchDialog(context, ref, ticket!),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_add_alt_1,
              size: 14, color: Color(0xB3FFFFFF)),
          SizedBox(width: 6),
          Text(
            'Müşteri Ekle',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Color(0xCCFFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinked(
    BuildContext context,
    WidgetRef ref,
    CustomerEntity customer,
  ) {
    return _buildShell(
      context: context,
      ref: ref,
      onTap: () => _openLinkedSheet(context, ref, customer),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              customer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${customer.loyaltyPoints}P',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShell({
    required BuildContext context,
    required WidgetRef ref,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    final v2 = context.v2;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: v2.chrome2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  Future<void> _openLinkedSheet(
    BuildContext context,
    WidgetRef ref,
    CustomerEntity customer,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      // Sheet is pinned white regardless of app theme — so ink colours
      // below stay on the light palette on purpose (matches [_tweaksHeader]).
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  customer.name,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: V2.ink,
                  ),
                ),
                if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    customer.phone!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: V2.ink2,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: V2.selWeak,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${customer.loyaltyPoints} puan',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: V2.selInk,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.person_remove_alt_1),
                  style: FilledButton.styleFrom(
                    backgroundColor: V2.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(sheetCtx).pop('unlink'),
                  label: const Text('Müşteriyi Kaldır'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  child: const Text('Kapat'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted) return;
    if (action == 'unlink') {
      await _unlinkCustomer(context, ref, customer);
    }
  }

  Future<void> _unlinkCustomer(
    BuildContext context,
    WidgetRef ref,
    CustomerEntity customer,
  ) async {
    final ticketValue = ticket;
    if (ticketValue == null) return;

    await ref.read(currentTicketProvider.notifier).setCustomer(null);

    final audit = ref.read(auditServiceProvider);
    unawaited(
      audit.log(
        action: AuditAction.customerLinkedToTicket,
        entityType: 'ticket',
        entityId: ticketValue.id,
        oldValueJson: '{"customerId":"${customer.id}"}',
        newValueJson: '{"customerId":null}',
        reason: 'Unlinked: ${customer.name}',
      ),
    );

    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${customer.name} bu biletten kaldırıldı.')),
      );
    }
  }
}

class _LoadingChipContent extends StatelessWidget {
  const _LoadingChipContent();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(
        strokeWidth: 1.6,
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xCCFFFFFF)),
      ),
    );
  }
}

/// Open the customer-search dialog, link the picked customer to [ticket],
/// and audit the action. No-op when the dialog is dismissed.
Future<void> _openSearchDialog(
  BuildContext context,
  WidgetRef ref,
  TicketEntity ticket,
) async {
  final picked = await showDialog<CustomerEntity>(
    context: context,
    builder: (_) => const _CustomerSearchDialog(),
  );
  if (picked == null) return;

  await ref.read(currentTicketProvider.notifier).setCustomer(picked.id);

  final audit = ref.read(auditServiceProvider);
  unawaited(
    audit.log(
      action: AuditAction.customerLinkedToTicket,
      entityType: 'ticket',
      entityId: ticket.id,
      oldValueJson:
          '{"customerId":${ticket.customerId == null ? 'null' : '"${ticket.customerId}"'}}',
      newValueJson: '{"customerId":"${picked.id}"}',
      reason: picked.name,
    ),
  );

  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('${picked.name} bilete eklendi.')),
    );
  }
}

/// Modal search dialog: type 2+ chars to filter by name / phone / e-mail.
/// Picking a row pops the dialog with the chosen [CustomerEntity].
class _CustomerSearchDialog extends ConsumerStatefulWidget {
  const _CustomerSearchDialog();

  @override
  ConsumerState<_CustomerSearchDialog> createState() =>
      _CustomerSearchDialogState();
}

class _CustomerSearchDialogState
    extends ConsumerState<_CustomerSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _loading = false;
  List<CustomerEntity> _results = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    _runQuery('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _runQuery(value);
    });
  }

  Future<void> _runQuery(String value) async {
    setState(() {
      _query = value;
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(customerRepositoryProvider);
      final tenantId = ref.read(tenantIdProvider);
      final rows = value.trim().isEmpty
          ? await repo.getAllCustomers(tenantId)
          : await repo.searchCustomers(tenantId, value.trim());
      if (!mounted) return;
      setState(() {
        _results = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Müşteri Ara',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: v2.ink,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'İsim, telefon veya e-posta',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: _buildBody(context),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Vazgeç'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Arama başarısız: $_error',
          style: const TextStyle(color: V2.danger),
          textAlign: TextAlign.center,
        ),
      );
    }
    final v2 = context.v2;
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _query.trim().isEmpty
              ? 'Henüz müşteri yok. Müşteriler ekranından kayıt oluşturabilirsiniz.'
              : '"$_query" için eşleşme bulunamadı.',
          style: TextStyle(color: v2.ink3, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: v2.line),
      itemBuilder: (ctx, i) {
        final c = _results[i];
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(
            c.name,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: v2.ink,
            ),
          ),
          subtitle: Text(
            [
              if (c.phone != null && c.phone!.isNotEmpty) c.phone!,
              if (c.email != null && c.email!.isNotEmpty) c.email!,
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: v2.ink3),
          ),
          trailing: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: V2.selWeak,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${c.loyaltyPoints}P',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: V2.selInk,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          onTap: () => Navigator.of(ctx).pop(c),
        );
      },
    );
  }
}

/// Topbar product / ticket search box. Pushes the trimmed query straight
/// into [productSearchProvider] so [filteredProductsProvider] — the source
/// the items grid watches — reapplies its case-insensitive name match on
/// every keystroke. The field keeps its own [TextEditingController] so it
/// also surfaces whatever was cleared from the provider externally (e.g.
/// a pilot reset).
class _TopSearchField extends ConsumerStatefulWidget {
  const _TopSearchField();

  @override
  ConsumerState<_TopSearchField> createState() => _TopSearchFieldState();
}

class _TopSearchFieldState extends ConsumerState<_TopSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: ref.read(productSearchProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(productSearchProvider.notifier).state = value;
  }

  void _clear() {
    _controller.clear();
    ref.read(productSearchProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    // Keep the controller aligned when some other widget writes to the
    // provider (e.g. Escape-to-clear affordance post-pilot).
    final currentQuery = ref.watch(productSearchProvider);
    if (currentQuery != _controller.text) {
      _controller.value = TextEditingValue(
        text: currentQuery,
        selection: TextSelection.collapsed(offset: currentQuery.length),
      );
    }
    final hasQuery = currentQuery.isNotEmpty;
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
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
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
          if (hasQuery)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: _clear,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: Color(0xB3FFFFFF),
                  ),
                ),
              ),
            )
          else
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
    final fastSale = FastSaleModeScope.of(context);
    final active = ref.watch(activeGangProvider);
    final guests = ticket?.guestCount ?? 1;
    final activeSeat = ref.watch(activeSeatProvider);
    // Derive 3 gang tabs sized like the React implementation (per-gang
    // counts).
    final items = ticket?.items ?? const <OrderItemEntity>[];
    int countFor(int g) => items.where((i) => i.course == g).length;
    int seatCountFor(int seat) =>
        items.where((i) => i.seatNumber == seat).length;

    // Hotfix 2026-05-07 (round 3): operator asked to drop the loud
    // "BESTELLUNG" header in fast-sale — the cart panel is already
    // distinguishable, the header just steals a row. Replaced with a
    // tiny ticket-number chip (#orderNumber) that sits inline with the
    // order-type segment. Table-service keeps the original head layout.
    final ticketNumber = ticket?.orderNumber;
    final ticketLabel = (ticketNumber == null || ticketNumber.isEmpty)
        ? '#—'
        : '#$ticketNumber';

    return Container(
      padding: fastSale
          ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
          : const EdgeInsets.fromLTRB(22, 16, 22, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.v2.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fastSale)
            // v3 redesign (2026-05-13): cart-header is now a 4-element
            // strip — [#0023] [🍽️ Mode ▾] [Tisch input] [☰] — modelled
            // after the operator-supplied mock. The 2-segment selector
            // shrinks to a single pill with a popup so a third element
            // (Tisch input) fits in the row. Table-bound tickets drop
            // the mode pill (dine-in implied) but keep the Tisch label.
            Row(
              children: [
                _TicketNoChip(label: ticketLabel),
                if (ticket?.tableId == null) ...[
                  const SizedBox(width: 8),
                  const _HeaderModePill(),
                ],
                const SizedBox(width: 8),
                Expanded(child: _HeaderTischField(ticket: ticket)),
                const SizedBox(width: 8),
                _HeaderHamburger(ticket: ticket),
              ],
            )
          else ...[
            Row(
              children: [
                Text('BESTELLUNG', style: context.v2t.orderH2),
                const Spacer(),
                _GuestStepper(
                  value: guests,
                  onChanged: (v) =>
                      _onGuestCountChanged(context, ref, v, items),
                ),
              ],
            ),
            if (guests >= 2) ...[
              const SizedBox(height: 12),
              _SeatTabs(
                guestCount: guests,
                activeSeat: activeSeat,
                countFor: seatCountFor,
                onSelect: (s) =>
                    ref.read(activeSeatProvider.notifier).state = s,
              ),
            ],
            const SizedBox(height: 12),
            _GangTabs(
              active: active,
              onSelect: (g) =>
                  ref.read(activeGangProvider.notifier).state = g,
              countFor: countFor,
            ),
          ],
        ],
      ),
    );
  }

  /// Clamp + propagate the new guest count, then sweep any orphan seat
  /// assignments. When the operator drops the count from e.g. 4 to 2,
  /// items previously bound to seats 3 / 4 lose their assignment (the
  /// items themselves stay on the ticket — only the seat tag is
  /// cleared) and a snackbar surfaces how many lines were affected so
  /// the cashier can re-assign manually if needed.
  void _onGuestCountChanged(
    BuildContext context,
    WidgetRef ref,
    int raw,
    List<OrderItemEntity> currentItems,
  ) {
    final clamped = raw.clamp(1, 20);
    ref.read(currentTicketProvider.notifier).updateGuestCount(clamped);

    final orphans = currentItems
        .where((i) => i.seatNumber != null && i.seatNumber! > clamped)
        .toList(growable: false);
    if (orphans.isEmpty) {
      // Nothing to clear; if the active seat now exceeds the count,
      // snap it back to "Tümü" so the cashier doesn't add new items
      // onto a seat that just disappeared.
      final activeSeat = ref.read(activeSeatProvider);
      if (activeSeat != null && activeSeat > clamped) {
        ref.read(activeSeatProvider.notifier).state = null;
      }
      return;
    }

    final notifier = ref.read(currentTicketProvider.notifier);
    for (final orphan in orphans) {
      notifier.updateItemSeat(orphan.id, null);
    }

    // Active seat fell off the ladder too — drop back to "Tümü".
    final activeSeat = ref.read(activeSeatProvider);
    if (activeSeat != null && activeSeat > clamped) {
      ref.read(activeSeatProvider.notifier).state = null;
    }

    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.seatReassignedSnack(orphans.length)),
        duration: const Duration(seconds: 3),
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
                    : context.v2t.gangLabel
                        .copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: context.v2t.gangCount.copyWith(
                  color: on
                      ? const Color(0xB3FFFFFF)
                      : context.v2t.gangCount.color,
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

/// Tiny order-number chip rendered in the fast-sale order-panel head
/// next to the order-type segment. Replaces the loud "BESTELLUNG" title
/// (round 3 operator feedback — "ticket no küçük yetrli").
class _TicketNoChip extends StatelessWidget {
  const _TicketNoChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: v2.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: v2.line),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: v2.ink2,
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// _CompactOrderTypeSelector + _CompactSeg removed in v3 — the cart-header
// strip uses a single popup-driven pill (`_HeaderModePill`) instead of a
// 2-segment inline control so a Tisch input + hamburger menu fit in the
// same row. Mode toggle logic is preserved on the new pill widget.

// ---------------------------------------------------------------------------
// _HeaderModePill / _HeaderTischField / _HeaderHamburger
// v3 cart-header strip — replaces the 2-segment dine-in/takeaway selector
// with a single pill (popup-driven) so a Tisch input + hamburger menu fit
// in the same row. Pattern matches operator mockup uploaded 2026-05-13.
// ---------------------------------------------------------------------------

class _HeaderModePill extends ConsumerWidget {
  const _HeaderModePill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ticket = ref.watch(currentTicketProvider);
    final pending = ref.watch(fastSalePendingOrderTypeProvider);
    final selected = ticket?.orderType ?? pending;

    String labelFor(OrderType t) => switch (t) {
          OrderType.dineIn => l10n.fastSaleOrderTypeDineIn,
          OrderType.takeaway => l10n.fastSaleOrderTypeTakeaway,
          _ => t.name,
        };
    IconData iconFor(OrderType t) => switch (t) {
          OrderType.dineIn => Icons.restaurant_rounded,
          OrderType.takeaway => Icons.shopping_bag_rounded,
          _ => Icons.help_outline_rounded,
        };

    void pick(OrderType type) {
      final notifier = ref.read(currentTicketProvider.notifier);
      notifier.updateOrderType(type);
      ref.read(fastSalePendingOrderTypeProvider.notifier).state = type;
    }

    return PopupMenuButton<OrderType>(
      tooltip: labelFor(selected),
      offset: const Offset(0, 36),
      position: PopupMenuPosition.under,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      itemBuilder: (_) => [
        for (final t in const [OrderType.dineIn, OrderType.takeaway])
          PopupMenuItem<OrderType>(
            value: t,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconFor(t), size: 16, color: V2.ink),
                const SizedBox(width: 8),
                Text(labelFor(t)),
                if (t == selected) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.check_rounded, size: 14, color: V2.ok),
                ],
              ],
            ),
          ),
      ],
      onSelected: pick,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(selected), size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              labelFor(selected),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only "Tisch" pill — shows the bound table id when the ticket is
/// parked on one, or a muted placeholder when the cart is in pure fast-
/// sale mode. Wiring the inline submit to a table-pick flow is a follow-
/// up; for now the affordance reads the mockup pattern without breaking
/// the existing tables provider model.
class _HeaderTischField extends StatelessWidget {
  const _HeaderTischField({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    final tableId = ticket?.tableId;
    final hasTable = tableId != null && tableId.isNotEmpty;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: v2.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: v2.line),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(
            hasTable
                ? Icons.table_restaurant_rounded
                : Icons.table_bar_outlined,
            size: 14,
            color: hasTable ? v2.ink : v2.ink4,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hasTable ? 'Tisch $tableId' : 'Tisch',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: hasTable ? v2.ink : v2.ink4,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cart-header hamburger — popup menu listing the operator-mock items
/// (Kunden hinzufügen / Bemerkung / Notiz / Tisch wechseln). Customer
/// pick is wired to the existing search dialog; the other three surface
/// a "Yakında" snackbar so the operator's mental model lands without
/// claiming features that aren't built yet.
class _HeaderHamburger extends ConsumerWidget {
  const _HeaderHamburger({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v2 = context.v2;
    return PopupMenuButton<String>(
      tooltip: 'Mehr',
      offset: const Offset(0, 36),
      position: PopupMenuPosition.under,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: 'customer',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_alt_rounded, size: 16),
              SizedBox(width: 8),
              Text('Kunden hinzufügen'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'remark',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 16),
              SizedBox(width: 8),
              Text('Bemerkung'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'note',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sticky_note_2_outlined, size: 16),
              SizedBox(width: 8),
              Text('Notiz'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'switchTable',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz_rounded, size: 16),
              SizedBox(width: 8),
              Text('Tisch wechseln'),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'clearBon',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.delete_sweep_outlined,
                size: 16,
                color: Color(0xFFDC2626),
              ),
              SizedBox(width: 8),
              Text(
                'Bon stornieren',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
            ],
          ),
        ),
      ],
      onSelected: (action) async {
        switch (action) {
          case 'customer':
            final t = ticket;
            if (t == null) return;
            await _openSearchDialog(context, ref, t);
            break;
          case 'clearBon':
            await _onClearBon(context, ref);
            break;
          case 'remark':
          case 'note':
          case 'switchTable':
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('Bald verfügbar.'),
                duration: Duration(seconds: 2),
              ),
            );
            break;
        }
      },
      child: Container(
        width: 36,
        height: 32,
        decoration: BoxDecoration(
          color: v2.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: v2.line),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.menu_rounded, size: 16, color: v2.ink2),
      ),
    );
  }

  /// Confirm-and-clear handler for the destructive hamburger entry.
  /// Refuses if any line has been sent to the kitchen — those must go
  /// through the void flow so the KDS ticket stays consistent.
  Future<void> _onClearBon(BuildContext context, WidgetRef ref) async {
    final t = ticket;
    if (t == null || t.items.isEmpty) return;
    final hasSent = t.items.any((i) => i.sentToKitchen);
    if (hasSent) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Mutfağa gönderilmiş kalemler var — Storno akışından geçin.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fişi temizle?'),
        content: const Text(
          'Bu fişteki tüm kalemler silinecek. Fiş numarası açık kalır, '
          'yeni satış aynı bonda devam edebilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ref
        .read(currentTicketProvider.notifier)
        .clearAllItems();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Fiş temizlendi.' : 'Mutfağa gönderilmiş kalem var.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Per-guest tab strip surfaced in `_OrderHead` whenever guestCount ≥ 2.
///
/// Tabs: `Tümü` (active seat = null) followed by `Person 1..N`. Tapping
/// a tab pre-selects the seat the next added line item is tagged with;
/// it also filters the order panel to that seat. Tabs auto-shrink to
/// fit a single row up to N=20 (the guestCount upper bound).
class _SeatTabs extends StatelessWidget {
  const _SeatTabs({
    required this.guestCount,
    required this.activeSeat,
    required this.countFor,
    required this.onSelect,
  });

  final int guestCount;
  final int? activeSeat;
  final int Function(int seat) countFor;

  /// `null` selects "Tümü", otherwise the 1-based seat number.
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: v2.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: v2.line),
      ),
      padding: const EdgeInsets.all(3),
      // Horizontal scroll keeps the strip usable for tables of 8+
      // without squashing the labels into illegibility.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _SeatTab(
              key: const Key('seat-tab-all'),
              label: l10n.seatAll,
              count: null,
              on: activeSeat == null,
              onTap: () => onSelect(null),
            ),
            for (var s = 1; s <= guestCount; s++) ...[
              const SizedBox(width: 2),
              _SeatTab(
                key: Key('seat-tab-$s'),
                label: l10n.seatPerson(s),
                count: countFor(s),
                on: activeSeat == s,
                onTap: () => onSelect(s),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeatTab extends StatelessWidget {
  const _SeatTab({
    super.key,
    required this.label,
    required this.count,
    required this.on,
    required this.onTap,
  });

  final String label;

  /// `null` means "don't render a count badge" (used for the "Tümü" tab).
  final int? count;
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
                    : context.v2t.gangLabel
                        .copyWith(fontWeight: FontWeight.w500),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: context.v2t.gangCount.copyWith(
                    color: on
                        ? const Color(0xB3FFFFFF)
                        : context.v2t.gangCount.color,
                  ),
                ),
              ],
            ],
          ),
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

    // Round-3+ hard-delete fix: in fast-sale the order panel must NEVER
    // surface "GANG 1 · N POS." section headers or HALTEN chips. The
    // previous gating only hid the head's Gang TABS, not these section
    // dividers in the list — operator screenshot still showed them.
    // Render a flat line-item list when fastSale is on, full byGang
    // grouping when off (table-service fine-dining keeps courses).
    final fastSale = FastSaleModeScope.of(context);
    if (fastSale) {
      final items = ticket!.items;
      if (items.isEmpty) {
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
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        itemCount: items.length,
        itemBuilder: (context, i) => _LineItem(item: items[i]),
      );
    }

    final activeSeat = ref.watch(activeSeatProvider);
    final byGang = <int, List<OrderItemEntity>>{};
    for (final it in ticket!.items) {
      // Filter by active seat tab. `null` = "Tümü / All" — every item
      // is included, preserving the pre-M3 behaviour. When a seat is
      // active only items tagged with that seat surface in the panel,
      // mirroring SambaPOS / Lightspeed split-billing UX.
      if (activeSeat != null && it.seatNumber != activeSeat) continue;
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
    final showFireChip = ref
            .watch(restaurantSettingsProvider)
            .valueOrNull
            ?.enablePerGangFire ??
        false;
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
                    style: context.v2t.gangHead,
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
                  // M5: per-gang Senden chip is opt-in. Pilot crews get
                  // a single global Senden footer button; fine-dining
                  // flips the toggle to restore independent timing.
                  if (showFireChip) ...[
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
                                    content:
                                        Text('Gang $gang an Küche gesendet'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              } catch (_) {}
                            }
                          : null,
                    ),
                  ],
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
          child: Text(label, style: context.v2t.chip),
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
    // Round-7: dark-mode contrast fix — V2.accentWeak is a near-white
    // tint that disappears on the dark surface AND the line title
    // (`v2.ink`) collapsed to the same near-white in dark mode, so the
    // selected row read as "blank box". Use the colorScheme onSurface
    // for the strong text colour and fall back to a translucent tint
    // for the selection background that respects brightness.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strongInk = isDark ? Colors.white : v2.ink;
    final selectedBg = isDark
        ? const Color(0x33FFD700) // muted gold tint
        : V2.accentWeak;

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
              color: selected ? selectedBg : Colors.transparent,
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
                          ? strongInk
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
                          color: sent ? v2.ink2 : strongInk,
                        ),
                      ),
                      if (item.notes != null && item.notes!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(item.notes!, style: context.v2t.lineNote),
                        ),
                      if (item.modifiers.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.modifiers
                                .map((m) => m.modifierName)
                                .join(', '),
                            style: context.v2t.lineNote,
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
                    color: sent ? v2.ink2 : strongInk,
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
    // v3 redesign: thumb-friendly stepper + icon-only RABATT/LÖSCHEN
    // square buttons. Round-13 fix (2026-05-14): the labelled outline
    // chips were wrapping on narrow line widths ("sıkışık"), so we
    // dropped the text and bumped the glyph to 20dp. Tooltips preserve
    // discoverability for the long-press / a11y path.
    return Row(
      children: [
        _Stepper(
          qty: item.quantity,
          onMinus: () {
            final next = (item.quantity - 1).clamp(0, 999).toDouble();
            if (next == 0) {
              ref.read(currentTicketProvider.notifier).removeItem(item.id);
              ref.read(v2SelectedLineIdProvider.notifier).state = null;
            } else {
              ref
                  .read(currentTicketProvider.notifier)
                  .updateItemQuantity(item.id, next);
            }
          },
          onPlus: () {
            ref
                .read(currentTicketProvider.notifier)
                .updateItemQuantity(item.id, item.quantity + 1);
          },
        ),
        const SizedBox(width: 8),
        _IconAction(
          tooltip: 'Rabatt',
          icon: Icons.percent_rounded,
          tone: _OutlineTone.warning,
          onTap: () {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('Bald verfügbar.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        _IconAction(
          tooltip: 'Löschen',
          icon: Icons.close_rounded,
          tone: _OutlineTone.danger,
          onTap: () {
            ref.read(currentTicketProvider.notifier).removeItem(item.id);
            ref.read(v2SelectedLineIdProvider.notifier).state = null;
          },
        ),
      ],
    );
  }
}

enum _OutlineTone { warning, danger }

/// Square icon-only outline button — replaces the previous `_OutlineAction`
/// labelled variant. Fixed 48×40 footprint so the row never reflows when
/// the line title is long; Tooltip + Semantics carry the label.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.tone,
    required this.onTap,
  });
  final String tooltip;
  final IconData icon;
  final _OutlineTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    final fg = tone == _OutlineTone.danger
        ? const Color(0xFFDC2626)
        : const Color(0xFFB45309);
    final border = tone == _OutlineTone.danger
        ? const Color(0xFFFCA5A5)
        : const Color(0xFFFCD34D);
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: v2.surface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 40,
              width: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
              child: ExcludeSemantics(
                child: Icon(icon, size: 20, color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
  });
  final double qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    final qtyStr = qty == qty.roundToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(2);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: v2.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: v2.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperBtn(icon: Icons.remove_rounded, onTap: onMinus),
          SizedBox(
            width: 32,
            child: Text(
              qtyStr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: v2.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _StepperBtn(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  const _StepperBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 40,
        height: 38,
        child: Icon(icon, size: 18, color: v2.ink2),
      ),
    );
  }
}

class _OrderFoot extends ConsumerWidget {
  const _OrderFoot({required this.ticket});
  final TicketEntity? ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discount = ticket?.discountAmount ?? 0;
    final rawTotal = ticket?.total ?? 0;
    // Round-7: apply Swiss 5-Rappen rounding (Rappenrundung) on the
    // displayed total so cash-paying customers see the actual cash-payable
    // amount. The DB ledger keeps the unrounded `ticket.total` for
    // accounting; the printer uses the same rounded value below.
    final roundedTotal = swissRoundCents(rawTotal);
    final roundingDelta = roundedTotal - rawTotal;

    final v2 = context.v2;
    // v3 redesign 2026-05-13: in fast-sale mode the payment chips now live
    // *here* (cart-column footer) instead of below the categories grid —
    // operators reached past the bill column to find them on the right
    // side, which felt backwards. Table-mode keeps the totals-only layout
    // and relies on the bottom action bar's "Zur Kasse" button instead.
    final fastSale = FastSaleModeScope.of(context);
    final hasItems = ticket != null && ticket!.items.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border(top: BorderSide(color: v2.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCompactTotals(
            context,
            total: roundedTotal,
            discount: discount,
            roundingDelta: roundingDelta,
            showTwintInline: fastSale && hasItems,
            onTwint: fastSale && hasItems
                ? () => _onTwintTapped(context, ref, ticket!)
                : null,
          ),
          if (fastSale) ...[
            const SizedBox(height: 10),
            _CartPayButtons(ticket: ticket, hasItems: hasItems),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactTotals(
    BuildContext context, {
    required int total,
    required int discount,
    required int roundingDelta,
    required bool showTwintInline,
    required VoidCallback? onTwint,
  }) {
    final v2 = context.v2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (discount > 0) ...[
          _kvRow(context, 'Rabatt', '− CHF ${v2Chf(discount)}'),
          const SizedBox(height: 6),
          Container(height: 1, color: v2.line),
          const SizedBox(height: 8),
        ],
        if (roundingDelta != 0) ...[
          _kvRow(
            context,
            'Rundung',
            '${roundingDelta > 0 ? '+' : '−'} CHF ${v2Chf(roundingDelta.abs())}',
          ),
          const SizedBox(height: 6),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ZU BEZAHLEN', style: context.v2t.kvTotalK),
                  const SizedBox(height: 2),
                  Text('CHF ${v2Chf(total)}', style: context.v2t.kvTotalV),
                ],
              ),
            ),
            if (showTwintInline)
              _TwintInlineButton(onTap: onTwint),
          ],
        ),
      ],
    );
  }

  Widget _kvRow(BuildContext context, String k, String v) {
    final style = context.v2t.kv;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(k, style: style)),
        Text(v, style: style),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _CartPayButtons + _TwintInlineButton + _TwintMark
// v3: payment row baked into the cart column. NAKIT (green) + KARTE (blue)
// span the column; TWINT lives inline with the ZU BEZAHLEN total above.
// ZUR KASSE · TEILEN drops the operator into the full settlement screen
// for partial / split / loyalty flows.
// ---------------------------------------------------------------------------

class _CartPayButtons extends ConsumerWidget {
  const _CartPayButtons({required this.ticket, required this.hasItems});
  final TicketEntity? ticket;
  final bool hasItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _BigPayBtn(
                label: 'NAKIT',
                icon: Icons.payments_rounded,
                bg: const Color(0xFF1B8A4A),
                fg: Colors.white,
                onTap: hasItems
                    ? () => _onBarTapped(context, ref, ticket!)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BigPayBtn(
                label: 'KARTE',
                icon: Icons.credit_card_rounded,
                bg: const Color(0xFF1F6FEB),
                fg: Colors.white,
                onTap: hasItems
                    ? () => _onKarteTapped(context, ref, ticket!)
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ZurKasseLink(
          enabled: hasItems,
          onTap: hasItems
              ? () {
                  HapticFeedback.selectionClick();
                  context.push(AppRoutes.paymentFor(ticket!.id));
                }
              : null,
        ),
      ],
    );
  }
}

class _BigPayBtn extends StatelessWidget {
  const _BigPayBtn({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: disabled ? const Color(0xFFD8D2C9) : bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 64,
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
                Icon(icon, size: 22, color: fg),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: fg,
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

class _TwintInlineButton extends StatelessWidget {
  const _TwintInlineButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Semantics(
      button: true,
      label: 'TWINT',
      child: Material(
        color: disabled ? const Color(0xFF333333) : Colors.black,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 56,
            width: 110,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
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
            child: const _TwintMark(),
          ),
        ),
      ),
    );
  }
}

/// Simplified TWINT mark + wordmark, painted inline so we don't pull a
/// PNG asset into the pipeline. Not the licensed brand mark — close
/// enough to be recognisable on the operator's screen without claiming
/// brand assets. The MyPOS dialog still renders the real licensed UI
/// when the operator follows through.
class _TwintMark extends StatelessWidget {
  const _TwintMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CustomPaint(painter: _TwintBadgePainter()),
        ),
        const SizedBox(width: 8),
        const Text(
          'TWINT',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _TwintBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // White hexagon badge.
    final hex = Path();
    final cx = w / 2, cy = h / 2;
    final r = w / 2;
    for (var i = 0; i < 6; i++) {
      final a = (i * 60 - 90) * math.pi / 180;
      final px = cx + r * 0.98 * math.cos(a);
      final py = cy + r * 0.98 * math.sin(a);
      if (i == 0) {
        hex.moveTo(px, py);
      } else {
        hex.lineTo(px, py);
      }
    }
    hex.close();
    canvas.drawPath(hex, Paint()..color = Colors.white);

    // Blue stroke (left wing).
    final blue = Paint()
      ..color = const Color(0xFF1AA7E1)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final leftPath = Path()
      ..moveTo(cx - r * 0.55, cy - r * 0.25)
      ..lineTo(cx - r * 0.12, cy + r * 0.45)
      ..lineTo(cx + r * 0.05, cy + r * 0.05);
    canvas.drawPath(leftPath, blue);

    // Red stroke (right wing).
    final red = Paint()
      ..color = const Color(0xFFEE2D3F)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rightPath = Path()
      ..moveTo(cx + r * 0.05, cy + r * 0.05)
      ..lineTo(cx + r * 0.22, cy + r * 0.45)
      ..lineTo(cx + r * 0.55, cy - r * 0.25);
    canvas.drawPath(rightPath, red);

    // Yellow dot (centre top).
    final dotR = r * 0.22;
    canvas.drawCircle(
      Offset(cx + r * 0.05, cy - r * 0.18),
      dotR,
      Paint()..color = const Color(0xFFF9B21C),
    );
    canvas.drawCircle(
      Offset(cx + r * 0.05, cy - r * 0.18),
      dotR * 0.4,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// FOOTER  — parts.jsx `Footer`
// ===========================================================================

/// Public builder so widget tests can pump the footer in isolation without
/// wiring the entire shell (topbar, rail, menu area, DI, ...).
@visibleForTesting
Widget buildPosV2FooterForTest() => const _Footer();

class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final hasItems = ticket != null && ticket.items.isNotEmpty;
    final hasUnsent =
        hasItems && ticket.items.any((i) => !i.sentToKitchen);
    // A table ticket is a parked order — the waiter wants to send items to
    // the kitchen without closing the bon. Surface a "Sipariş Ver" primary
    // plus a separate "Zur Kasse" so the two intents never collide. In
    // takeaway/counter mode the ticket settles on the same screen, so the
    // original close / new / send triad still applies.
    final isTableTicket = ticket?.tableId != null;
    final fastSale = FastSaleModeScope.of(context);
    // Hotfix 2026-05-07: in fast-sale mode the cart panel already exposes
    // BAR / KARTE / ZUR KASSE quick-pay chips in the categories footer, and
    // there is no kitchen-fire ("Senden") flow because every item is sold
    // immediately. Schliessen / Neuer Bon / Senden become noise that hides
    // a screen-row of cart space. Hide the entire footer in fast-sale —
    // the order column collapses cleanly thanks to its SizedBox parent.
    final v2 = context.v2;
    if (fastSale) {
      // Render an empty container so the parent SizedBox(height: 72)
      // still has a child; visually nothing shows.
      return ColoredBox(color: v2.surface);
    }
    return Container(
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border(top: BorderSide(color: v2.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: isTableTicket
            ? [
                _FlatBtn(
                  icon: Icons.send_rounded,
                  label: 'Sipariş Ver',
                  enabled: hasItems,
                  onTap: hasItems
                      ? () => _onOrderAndReturn(context, ref)
                      : null,
                ),
                const SizedBox(width: 4),
                _FlatBtn(
                  icon: Icons.point_of_sale_outlined,
                  label: 'Zur Kasse',
                  enabled: hasItems,
                  onTap: hasItems
                      ? () => _onOpenCheckout(context, ref)
                      : null,
                ),
                const Spacer(),
              ]
            : [
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
                  onTap: () =>
                      _onNewTicket(context, ref, hasItems: hasItems),
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
    final ticket = ref.read(currentTicketProvider);
    // Table tickets are parked unpaid on purpose — closing the view is not
    // discarding the bon, so the "nicht bezahlt" warning is wrong. Silent-
    // approve and fall through to the navigation.
    final isTableTicket = ticket?.tableId != null;
    if (hasItems && !isTableTicket) {
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
    final ticket = ref.read(currentTicketProvider);
    final isTableTicket = ticket?.tableId != null;
    if (hasItems && !isTableTicket) {
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

  /// Table mode: persist the ticket, fire items to the kitchen, audit the
  /// dispatch, then return to the floor plan. The bon stays open — the
  /// guest is still seated — so no payment screen, no "nicht bezahlt"
  /// dialog, no Schliessen semantics.
  Future<void> _onOrderAndReturn(BuildContext context, WidgetRef ref) async {
    final ticket = ref.read(currentTicketProvider);
    if (ticket == null) return;
    await ref.read(currentTicketProvider.notifier).sendToKitchen();
    final saved = ref.read(currentTicketProvider);
    final audit = ref.read(auditServiceProvider);
    unawaited(
      audit.log(
        action: AuditAction.orderSentToKitchen,
        entityType: 'ticket',
        entityId: saved?.id ?? ticket.id,
        reason: 'Table ${ticket.tableId}',
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sipariş mutfağa gönderildi'),
        duration: Duration(seconds: 2),
      ),
    );
    context.go(AppRoutes.tables);
  }

  /// Table mode secondary: persist the ticket (so unsent items are not lost
  /// mid-flow) and jump to the payment screen.
  Future<void> _onOpenCheckout(BuildContext context, WidgetRef ref) async {
    final ticket = ref.read(currentTicketProvider);
    if (ticket == null) return;
    await ref.read(currentTicketProvider.notifier).saveCurrentTicket();
    if (!context.mounted) return;
    context.push(AppRoutes.paymentFor(ticket.id));
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
  const _MenuArea({this.leftHanded = false});

  /// When true, the category rail swaps to the right so the menu area
  /// mirrors the outer layout flip — keeps the operator's categories and
  /// order panel on the same side of the grid.
  final bool leftHanded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, bc) {
        final catW = bc.maxWidth >= 1400 ? 300.0 : (bc.maxWidth >= 1200 ? 280.0 : 240.0);
        final cats = SizedBox(
          width: catW,
          child: _CategoryList(leftHanded: leftHanded),
        );
        const items = Expanded(child: _ItemsWrap());
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: leftHanded
              ? <Widget>[items, cats]
              : <Widget>[cats, items],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// CATEGORY LIST  — parts.jsx `CategoryList`
// ---------------------------------------------------------------------------

class _CategoryList extends ConsumerWidget {
  const _CategoryList({this.leftHanded = false});

  /// In left-hand mode the category rail sits on the right of the menu area
  /// — flip its hairline divider to the left edge so it still faces the
  /// item grid.
  final bool leftHanded;

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
    final side = BorderSide(color: v2.line);
    final fastSale = FastSaleModeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: v2.surface,
        border: leftHanded ? Border(left: side) : Border(right: side),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Round-10: search input migrated here from the (now-removed)
          // topbar — the categories panel is the natural home for menu
          // navigation, and putting the search inline keeps it close to
          // the items grid that actually responds to it.
          if (fastSale) ...[
            const _CategorySearchField(),
            const SizedBox(height: 10),
          ],
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
            ticket: ticket,
            total: total,
          ),
        ],
      ),
    );
  }
}

/// Slim search field that drives [productSearchProvider]. Lives at the
/// top of the categories column in fast-sale (round-10 — replaced the
/// topbar search). Keeps its own controller so a programmatic provider
/// reset (e.g. shift close) clears the visible text too.
class _CategorySearchField extends ConsumerStatefulWidget {
  const _CategorySearchField();

  @override
  ConsumerState<_CategorySearchField> createState() =>
      _CategorySearchFieldState();
}

class _CategorySearchFieldState
    extends ConsumerState<_CategorySearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: ref.read(productSearchProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    final hasText = _controller.text.isNotEmpty;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: v2.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: v2.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: v2.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() {
                ref.read(productSearchProvider.notifier).state = v;
              }),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: v2.ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: 'Suchen…',
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: v2.ink4,
                ),
              ),
            ),
          ),
          if (hasText)
            InkWell(
              onTap: () {
                _controller.clear();
                ref.read(productSearchProvider.notifier).state = '';
                setState(() {});
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: v2.ink3),
              ),
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
                  // Round-5 cosmetic fix: removed the 1dp white "inset
                  // highlight" line at the top of every category tile —
                  // operator read it as a scratch / glitch on tiles.
                  // Drop shadow on the parent already gives enough depth.
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

/// Footer of the category column.
///
/// v3 (2026-05-13): the BAR / KARTE / TWINT chips moved into the cart-
/// column footer (`_OrderFoot` → `_CartPayButtons`) so the payment row
/// sits directly under the bill it settles. This widget now renders an
/// empty placeholder so the categories grid expands to fill the column;
/// the class is retained as a stub to avoid churning the single call
/// site and the test imports that reference `_CatsFooter` lookups.
class _CatsFooter extends ConsumerWidget {
  const _CatsFooter({required this.ticket, required this.total});
  final TicketEntity? ticket;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SizedBox.shrink();
  }
}

// _PayChip removed in v3 — superseded by _BigPayBtn (cart-column footer).
// Kept here as a header comment so a reader doing a textual diff against
// the v2 shell sees where the icon-only quick-pay chip lived.

class _ZurKasseLink extends StatelessWidget {
  const _ZurKasseLink({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    return Material(
      color: enabled ? v2.surface2 : const Color(0xFFEFEAE2),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: v2.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.call_split_rounded,
                size: 14,
                color: enabled ? v2.ink2 : v2.ink4,
              ),
              const SizedBox(width: 6),
              Text(
                'ZUR KASSE · TEILEN',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: enabled ? v2.ink2 : v2.ink4,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Direct settle helper — used by the NAKİT / KART quick-pay chips. Records
/// a single full-amount payment, closes the ticket, and routes to the
/// receipt screen so the operator can print or move on. The button itself
/// is the confirmation; cancellation lives on the receipt screen.
/// BAR button entry point — round-3 operator request: open a supermarket-
/// style cash dialog (denominations + numpad + Rückgeld) instead of the
/// legacy one-tap settle. The cashier picks how much was tendered, the
/// dialog returns it in cents, and we settle with that as the
/// `tenderedAmount` so the change calculation in
/// `paymentRepository.processPayment` lands a non-zero `changeAmount`
/// that prints on the receipt.
Future<void> _onBarTapped(
  BuildContext context,
  WidgetRef ref,
  TicketEntity ticket,
) async {
  if (ticket.items.isEmpty) return;
  // Persist the cart up-front so the dialog total reflects what the
  // database will actually charge (in case modifiers / discounts moved
  // the total between the panel render and the BAR tap).
  final saved =
      await ref.read(currentTicketProvider.notifier).saveCurrentTicket();
  if (saved == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adisyon kaydedilemedi.')),
    );
    return;
  }
  if (!context.mounted) return;
  // Round-7: Swiss 5-Rappen rounding. Cash customers can only pay in
  // 5-cent increments — round the grand total before opening the
  // dialog so Bezahlt / Rückgeld math lands on real coins. Card path
  // (KARTE) doesn't round; the terminal handles arbitrary cents.
  final cashTotal = swissRoundCents(saved.total);

  // Cash Collector path: when Settings ▸ Payment ▸ KASA OTOMATI is on,
  // skip the manual denomination dialog entirely. The kiosk takes the
  // money straight from the customer and dispenses change; we settle
  // with the actually-collected amount as `tenderedAmount` so the
  // receipt's Rückgeld matches what the device gave out.
  final collectorCfg = ref
      .read(paymentSettingsProvider)
      .valueOrNull
      ?.cashCollector;
  if (collectorCfg != null && collectorCfg.enabled) {
    final result = await showCashCollectorDialog(
      context,
      config: collectorCfg,
      saleAmountCents: cashTotal,
    );
    if (!context.mounted) return;
    if (result == null) return; // operator cancelled, no money in escrow
    if (result.fallbackToManual) {
      // Kiosk down / jammed / operator preference — fall through to the
      // manual cash dialog for this one transaction. Toggle stays on, so
      // the next sale tries the device again.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Manuel nakit girişine geçildi.'),
          duration: Duration(seconds: 3),
        ),
      );
      final tendered = await showCashPaymentDialog(
        context,
        grandTotalCents: cashTotal,
      );
      if (tendered == null) return;
      if (!context.mounted) return;
      await _quickSettle(
        context: context,
        ref: ref,
        method: PaymentMethod.cash,
        label: 'Bar',
        tenderedOverride: tendered,
        cashAmountOverride: cashTotal,
      );
      return;
    }
    if (result.refund > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cihaz ${(result.refund / 100).toStringAsFixed(2)} CHF iade veremedi — elden geri verin.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    await _quickSettle(
      context: context,
      ref: ref,
      method: PaymentMethod.cash,
      label: 'Bar',
      tenderedOverride: result.collected,
      cashAmountOverride: cashTotal,
    );
    return;
  }

  final tendered = await showCashPaymentDialog(
    context,
    grandTotalCents: cashTotal,
  );
  if (tendered == null) return; // cashier cancelled
  if (!context.mounted) return;
  await _quickSettle(
    context: context,
    ref: ref,
    method: PaymentMethod.cash,
    label: 'Bar',
    tenderedOverride: tendered,
    cashAmountOverride: cashTotal,
  );
}

/// TWINT quick-pay chip entry point. Sibling of `_onKarteTapped` — the
/// MyPOS Sigma talks to the customer's TWINT app via `twintPurchase`
/// when the terminal is enabled. With the toggle off we fall back to
/// the legacy "manual confirmation" flow: the cashier eyeballs the
/// customer's phone and one-taps the sale closed, exactly like KARTE
/// used to behave. PaymentMethod.other is the established TWINT slot
/// (see payment_screen's `_referenceFor`).
Future<void> _onTwintTapped(
  BuildContext context,
  WidgetRef ref,
  TicketEntity ticket,
) async {
  if (ticket.items.isEmpty) return;
  final saved =
      await ref.read(currentTicketProvider.notifier).saveCurrentTicket();
  if (saved == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adisyon kaydedilemedi.')),
    );
    return;
  }
  if (!context.mounted) return;

  final myposCfg = ref.read(paymentSettingsProvider).valueOrNull?.mypos;
  if (myposCfg != null && myposCfg.enabled) {
    final result = await showMyPosPaymentDialog(
      context,
      // TWINT is CHF-only at the SDK level; force currency regardless of
      // whatever the operator typed in settings.
      config: myposCfg.copyWith(currency: 'CHF'),
      amountCents: saved.total,
      flow: MyPosFlow.twint,
    );
    if (!context.mounted) return;
    if (result == null) return;
    if (result.fallbackToManual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Manuel TWINT onayına geçildi.'),
          duration: Duration(seconds: 3),
        ),
      );
      await _quickSettle(
        context: context,
        ref: ref,
        method: PaymentMethod.other,
        label: 'TWINT',
        referenceOverride: 'TWINT',
      );
      return;
    }
    if (!result.approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Terminal reddetti: ${result.errorMessage ?? "bilinmeyen hata"}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    await _quickSettle(
      context: context,
      ref: ref,
      method: PaymentMethod.other,
      label: 'TWINT',
      referenceOverride: 'MYPOS:TWINT:${result.transactionId}',
    );
    return;
  }

  // Toggle off — manual confirmation flow (operator eyeballs the phone).
  await _quickSettle(
    context: context,
    ref: ref,
    method: PaymentMethod.other,
    label: 'TWINT',
    referenceOverride: 'TWINT',
  );
}

/// KARTE quick-pay chip entry point. Mirrors `_onBarTapped`: when the
/// MyPOS terminal is enabled, open the live dialog instead of one-tap-
/// settling. Cashier no longer has to walk to the terminal and tap it
/// manually — the SDK pushes the amount automatically and we settle
/// only on terminal-side approval.
Future<void> _onKarteTapped(
  BuildContext context,
  WidgetRef ref,
  TicketEntity ticket,
) async {
  if (ticket.items.isEmpty) return;
  final saved =
      await ref.read(currentTicketProvider.notifier).saveCurrentTicket();
  if (saved == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adisyon kaydedilemedi.')),
    );
    return;
  }
  if (!context.mounted) return;

  final myposCfg = ref.read(paymentSettingsProvider).valueOrNull?.mypos;
  if (myposCfg != null && myposCfg.enabled) {
    final result = await showMyPosPaymentDialog(
      context,
      config: myposCfg,
      amountCents: saved.total,
      flow: MyPosFlow.card,
    );
    if (!context.mounted) return;
    if (result == null) return; // cancelled — terminal idle
    if (result.fallbackToManual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Manuel KART kaydına geçildi.'),
          duration: Duration(seconds: 3),
        ),
      );
      await _quickSettle(
        context: context,
        ref: ref,
        method: PaymentMethod.creditCard,
        label: 'Karte',
      );
      return;
    }
    if (!result.approved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Terminal reddetti: ${result.errorMessage ?? "bilinmeyen hata"}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    final ref0 =
        'MYPOS:${result.cardType ?? "CARD"}:${result.transactionId}';
    await _quickSettle(
      context: context,
      ref: ref,
      method: PaymentMethod.creditCard,
      label: 'Karte',
      referenceOverride: ref0,
    );
    return;
  }

  await _quickSettle(
    context: context,
    ref: ref,
    method: PaymentMethod.creditCard,
    label: 'Karte',
  );
}

Future<void> _quickSettle({
  required BuildContext context,
  required WidgetRef ref,
  required PaymentMethod method,
  required String label,
  int? tenderedOverride,
  // Round-7: BAR path passes the Swiss-rounded total here so the bill
  // amount the customer actually paid (e.g. CHF 27.80) is what hits the
  // payment row, not the unrounded ticket.total (CHF 27.79). The
  // 1-cent difference is logged in the audit reason for reconciliation.
  int? cashAmountOverride,
  /// Replace the default 'QUICK' reference (e.g. MyPOS approval payload
  /// `MYPOS:VISA:000123…`) so the receipt + audit row carry terminal data.
  String? referenceOverride,
}) async {
  final ticket = ref.read(currentTicketProvider);
  if (ticket == null || ticket.items.isEmpty) return;

  // Persist the cart first — payment_repository.processPayment reads the
  // ticket totals to derive the bill row, so an unsaved draft would
  // mis-bill.
  final saved =
      await ref.read(currentTicketProvider.notifier).saveCurrentTicket();
  if (saved == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Adisyon kaydedilemedi.')),
    );
    return;
  }

  HapticFeedback.mediumImpact();

  final tenantId = ref.read(tenantIdProvider);
  final user = ref.read(currentUserProvider);
  final receivedBy = user?.name ?? 'POS';
  final repo = ref.read(paymentRepositoryProvider);
  final amountCents = cashAmountOverride ?? saved.total;
  // BAR (cash) path may pass a tenderedOverride from the cash dialog so
  // the receipt prints the right Rückgeld. Card / others always tender
  // exactly the bill — no change.
  final tendered = tenderedOverride ?? amountCents;

  try {
    await repo.processPayment(
      ticketId: saved.id,
      tenantId: tenantId,
      paymentMethod: method,
      amount: amountCents,
      tenderedAmount: tendered,
      receivedBy: receivedBy,
      reference: method == PaymentMethod.cash
          ? null
          : (referenceOverride ?? 'QUICK'),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ödeme başarısız: $e')),
    );
    return;
  }

  // Nudge the sync engine right after the sale lands so the cloud sees
  // it within ~1s instead of waiting for the next periodic tick. No-op
  // for local-demo sessions (the notifier early-returns when offline).
  unawaited(ref.read(syncProvider.notifier).sync());

  final roundingDelta = amountCents - saved.total;
  unawaited(
    ref.read(auditServiceProvider).log(
          action: AuditAction.paymentReceived,
          entityType: 'ticket',
          entityId: saved.id,
          reason: 'QUICK $label CHF ${(amountCents / 100).toStringAsFixed(2)}'
              '${roundingDelta != 0 ? ' (Rundung ${roundingDelta > 0 ? '+' : ''}${(roundingDelta / 100).toStringAsFixed(2)})' : ''}',
        ),
  );

  // Round-4 operator request: replace the full receipt-detail screen with
  // a compact "Beleg drucken / OK" dialog so the cashier returns to the
  // empty cart in two taps instead of navigating away. Receipt detail
  // route still exists for manual reprints from the Bons history list.
  final change = (tendered - amountCents).clamp(0, 1 << 31);
  // Snapshot the ticket BEFORE clearing so the printer facade can render
  // the receipt even though the cart panel is already empty visually.
  final snapshot = saved;
  ref.read(currentTicketProvider.notifier).clear();

  if (!context.mounted) return;
  final shouldPrint = await showPaymentSuccessDialog(
    context,
    changeCents: change,
  );
  if (shouldPrint == true) {
    await _printQuickPayReceipt(
      ref: ref,
      ticket: snapshot,
      method: method,
      cashierName: receivedBy,
    );
  }
}

/// Renders a quick-pay receipt straight to the printer facade. Called
/// only when the cashier picked "Beleg drucken" on the success dialog —
/// `autoPrintOnPayment` setting is intentionally ignored here because
/// the user just explicitly asked for a print. Takes a passed-in
/// [TicketEntity] snapshot so it still works after the active cart has
/// been cleared (clearing happens before the dialog so the panel
/// returns to empty state regardless of the operator's choice).
Future<void> _printQuickPayReceipt({
  required WidgetRef ref,
  required TicketEntity ticket,
  required PaymentMethod method,
  required String cashierName,
}) async {
  final items = ticket.items
      .map(_quickPayReceiptItem)
      .toList(growable: false);
  final paymentLabel = switch (method) {
    PaymentMethod.cash => 'Bargeld',
    PaymentMethod.creditCard => 'Karte',
    PaymentMethod.debitCard => 'Karte',
    _ => 'Andere',
  };
  final req = ReceiptPrintRequest(
    orderNo: ticket.orderNumber,
    orderTime: ticket.openedAt,
    tableOrTakeaway: ticket.tableId ?? 'Takeaway',
    cashierName: cashierName,
    customerName: '',
    items: items,
    discount: ticket.discountAmount / 100.0,
    tip: 0,
    paymentMethod: paymentLabel,
    isCash: method == PaymentMethod.cash,
  );
  final facade = ref.read(receiptPrintFacadeProvider);
  try {
    await facade.printReceipt(req);
  } catch (_) {
    // Best-effort. Manual reprint via Bons → bon detail is the fallback.
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

    final fastSale = FastSaleModeScope.of(context);
    return ColoredBox(
      color: context.v2.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table-service: top Schnellbar (~68dp, bigger names, no price).
          if (!fastSale && allProducts.isNotEmpty)
            SizedBox(
              height: 68,
              child: _SchnellBar(products: allProducts),
            ),
          // Round-13 operator request: "su hizli urunleri uste koyaliam
          // alta degil ya". Fast-sale favourites strip moves from the
          // BOTTOM of the items column to the TOP — sits right above
          // the items grid so quick-pick products stay visible without
          // forcing the cashier to scroll past the grid. Same compact
          // 64dp height + fixed 120dp chips + name-only / ellipsis.
          if (fastSale && allProducts.isNotEmpty)
            SizedBox(
              height: 64,
              child: _FavoritesStripCompact(products: allProducts),
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
    // Round-3 operator feedback ("kucultme/buyutme ozelliği nerde
    // bulamadim"): the posTileScale slider lives deep in the Settings
    // screen, operators can't reach it during a rush. Surface a 4-step
    // size picker (S/M/L/XL) right inside the topbar Tweaks overlay so
    // the cashier can tap once to resize the items grid.
    final settings = ref.watch(restaurantSettingsProvider).valueOrNull;
    final scale = (settings?.posTileScale ?? 1.0).clamp(0.7, 1.5);
    final activeSize = PosTileSize.forScale(scale);
    final mode = settings?.posTileMode ?? PosTileMode.fixed;

    Future<void> setTileSize(PosTileSize next) async {
      await ref.read(restaurantSettingsProvider.notifier).update(
            (s) => s.copyWith(
              posTileScale: next.scale,
              // Picking a manual size implies "fixed" mode — autoFit
              // ignores the scale, which would feel broken when the
              // operator just tapped a size button.
              posTileMode: PosTileMode.fixed,
            ),
          );
    }

    // Round-7 redesign: tighter dropdown-style panel anchored to top-
    // right (under the Tweaks topbar icon). 360dp wide; section gaps
    // 10dp instead of 14; uppercase 10pt section headers; pronounced
    // shadow + rounded corners; Bericht link rendered as an outlined
    // primary button so it reads as a navigation, not a footnote.
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 64, 12, 0),
        child: SizedBox(
          width: 360,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            elevation: 18,
            shadowColor: const Color(0x33000000),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TWEAKS', style: _tweaksHeader),
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              size: 16, color: Color(0xFF8B92A0)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('KACHELGRÖSSE', style: _tweaksLabel),
                  const SizedBox(height: 6),
                  _TileSizeRow(
                    active: activeSize,
                    onPick: setTileSize,
                  ),
                  const SizedBox(height: 6),
                  _TileModeRow(
                    active: mode,
                    onPick: (m) async {
                      await ref
                          .read(restaurantSettingsProvider.notifier)
                          .update((s) => s.copyWith(posTileMode: m));
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text('PALETTE', style: _tweaksLabel),
                  const SizedBox(height: 6),
                  _SegmentedPair<PosPalette>(
                    leftLabel: 'Ivory',
                    leftValue: PosPalette.ivory,
                    rightLabel: 'Midnight',
                    rightValue: PosPalette.midnight,
                    value: palette,
                    onChanged: (v) async {
                      await ref.read(appSettingsProvider.notifier).setTheme(
                            v == PosPalette.midnight
                                ? AppThemeMode.dark
                                : AppThemeMode.light,
                          );
                    },
                  ),
                  const SizedBox(height: 10),
                  const Text('PRODUKTBILDER', style: _tweaksLabel),
                  const SizedBox(height: 6),
                  _SegmentedPair<bool>(
                    leftLabel: 'Aus',
                    leftValue: false,
                    rightLabel: 'An',
                    rightValue: true,
                    value: imagesOn,
                    onChanged: (v) async {
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setShowProductImages(v);
                    },
                  ),
                  const SizedBox(height: 14),
                  _BerichtLink(),
                  const SizedBox(height: 8),
                  _RailAnpassenLink(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick "open Bericht" link at the bottom of the Tweaks overlay.
/// Round-5: the rail no longer carries a Bericht entry; this is the
/// in-shell discovery path. Tap closes the overlay and pushes the
/// reports center route.
class _BerichtLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEEF4FB),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          context.push(AppRoutes.reportsCenter);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: const [
              Icon(Icons.insert_chart_outlined,
                  size: 16, color: Color(0xFF1F6FEB)),
              SizedBox(width: 8),
              Text(
                'Bericht öffnen',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F6FEB),
                ),
              ),
              Spacer(),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: Color(0xFF1F6FEB)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Rail anpassen" link — opens the rail-customisation dialog. Round-9
/// operator request: "kafama gore aktif pasif yapabileyim".
class _RailAnpassenLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF6E7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () async {
          // Close the Tweaks overlay first so the dialog isn't stacked
          // on top of a dimmed dropdown.
          Navigator.of(context).pop();
          await showDialog<void>(
            context: context,
            builder: (_) => const _RailConfigDialog(),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: const [
              Icon(Icons.tune_rounded,
                  size: 16, color: Color(0xFFB8860B)),
              SizedBox(width: 8),
              Text(
                'Rail anpassen',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB8860B),
                ),
              ),
              Spacer(),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: Color(0xFFB8860B)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Static descriptor of every togglable rail entry — drives the
/// "Rail anpassen" dialog. The `id` MUST match the literal `id:`
/// passed to `_RailBtn` (and `'fnGroup'` for the dynamic FUNKTION
/// block) so the rail's `disabledRailIds` lookup hits.
class _RailItemDef {
  const _RailItemDef(this.id, this.label, this.icon, {this.subtitle});
  final String id;
  final String label;
  final IconData icon;
  final String? subtitle;
}

const _kRailItemDefs = <_RailItemDef>[
  _RailItemDef('tables', 'Tische', Icons.table_restaurant_outlined,
      subtitle: 'Floor plan (sadece mix mode)'),
  _RailItemDef('fastSaleSwitch', 'Schnell', Icons.flash_on_rounded,
      subtitle: 'Hızlı satışa geç (sadece mix mode)'),
  _RailItemDef('bill', 'Bons', Icons.receipt_long_outlined,
      subtitle: 'Sipariş geçmişi'),
  _RailItemDef('fnGroup', 'FUNKTION', Icons.bolt_outlined,
      subtitle: 'Operatör tanımlı butonlar (Rabatt, Geschenk, …)'),
  _RailItemDef('cancel', 'Storno', Icons.block_outlined,
      subtitle: 'İade / iptal'),
  _RailItemDef('print', 'Drucken', Icons.print_outlined,
      subtitle: 'Mutfağa yazdır'),
  _RailItemDef('lock', 'Sperren', Icons.lock_outline,
      subtitle: 'Çıkış / kilit'),
];

/// Dialog: list every rail entry with a switch. Toggles write through
/// `AppSettings.disabledRailIds` so changes persist + the rail rebuilds
/// instantly. "Standard" button restores everything visible.
class _RailConfigDialog extends ConsumerWidget {
  const _RailConfigDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disabled =
        ref.watch(appSettingsProvider).valueOrNull?.disabledRailIds ??
            const <String>{};

    Future<void> setDisabled(Set<String> next) async {
      await ref
          .read(appSettingsProvider.notifier)
          .setDisabledRailIds(next);
    }

    void toggle(String id, bool enabled) {
      final next = Set<String>.from(disabled);
      if (enabled) {
        next.remove(id);
      } else {
        next.add(id);
      }
      setDisabled(next);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Rail anpassen',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 18, color: Color(0xFF8B92A0)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Sol menüde hangi butonlar görünsün? Değişiklikler '
                'anında kaydedilir.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              for (final def in _kRailItemDefs)
                _RailToggleTile(
                  def: def,
                  enabled: !disabled.contains(def.id),
                  onChanged: (v) => toggle(def.id, v),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setDisabled(const <String>{}),
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Standardı geri yükle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailToggleTile extends StatelessWidget {
  const _RailToggleTile({
    required this.def,
    required this.enabled,
    required this.onChanged,
  });
  final _RailItemDef def;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F4F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(def.icon, size: 16, color: const Color(0xFF425466)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.label,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                if (def.subtitle != null)
                  Text(
                    def.subtitle!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11.5,
                      color: Color(0xFF6B7280),
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Five-step tile size picker: XS / S / M / L / XL — wired to
/// `posTileScale` via the restaurant-settings notifier. Each tap snaps to
/// the canonical `PosTileSize` scale (0.7 / 0.85 / 1.0 / 1.2 / 1.5) and
/// flips `posTileMode` back to `fixed` so the chosen size actually
/// applies (autoFit ignores the scalar).
class _TileSizeRow extends StatelessWidget {
  const _TileSizeRow({required this.active, required this.onPick});
  final PosTileSize active;
  final ValueChanged<PosTileSize> onPick;

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
          for (final size in PosTileSize.values)
            _tileChip(size, active == size, () => onPick(size)),
        ],
      ),
    );
  }

  Widget _tileChip(PosTileSize size, bool selected, VoidCallback onTap) {
    final label = size.name.toUpperCase();
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? V2.ink : V2.ink3,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// Toggle between manual scale (`fixed`) and auto-fit packing (`autoFit`).
/// Surfaces alongside `_TileSizeRow` because the two are coupled — picking
/// autoFit explicitly tells the grid to ignore the manual scale.
class _TileModeRow extends StatelessWidget {
  const _TileModeRow({required this.active, required this.onPick});
  final PosTileMode active;
  final ValueChanged<PosTileMode> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _SegmentedPair<PosTileMode>(
        leftLabel: 'Manuell',
        leftValue: PosTileMode.fixed,
        rightLabel: 'AutoFit',
        rightValue: PosTileMode.autoFit,
        value: active,
        onChanged: onPick,
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

/// Compact horizontal favourites strip — round-8 fast-sale variant.
///
/// Sits at the BOTTOM of the items grid (the band the operator pointed to
/// in feedback: "bu kirmizi yere hizli butonlar lazim"). 64dp container,
/// scrollable horizontally, pulls the top-N products by `displayOrder`
/// so the merchant can pin frequently-sold items via the menu admin
/// without code changes.
///
/// Tap behaviour mirrors the legacy [_SchnellBar] — opens the modifier
/// dialog when needed, otherwise adds straight to the cart.
class _FavoritesStripCompact extends ConsumerWidget {
  const _FavoritesStripCompact({required this.products});
  final List<ProductEntity> products;

  static const int _maxFavorites = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = [...products]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final top = picks.take(_maxFavorites).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    final v2 = context.v2;
    return Container(
      decoration: BoxDecoration(
        color: v2.surface,
        border: Border(top: BorderSide(color: v2.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: top.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => _FavoriteChip(
          product: top[i],
          onTap: () => addProductToCurrentTicket(context, ref, top[i]),
        ),
      ),
    );
  }
}

class _FavoriteChip extends StatelessWidget {
  const _FavoriteChip({required this.product, required this.onTap});
  final ProductEntity product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v2 = context.v2;
    // Round-11 operator request: "butonlarin boyutlari sabit olsun ya
    // bak isim uzadikca buton uzuyor; fiyat olmasin direk urun isimleri
    // yeterli". Fixed 120dp wide chip, name only (price lives in the
    // items grid card and on the receipt). Long names ellipsis on a
    // single line so the strip never grows vertically.
    return SizedBox(
      width: 120,
      child: Semantics(
        button: true,
        label: 'Favorit ${product.name}',
        child: Material(
          color: const Color(0xFFEEF4FB),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDCE6F2)),
              ),
              child: Center(
                child: Text(
                  product.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: v2.ink,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    // M1 — route through the modifier-aware helper so Schnellverkauf
    // tiles open the dialog when the product carries modifier groups.
    await addProductToCurrentTicket(context, ref, product);
  }
}

class _SchnellTile extends ConsumerWidget {
  const _SchnellTile({required this.product, required this.onTap});
  final ProductEntity product;
  final VoidCallback onTap;

  static const Color _bg = Color(0xFFEEF4FB);
  static const Color _border = Color(0xFFDCE6F2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // M7 — Schnellverkauf tiles share the same operator-controlled
    // scale as the items grid so the two strips stay visually
    // consistent.
    final scale = (ref
                .watch(restaurantSettingsProvider)
                .valueOrNull
                ?.posTileScale ??
            1.0)
        .clamp(0.7, 1.5);

    // Round-12 operator request: "fiyatlari kaldir favori butonunda fiyat
    // olmasin, yazi voyutnu buyut, yuksekligni kucult". Dropped the CHF
    // row entirely; the name now centres in the full chip and uses a
    // bigger font (15pt × scale) for at-a-glance reads. Container
    // height is driven by the parent `SizedBox(height:64)` in
    // `_ItemsWrap` so the chip can't grow vertically — short single
    // line, ellipsis on overflow.
    return Semantics(
      button: true,
      label: 'Schnellverkauf ${product.name}',
      child: Material(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Center(
              child: ExcludeSemantics(
                child: Text(
                  product.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: V2Text.schnellName.copyWith(
                    fontSize: 15 * scale,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
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

    // M7 — apply the operator's preferred tile scale to BOTH the min
    // tile width (drives column count) and the row height. Smaller
    // scale = more tiles per row + shorter row height; larger scale =
    // chunkier targets, fewer columns. Clamp keeps GridView happy
    // when storage holds a stale free-form value.
    final settings = ref.watch(restaurantSettingsProvider).valueOrNull;
    final scale = (settings?.posTileScale ?? 1.0).clamp(0.7, 1.5);
    final mode = settings?.posTileMode ?? PosTileMode.fixed;

    // AutoFit: compute the column count that packs every product in
    // the active category into the visible viewport without scrolling.
    // Cell aspect ratio is targeted at 1.3 (slightly wider than tall —
    // mirrors the v2 fixed-mode tile, where 180×130 ≈ 1.38). Falls
    // back to a scrolling grid at the minimum cell size when the
    // category is too dense to fit (rare; pilot menus stay <60 SKUs
    // per category).
    if (mode == PosTileMode.autoFit) {
      return LayoutBuilder(
        builder: (context, bc) {
          final n = products.length;
          if (n == 0) return const _EmptyGrid();
          const gap = 10.0;
          const padding = EdgeInsets.fromLTRB(22, 6, 22, 20);
          final innerW = bc.maxWidth - padding.horizontal;
          final innerH = bc.maxHeight - padding.vertical;
          final pick = _bestColumnCount(n, innerW, innerH, gap: gap);
          final cols = pick.cols;
          final rows = (n / cols).ceil();
          final cellW = (innerW - (cols - 1) * gap) / cols;
          final cellH = (innerH - (rows - 1) * gap) / rows;
          // Aspect ratio for SliverGridDelegateWithFixedCrossAxisCount.
          // childAspectRatio = main-axis-extent's `crossAxisExtent/mainAxisExtent`.
          final ratio = cellW / cellH;
          // Cap at 100 products to keep `n` bounded; beyond that the
          // grid scrolls at the minimum cell size — same fallback the
          // bestColumn picker uses when no layout meets the floor.
          final tooDense = pick.fellBack;
          final delegate = SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: ratio,
          );
          Widget builder(int i) {
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
              autoFit: true,
              cellWidth: cellW,
              cellHeight: cellH,
              onTap: () => addProductToCurrentTicket(context, ref, p),
            );
          }

          return GridView.builder(
            padding: padding,
            physics: tooDense
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            gridDelegate: delegate,
            itemCount: n,
            itemBuilder: (context, i) => builder(i),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, bc) {
        final w = bc.maxWidth;
        final targetMin = (w >= 1500 ? 200.0 : 180.0) * scale;
        const gap = 10.0;
        final cols = ((w - 44 + gap) / (targetMin + gap)).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: 130 * scale,
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
              onTap: () => addProductToCurrentTicket(context, ref, p),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// AutoFit column picker
// ---------------------------------------------------------------------------

/// Result of [_bestColumnCount]. Carries the chosen column count and
/// whether the picker had to fall back to the floor configuration
/// (i.e. no column count cleared the minimum cell size, so the grid
/// will need to scroll).
class _AutoFitChoice {
  const _AutoFitChoice(this.cols, {this.fellBack = false});
  final int cols;
  final bool fellBack;
}

/// Picks the column count that best packs `n` products into a `w × h`
/// viewport. Iterates 1..8 columns, computes the resulting cell size,
/// and picks the one whose aspect ratio is closest to the v2 ideal
/// (≈1.3 — slightly wider than tall) without dropping below the
/// touch-target floor (80×60).
///
/// Algorithm:
///   * For each candidate column count `c`:
///       - rows = ceil(n / c)
///       - cellW = w / c, cellH = h / rows
///       - If cellW < 80 or cellH < 60 → skip (below touch floor)
///       - score = |1.3 - cellW/cellH|
///   * Pick the minimum-score candidate.
///   * If no candidate clears the floor, fall back to the densest
///     layout (highest column count tried) and signal `fellBack=true`
///     so the caller can switch the grid to scrollable.
_AutoFitChoice _bestColumnCount(
  int n,
  double w,
  double h, {
  double gap = 10.0,
}) {
  if (n <= 0) return const _AutoFitChoice(1);
  const minCellW = 80.0;
  const minCellH = 60.0;
  const maxCellW = 240.0;
  const maxCellH = 180.0;
  const targetRatio = 1.3;

  int? bestCols;
  double bestScore = double.infinity;
  int? fallbackCols;
  double fallbackScore = double.infinity;

  for (var c = 1; c <= 8; c++) {
    if (c > n && c > 1) break; // Never split fewer products into more cols.
    final rows = (n / c).ceil();
    final cellW = (w - (c - 1) * gap) / c;
    final cellH = (h - (rows - 1) * gap) / rows;
    if (cellW <= 0 || cellH <= 0) continue;
    final ratio = cellW / cellH;
    final score = (ratio - targetRatio).abs();
    // Clamp score harder when cells get too big (single product on a
    // big screen → 1 col, but we don't want a 800-wide cell either).
    final ratioPenalty = cellW > maxCellW || cellH > maxCellH ? 0.5 : 0.0;
    final total = score + ratioPenalty;
    final fitsFloor = cellW >= minCellW && cellH >= minCellH;
    if (fitsFloor) {
      if (total < bestScore) {
        bestScore = total;
        bestCols = c;
      }
    } else {
      // Track the candidate whose score is closest to ideal even
      // though it failed the touch-target floor — used as fallback if
      // *every* candidate fails (e.g. 100+ products on a small
      // viewport).
      if (total < fallbackScore) {
        fallbackScore = total;
        fallbackCols = c;
      }
    }
  }

  if (bestCols != null) {
    return _AutoFitChoice(bestCols);
  }
  // Floor fallback: pick whatever was closest to ideal even if it
  // would violate the floor — caller switches to scrollable.
  return _AutoFitChoice(fallbackCols ?? 4, fellBack: true);
}

class _PCard extends ConsumerWidget {
  const _PCard({
    required this.product,
    required this.qty,
    required this.palette,
    required this.onTap,
    this.autoFit = false,
    this.cellWidth,
    this.cellHeight,
  });

  final ProductEntity product;
  final int qty;
  final ({Color bg, Color bgWk}) palette;
  final VoidCallback onTap;

  /// True when the parent grid is in [PosTileMode.autoFit]. Causes the
  /// tile to derive font size + padding from `cellWidth` and
  /// `cellHeight` rather than the operator's [posTileScale].
  final bool autoFit;

  /// Cell dimensions calculated by the parent's auto-fit picker.
  /// Required when [autoFit] is true; ignored otherwise.
  final double? cellWidth;
  final double? cellHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = qty > 0;
    final imagesOn = ref.watch(productImagesEnabledProvider);
    final hasImage = imagesOn &&
        product.imagePath != null &&
        product.imagePath!.isNotEmpty;
    // M7 — pull the operator's tile scale and amplify the typography
    // alongside the grid sizing in `_ItemsGrid`. Falling back to 1.0
    // matches the pre-M7 baseline. Ignored under autoFit; the cell
    // size dictates font/padding instead.
    final scale = (ref
                .watch(restaurantSettingsProvider)
                .valueOrNull
                ?.posTileScale ??
            1.0)
        .clamp(0.7, 1.5);

    // AutoFit typography sizing: pick a base font size derived from
    // the cell's smaller dimension, clamped to a readable range. Same
    // formula keeps the price row proportional to the name.
    final autoBase = autoFit
        ? ((cellWidth ?? 180) < (cellHeight ?? 130)
                ? (cellWidth ?? 180)
                : (cellHeight ?? 130)) /
            8.0
        : 0.0;
    final autoNameSize = autoBase.clamp(10.0, 32.0);
    final autoPriceSize = (autoBase * 1.05).clamp(10.0, 36.0);
    final autoCurrencySize = (autoBase * 0.7).clamp(8.0, 22.0);
    // Padding shrinks on small cells so name/price still fit.
    final autoPadding = autoFit
        ? (autoBase < 12
            ? const EdgeInsets.all(4)
            : autoBase < 18
                ? const EdgeInsets.all(8)
                : const EdgeInsets.all(12))
        : const EdgeInsets.fromLTRB(14, 10, 14, 10);

    // M6 — pilot decision: tiles only carry name + price. The product
    // description is still queryable in BackOffice but never rendered
    // on the sales grid.
    //
    // a11y: flatten the product card to a single button node. Screen
    // readers announce "Espresso, CHF 4.50, 2 im Warenkorb" rather than
    // walking through the name, currency, price, and badge as four
    // separate leaves. excludeSemantics: true on the Semantics wrapper
    // suppresses every descendant's natural semantic tree.
    final cartHint = inCart ? ', $qty im Warenkorb' : '';
    return Semantics(
      button: true,
      label: '${product.name}, CHF ${v2Chf(product.price)}$cartHint',
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
              padding: autoPadding,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // M6: description (subtitle) intentionally dropped —
                  // pilot crews want only the product name on the tile
                  // so the cashier's eye lands on the right button
                  // faster on a packed grid.
                  //
                  // Centred horizontally + vertically inside the
                  // expanded slot so the eye lands on the name first,
                  // regardless of word length. Price row stays anchored
                  // at the bottom and is also centred.
                  Expanded(
                    child: Center(
                      child: Text(
                        product.name,
                        textAlign: TextAlign.center,
                        style: V2Text.pName.copyWith(
                          fontSize: autoFit
                              ? autoNameSize
                              : (V2Text.pName.fontSize == null
                                  ? null
                                  : V2Text.pName.fontSize! * scale),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'CHF',
                        style: V2Text.pCurrency.copyWith(
                          fontSize: autoFit
                              ? autoCurrencySize
                              : (V2Text.pCurrency.fontSize == null
                                  ? null
                                  : V2Text.pCurrency.fontSize! * scale),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        v2Chf(product.price),
                        style: V2Text.pPrice.copyWith(
                          fontSize: autoFit
                              ? autoPriceSize
                              : (V2Text.pPrice.fontSize == null
                                  ? null
                                  : V2Text.pPrice.fontSize! * scale),
                        ),
                      ),
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

// ---------------------------------------------------------------------------
// Add-product flow — modifier-aware (M1)
// ---------------------------------------------------------------------------

/// Single entry point used by every "tap product to add" surface in the
/// pilot v2 shell (Schnellverkauf grid, category grid, search results).
///
/// Behaviour:
///   * Ensures a draft ticket exists. If the cashier hasn't started one
///     yet this method spins up `currentTicketProvider`'s draft using
///     the active staff session.
///   * If the product carries one or more modifier groups, opens the
///     modifier dialog (modal bottom sheet). Cancelling drops the add
///     silently. Confirming forwards the operator's selections (with
///     the `OrderItemModifierEntity` plumbing the dialog already builds
///     out) into `addItem`.
///   * If the product has no modifier groups, falls through to the
///     fast-path `addItem(product, course: gang)` — and forwards the
///     active seat from `activeSeatProvider` so M3 multi-guest mode
///     tags the new line item with `Person N` automatically.
///
/// Marked top-level + `@visibleForTesting` so widget tests can drive
/// the modifier path without instantiating the whole shell.
@visibleForTesting
Future<void> addProductToCurrentTicket(
  BuildContext context,
  WidgetRef ref,
  ProductEntity product, {
  int? overrideSeat,
}) async {
  final notifier = ref.read(currentTicketProvider.notifier);
  var ticket = ref.read(currentTicketProvider);
  final gang = ref.read(activeGangProvider);
  final seat = overrideSeat ?? ref.read(activeSeatProvider);
  final fastSale = FastSaleModeScope.of(context);

  if (ticket == null) {
    final user = ref.read(currentUserProvider);
    // Fast-sale: inherit the cashier's last-picked order type so the
    // segmented selector survives between tickets (snack-bar flow).
    final orderType = fastSale
        ? ref.read(fastSalePendingOrderTypeProvider)
        : OrderType.dineIn;
    await notifier.createNewTicket(
      deviceId: 'DEV-POS-01',
      waiterId: user?.id,
      orderType: orderType,
    );
    ticket = ref.read(currentTicketProvider);
  }
  if (ticket == null) return;

  if (product.modifierGroups.isEmpty) {
    notifier.addItem(product, course: gang, seatNumber: seat);
    return;
  }

  if (!context.mounted) return;
  final result = await showModifierDialog(
    context: context,
    productName: product.name,
    productPrice: product.price,
    modifierGroups: ModifierGroupData.fromProductEntity(product),
  );
  if (result == null) return;

  final orderModifiers = <OrderItemModifierEntity>[
    for (final sel in result.flattened())
      OrderItemModifierEntity(
        id: IdGenerator.generateId(),
        orderItemId: '',
        modifierId: sel.option.id,
        modifierName: sel.displayName,
        priceDelta: sel.option.priceDelta,
        quantity: sel.quantity,
        note: sel.note,
      ),
  ];

  notifier.addItem(
    product,
    quantity: result.quantity.toDouble(),
    selectedModifiers: orderModifiers,
    notes: result.notes.isNotEmpty ? result.notes : null,
    course: gang,
    seatNumber: seat,
  );
}

/// Order-item → printable receipt-item mapping. Mirrors the helper in the
/// numpad payment screen but trimmed to the fields the quick-pay flow
/// actually uses (no tip, no voucher, no loyalty).
ReceiptItem _quickPayReceiptItem(OrderItemEntity it) {
  final unit = it.unitPrice / 100.0;
  final net = it.subtotal - it.taxAmount;
  final rate = (net > 0 && it.taxAmount > 0)
      ? (it.taxAmount / net) * 100.0
      : (it.taxGroup == 'accommodation' ? 3.8 : 8.1);
  final roundedRate = (rate * 10).round() / 10.0;
  return ReceiptItem(
    qty: it.quantity.round().clamp(1, 1 << 30),
    name: it.productName,
    unitPrice: unit,
    vatRate: roundedRate,
  );
}
