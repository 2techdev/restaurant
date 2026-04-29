/// Dashboard / Home Screen for GastroCore POS – Stitch V2 Design.
///
/// Replaces the old launcher-grid with a full analytics dashboard showing:
///   • KPI cards (revenue, orders, avg order, table occupancy)
///   • Quick-action buttons (new order, floor plan, open/close shift)
///   • Hourly sales bar chart (fl_chart)
///   • Payment method breakdown (cash / card / other)
///   • Recent orders list (last 10)
///   • Active shift information card
///   • Hardware status indicator (printer + terminal)
///
/// Data is provided by [dashboardSummaryProvider] and refreshed every
/// 30 seconds via a timer and on every screen mount (autoDispose).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/providers/connectivity_provider.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';
import 'package:gastrocore_pos/features/home/presentation/providers/dashboard_provider.dart';
import 'package:gastrocore_pos/features/home/domain/entities/dashboard_summary.dart';
import 'package:gastrocore_pos/features/sync/presentation/widgets/sync_status_widget.dart';
import 'package:gastrocore_pos/features/waiter/presentation/widgets/service_call_bell.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';
import 'package:gastrocore_pos/shared/widgets/gc_sidebar.dart';

// ---------------------------------------------------------------------------
// CHF formatter (Swiss locale)
// ---------------------------------------------------------------------------

final _chf = NumberFormat.currency(locale: 'de_CH', symbol: 'CHF ', decimalDigits: 2);

String _formatChf(int cents) => _chf.format(cents / 100);

// ---------------------------------------------------------------------------
// HomeScreen
// ---------------------------------------------------------------------------

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _now = DateTime.now());
      ref.invalidate(dashboardSummaryProvider);
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final shift = ref.watch(currentShiftProvider);
    final userName = user?.name ?? 'Staff';

    return Scaffold(
      key: const Key('home_screen'),
      backgroundColor: AppColors.surfaceDim,
      body: Row(
        children: [
          GcSidebar(
            activeRoute: '/home',
            userName: userName,
            userInitials: userName.isNotEmpty
                ? userName.substring(0, 1).toUpperCase()
                : '?',
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(userName: userName, shift: shift, now: _now),
                Expanded(child: _DashboardBody(shift: shift)),
                _Footer(
                  onSignOut: () {
                    ref.read(currentUserProvider.notifier).logout();
                    context.go(AppRoutes.login);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar (96 px, icon-based navigation)
// ---------------------------------------------------------------------------

// ignore: unused_element
class _Sidebar extends StatelessWidget {
  final ShiftEntity? shift;
  const _Sidebar({required this.shift});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = [
      _SidebarItem(icon: Icons.shopping_cart_outlined, label: l10n.posOrder, route: AppRoutes.orderCenter, itemKey: const Key('module_order')),
      _SidebarItem(icon: Icons.receipt_long_outlined, label: l10n.orderHistory, route: AppRoutes.orderHistory),
      _SidebarItem(icon: Icons.grid_view_outlined, label: l10n.navTables, route: AppRoutes.orderCenter),
      _SidebarItem(icon: Icons.restaurant_menu_outlined, label: l10n.navMenu, route: AppRoutes.backOffice),
      _SidebarItem(icon: Icons.tv_outlined, label: l10n.navKitchen, route: AppRoutes.kitchen),
      _SidebarItem(icon: Icons.bar_chart_rounded, label: 'Raporlar', route: AppRoutes.analytics),
      _SidebarItem(icon: Icons.verified_rounded, label: 'Z-Rapport', route: AppRoutes.reportsCenter),
    ];

    return Container(
      width: 96,
      color: AppColors.surfaceDim,
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Center(
              child: Text(
                'GC',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          ...items.map((item) => _SidebarButton(item: item)),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.person, size: 20, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final String label;
  final String route;
  final Key? itemKey;
  const _SidebarItem({required this.icon, required this.label, required this.route, this.itemKey});
}

class _SidebarButton extends StatefulWidget {
  final _SidebarItem item;
  const _SidebarButton({required this.item});

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: widget.item.itemKey,
          onTap: () => context.go(widget.item.route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 64,
            height: 56,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.item.icon, size: 22,
                    color: _hovered ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(height: 3),
                Text(widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: _hovered ? AppColors.primary : AppColors.textSecondary,
                      letterSpacing: -0.3,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends ConsumerWidget {
  final String userName;
  final ShiftEntity? shift;
  final DateTime now;

  const _TopBar({required this.userName, required this.shift, required this.now});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shiftOpen = shift != null && shift!.isOpen;
    final connectivity = ref.watch(connectivityProvider);
    final isOffline = connectivity == ConnectivityState.offline;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      color: AppColors.surfaceDim,
      child: Row(
        children: [
          const Flexible(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'Gastro',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary, letterSpacing: -0.5,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    'Core POS',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900,
                      color: AppColors.primary, letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Flexible(
            child: Text(userName.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary, letterSpacing: 0.5,
                )),
          ),
          const SizedBox(width: 16),
          // Shift chip — tap to open/close shift (Schichtwechsel).
          InkWell(
            key: const Key('topbar_shift_chip'),
            onTap: () => context
                .push(shiftOpen ? AppRoutes.shiftClose : AppRoutes.shiftOpen),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: shiftOpen
                    ? AppColors.green.withValues(alpha: 0.12)
                    : AppColors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: shiftOpen ? AppColors.green : AppColors.red,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  shiftOpen
                      ? l10n.shiftStatusOpen.toUpperCase()
                      : l10n.shiftNoActiveShift.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: shiftOpen ? AppColors.green : AppColors.red,
                    letterSpacing: 0.8,
                  ),
                ),
              ]),
            ),
          ),
          const Spacer(),
          if (isOffline) ...[
            Container(
              key: const Key('topbar_offline_chip'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 12, color: AppColors.red),
                const SizedBox(width: 6),
                Text(
                  l10n.statusOffline.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.red, letterSpacing: 0.8,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
          ],
          const _LanguageSwitcher(),
          const SizedBox(width: 8),
          const _ReportsMenu(),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(DateFormat('EEE, MMM d').format(now),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text(DateFormat('HH:mm').format(now),
                  style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary, letterSpacing: -0.5,
                  )),
            ],
          ),
          const SizedBox(width: 16),
          const ServiceCallBell(),
          const SizedBox(width: 12),
          const SyncStatusWidget(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language switcher (DE / FR / IT / EN / TR) — popup menu in top bar.
// ---------------------------------------------------------------------------

class _LanguageSwitcher extends ConsumerWidget {
  const _LanguageSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final current = settingsAsync.valueOrNull?.language ?? AppLanguage.de;

    return PopupMenuButton<AppLanguage>(
      key: const Key('topbar_language_switcher'),
      tooltip: 'Dil / Sprache',
      position: PopupMenuPosition.under,
      initialValue: current,
      onSelected: (lang) =>
          ref.read(appSettingsProvider.notifier).setLanguage(lang),
      itemBuilder: (_) => [
        for (final lang in AppLanguage.values)
          PopupMenuItem<AppLanguage>(
            value: lang,
            child: Row(children: [
              Text(lang.flag, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Text(
                lang.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      lang == current ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              if (lang == current) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_rounded,
                    size: 14, color: AppColors.primary),
              ],
            ]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.language_rounded,
              size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            current.name.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down_rounded,
              size: 16, color: AppColors.textSecondary),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reports menu (Z-Bericht / X-Bericht / Gün Sonu) — popup menu in top bar.
// ---------------------------------------------------------------------------

class _ReportsMenu extends StatelessWidget {
  const _ReportsMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('topbar_reports_menu'),
      tooltip: 'Raporlar',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'z':
            context.push(AppRoutes.zReport);
          case 'x':
            // Z-Report screen also exposes the X-Report print button
            // (Zwischenbericht, no register reset).
            context.push(AppRoutes.zReport);
          case 'dayclose':
            context.go(AppRoutes.dayClose);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          key: Key('menu_z_report'),
          value: 'z',
          child: Row(children: [
            Icon(Icons.assessment_rounded,
                size: 16, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Z-Raporu',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ]),
        ),
        PopupMenuItem<String>(
          key: Key('menu_x_report'),
          value: 'x',
          child: Row(children: [
            Icon(Icons.receipt_long_rounded,
                size: 16, color: AppColors.orange),
            SizedBox(width: 10),
            Text('X-Raporu',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ]),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          key: Key('menu_day_close'),
          value: 'dayclose',
          child: Row(children: [
            Icon(Icons.lock_clock_rounded,
                size: 16, color: AppColors.orange),
            SizedBox(width: 10),
            Text('Gün Sonu / Kassensturz',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.bar_chart_rounded,
              size: 14, color: AppColors.textSecondary),
          SizedBox(width: 6),
          Text(
            'RAPORLAR',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(width: 4),
          Icon(Icons.arrow_drop_down_rounded,
              size: 16, color: AppColors.textSecondary),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard body – assembles all widgets
// ---------------------------------------------------------------------------

class _DashboardBody extends ConsumerWidget {
  final ShiftEntity? shift;
  const _DashboardBody({required this.shift});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final hardware = ref.watch(hardwareStatusProvider);

    return summaryAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
      error: (err, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 40),
          const SizedBox(height: 12),
          const Text('Failed to load dashboard',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(err.toString(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
      ),
      data: (summary) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _KpiRow(summary: summary),
            const SizedBox(height: 12),
            _QuickActions(shift: shift),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: Row(children: [
                Expanded(flex: 6, child: _HourlySalesChart(summary: summary)),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: _PaymentBreakdownCard(summary: summary)),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: Row(children: [
                Expanded(flex: 6, child: _RecentOrdersList(orders: summary.recentOrders)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(children: [
                    Expanded(child: _ShiftInfoCard(shift: summary.currentShift)),
                    const SizedBox(height: 10),
                    _HardwareStatusRow(hardware: hardware),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI cards row
// ---------------------------------------------------------------------------

class _KpiRow extends StatelessWidget {
  final DashboardSummaryEntity summary;
  const _KpiRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(children: [
      Expanded(child: _KpiCard(
        label: l10n.dashboardDailyRevenue.toUpperCase(),
        value: _formatChf(summary.dailyRevenueCents),
        icon: Icons.payments_outlined,
        iconColor: AppColors.primary,
      )),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard(
        label: l10n.dashboardOrders.toUpperCase(),
        value: summary.dailyOrderCount.toString(),
        icon: Icons.receipt_long_outlined,
        iconColor: AppColors.green,
      )),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard(
        label: l10n.dashboardAvgOrder.toUpperCase(),
        value: _formatChf(summary.dailyAverageOrderCents),
        icon: Icons.trending_up_outlined,
        iconColor: AppColors.orange,
      )),
      const SizedBox(width: 10),
      Expanded(child: _KpiCard(
        label: l10n.navTables.toUpperCase(),
        value: '${summary.occupiedTableCount} / ${summary.totalTableCount}',
        icon: Icons.table_restaurant_outlined,
        iconColor: AppColors.purple,
        subLabel: summary.totalTableCount > 0
            ? '${(summary.tableOccupancyRate * 100).round()}% ${l10n.tableOccupied.toLowerCase()}'
            : null,
      )),
    ]);
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String? subLabel;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary, letterSpacing: 0.6,
                )),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary, letterSpacing: -0.3,
                )),
            if (subLabel != null) ...[
              const SizedBox(height: 1),
              Text(subLabel!,
                  style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

class _QuickActions extends ConsumerWidget {
  final ShiftEntity? shift;
  const _QuickActions({required this.shift});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shiftOpen = shift != null && shift!.isOpen;

    return Row(children: [
      Expanded(child: _ActionButton(
        key: const Key('quick_new_order'),
        icon: Icons.add_shopping_cart_outlined,
        label: l10n.quickActionNewOrder,
        color: AppColors.green,
        onTap: () => context.go(AppRoutes.orderCenter),
      )),
      const SizedBox(width: 10),
      Expanded(child: _ActionButton(
        key: const Key('quick_floor_plan'),
        icon: Icons.grid_view_outlined,
        label: l10n.quickActionFloorPlan,
        color: AppColors.primary,
        onTap: () => context.go(AppRoutes.orderCenter),
      )),
      const SizedBox(width: 10),
      Expanded(child: _ActionButton(
        key: const Key('quick_shift'),
        icon: shiftOpen ? Icons.lock_clock_outlined : Icons.play_circle_outline,
        label: shiftOpen ? l10n.quickActionCloseShift : l10n.quickActionOpenShift,
        color: shiftOpen ? AppColors.orange : AppColors.green,
        onTap: () => context.go(shiftOpen ? AppRoutes.shiftClose : AppRoutes.shiftOpen),
      )),
      const SizedBox(width: 10),
      Expanded(child: _ActionButton(
        key: const Key('quick_history'),
        icon: Icons.history_outlined,
        label: l10n.quickActionOrderHistory,
        color: AppColors.yellow,
        onTap: () => context.go(AppRoutes.orderHistory),
      )),
    ]);
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _pressed
                ? widget.color.withValues(alpha: 0.18)
                : widget.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.color.withValues(alpha: 0.25)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.icon, color: widget.color, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(widget.label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: widget.color,
                  )),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hourly sales bar chart (fl_chart)
// ---------------------------------------------------------------------------

class _HourlySalesChart extends StatelessWidget {
  final DashboardSummaryEntity summary;
  const _HourlySalesChart({required this.summary});

  @override
  Widget build(BuildContext context) {
    final peak = summary.peakHourlyRevenueCents;
    final maxY = peak > 0 ? (peak / 100 * 1.15).ceilToDouble() : 100.0;

    // Business hours 6–23
    final hours = summary.hourlySales.where((h) => h.hour >= 6).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Builder(builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Row(children: [
            const Icon(Icons.bar_chart_outlined, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(l10n.dashboardHourlySales.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary, letterSpacing: 0.8,
                )),
            const Spacer(),
            const Text('Today · CHF',
                style: TextStyle(fontSize: 9, color: AppColors.textDim)),
          ]);
        }),
        const SizedBox(height: 10),
        Expanded(
          child: peak == 0
              ? Center(
                  child: Builder(builder: (context) => Text(
                      AppLocalizations.of(context).statusNoData,
                      style: const TextStyle(color: AppColors.textDim, fontSize: 11))))
              : BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY,
                    minY: 0,
                    barGroups: hours.map((h) {
                      return BarChartGroupData(
                        x: h.hour,
                        barRods: [
                          BarChartRodData(
                            toY: h.amountCents / 100,
                            color: h.amountCents > 0
                                ? AppColors.primary
                                : AppColors.surfaceContainerHigh,
                            width: 9,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ],
                      );
                    }).toList(),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 38,
                          getTitlesWidget: (v, meta) {
                            if (v == meta.min || v == meta.max) {
                              return const SizedBox();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                v >= 1000
                                    ? '${(v / 1000).toStringAsFixed(1)}k'
                                    : v.toInt().toString(),
                                style: const TextStyle(
                                    fontSize: 8, color: AppColors.textDim),
                                textAlign: TextAlign.right,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 16,
                          getTitlesWidget: (v, _) {
                            final h = v.toInt();
                            if (h % 3 != 0) return const SizedBox();
                            return Text('${h.toString().padLeft(2, '0')}h',
                                style: const TextStyle(
                                    fontSize: 8, color: AppColors.textDim));
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: math.max(maxY / 4, 1),
                      getDrawingHorizontalLine: (_) => const FlLine(
                          color: AppColors.surfaceContainerHigh, strokeWidth: 1),
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => AppColors.surfaceContainer,
                        tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        getTooltipItem: (group, _, rod, __) {
                          return BarTooltipItem(
                            _formatChf((rod.toY * 100).round()),
                            const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  duration: const Duration(milliseconds: 400),
                ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment breakdown (horizontal progress bars, 3 methods)
// ---------------------------------------------------------------------------

class _PaymentBreakdownCard extends StatelessWidget {
  final DashboardSummaryEntity summary;
  const _PaymentBreakdownCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final total = summary.totalPaymentsCents;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Builder(builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Row(children: [
            const Icon(Icons.pie_chart_outline, size: 14, color: AppColors.orange),
            const SizedBox(width: 6),
            Text(l10n.settingsPayment.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary, letterSpacing: 0.8,
                )),
          ]);
        }),
        const SizedBox(height: 12),
        if (total == 0)
          Expanded(
            child: Center(
              child: Builder(builder: (context) => Text(
                  AppLocalizations.of(context).statusNoData,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 11))),
            ),
          )
        else
          Builder(builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _PaymentBar(
                    label: l10n.posCash,
                    icon: Icons.attach_money_outlined,
                    color: AppColors.green,
                    amountCents: summary.cashRevenueCents,
                    totalCents: total,
                  ),
                  _PaymentBar(
                    label: l10n.posCard,
                    icon: Icons.credit_card_outlined,
                    color: AppColors.primary,
                    amountCents: summary.cardRevenueCents,
                    totalCents: total,
                  ),
                  _PaymentBar(
                    label: '${l10n.posTwint} / Other',
                    icon: Icons.qr_code_outlined,
                    color: AppColors.purple,
                    amountCents: summary.otherRevenueCents,
                    totalCents: total,
                  ),
                ],
              ),
            );
          }),
      ]),
    );
  }
}

class _PaymentBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int amountCents;
  final int totalCents;

  const _PaymentBar({
    required this.label,
    required this.icon,
    required this.color,
    required this.amountCents,
    required this.totalCents,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = totalCents > 0 ? amountCents / totalCents : 0.0;
    final pct = (fraction * 100).round();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const Spacer(),
        Text(_formatChf(amountCents),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(width: 5),
        SizedBox(
          width: 28,
          child: Text('$pct%',
              style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
              textAlign: TextAlign.right),
        ),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          minHeight: 5,
          backgroundColor: AppColors.surfaceContainerHigh,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Recent orders list (last 10)
// ---------------------------------------------------------------------------

class _RecentOrdersList extends StatelessWidget {
  final List<RecentOrderRow> orders;
  const _RecentOrdersList({required this.orders});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Builder(builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              const Icon(Icons.history_outlined, size: 14, color: AppColors.yellow),
              const SizedBox(width: 6),
              Text(l10n.dashboardRecentOrders.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary, letterSpacing: 0.8,
                  )),
              const Spacer(),
              Text('Last ${math.min(orders.length, 10)}',
                  style: const TextStyle(fontSize: 9, color: AppColors.textDim)),
            ]),
          );
        }),
        const Divider(height: 1, color: AppColors.surfaceContainerHigh),
        if (orders.isEmpty)
          Expanded(
            child: Center(
              child: Builder(builder: (context) => Text(
                AppLocalizations.of(context).statusNoData,
                style: const TextStyle(color: AppColors.textDim, fontSize: 11))),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(
                  height: 1, color: AppColors.surfaceContainer, indent: 14),
              itemBuilder: (_, i) => _OrderRow(order: orders[i]),
            ),
          ),
      ]),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final RecentOrderRow order;
  const _OrderRow({required this.order});

  static const _statusColors = <String, Color>{
    'completed': AppColors.green,
    'open': AppColors.primary,
    'sent': AppColors.orange,
    'in_progress': AppColors.orange,
    'ready': AppColors.yellow,
    'bill_requested': AppColors.yellow,
    'cancelled': AppColors.red,
    'voided': AppColors.red,
    'draft': AppColors.textSecondary,
  };

  static const _statusLabels = <String, String>{
    'completed': 'Paid',
    'open': 'Open',
    'sent': 'Sent',
    'in_progress': 'In Kitchen',
    'ready': 'Ready',
    'bill_requested': 'Bill Req.',
    'cancelled': 'Cancelled',
    'voided': 'Voided',
    'draft': 'Draft',
  };

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[order.status] ?? AppColors.textSecondary;
    final statusLabel = _statusLabels[order.status] ?? order.status;
    final timeStr = DateFormat('HH:mm').format(order.openedAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(children: [
        Container(
            width: 6, height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 8),
        Text('#${order.orderNumber}',
            style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
            )),
        const SizedBox(width: 6),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_orderTypeLabel(order.orderType),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
          ),
        ),
        const Spacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 72),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(statusLabel,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 68,
          child: Text(_formatChf(order.totalCents),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.right),
        ),
        const SizedBox(width: 6),
        Text(timeStr,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ]),
    );
  }

  static String _orderTypeLabel(String t) => switch (t) {
        'dine_in' => 'Dine In',
        'takeaway' => 'Takeaway',
        'delivery' => 'Delivery',
        'online' => 'Online',
        _ => t,
      };
}

// ---------------------------------------------------------------------------
// Shift info card
// ---------------------------------------------------------------------------

class _ShiftInfoCard extends StatelessWidget {
  final ShiftEntity? shift;
  const _ShiftInfoCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    final open = shift != null && shift!.isOpen;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.schedule_outlined, size: 14, color: AppColors.orange),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('ACTIVE SHIFT',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary, letterSpacing: 0.8,
                )),
          ),
          const SizedBox(width: 4),
          Builder(builder: (context) {
            final l10n = AppLocalizations.of(context);
            final label = open
                ? l10n.shiftStatusOpen.toUpperCase()
                : l10n.shiftNoActiveShift.toUpperCase();
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: open
                      ? AppColors.green.withValues(alpha: 0.12)
                      : AppColors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    color: open ? AppColors.green : AppColors.red, letterSpacing: 0.5,
                  ),
                ),
              ),
            );
          }),
        ]),
        const SizedBox(height: 10),
        if (!open)
          Expanded(
            child: Center(
              child: Builder(builder: (context) {
                final l10n = AppLocalizations.of(context);
                return Text(
                  l10n.shiftNoActiveShift,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim, height: 1.6),
                );
              }),
            ),
          )
        else
          Builder(builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ShiftRow(l10n.receiptDate, DateFormat('HH:mm').format(shift!.openedAt)),
                  _ShiftRow(l10n.navShift, _duration(shift!.openedAt)),
                  _ShiftRow(l10n.dashboardOrders, shift!.totalOrders.toString()),
                  _ShiftRow(l10n.posTotal, _formatChf(shift!.totalSales)),
                  _ShiftRow(l10n.shiftOpeningFloat, _formatChf(shift!.openingCash)),
                ],
              ),
            );
          }),
      ]),
    );
  }

  static String _duration(DateTime openedAt) {
    final d = DateTime.now().difference(openedAt);
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    return '${h}h ${m}m';
  }
}

class _ShiftRow extends StatelessWidget {
  final String label;
  final String value;
  const _ShiftRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Flexible(
        child: Text(label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ),
      const SizedBox(width: 8),
      Text(value,
          style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
          )),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Hardware status row
// ---------------------------------------------------------------------------

class _HardwareStatusRow extends StatelessWidget {
  final HardwareStatus hardware;
  const _HardwareStatusRow({required this.hardware});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Builder(builder: (context) {
        final l10n = AppLocalizations.of(context);
        return Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _HardwareChip(
            icon: Icons.print_outlined,
            label: l10n.settingsPrinter,
            connected: hardware.printerConnected,
          ),
          _HardwareChip(
            icon: Icons.point_of_sale_outlined,
            label: l10n.settingsPayment,
            connected: hardware.terminalConnected,
          ),
        ]);
      }),
    );
  }
}

class _HardwareChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool connected;
  const _HardwareChip({required this.icon, required this.label, required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppColors.green : AppColors.textDim;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      const SizedBox(width: 5),
      Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? AppColors.green : AppColors.red.withValues(alpha: 0.6),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

class _Footer extends StatelessWidget {
  final VoidCallback onSignOut;
  const _Footer({required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      child: Row(children: [
        const Text('GastroCore ',
            style: TextStyle(fontSize: 12, color: AppColors.textDim)),
        const Text('v0.1.0',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const Spacer(),
        GestureDetector(
          key: const Key('sign_out_btn'),
          onTap: onSignOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.logout, size: 15, color: AppColors.textPrimary),
              SizedBox(width: 7),
              Text('Sign Out',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  )),
            ]),
          ),
        ),
      ]),
    );
  }
}
