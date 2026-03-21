/// Shift Close Screen for GastroCore POS.
///
/// Two-column layout:
/// - LEFT  – Shift summary: total sales hero, stats grid, payment breakdown
/// - RIGHT – Cash reconciliation: numpad, variance, cash drawer, close button
///
/// On close:
///  1. Calls [currentShiftProvider.closeShift]
///  2. Builds [ShiftReportData] and triggers Z-report print
///  3. Logs out the current user and navigates to /login
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/printing/providers/print_use_case_provider.dart';
import 'package:gastrocore_pos/core/printing/printing_provider.dart';
import 'package:gastrocore_pos/core/printing/models/print_models.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_entity.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_summary_entity.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';

// ---------------------------------------------------------------------------
// Shift Close Screen
// ---------------------------------------------------------------------------

class ShiftCloseScreen extends ConsumerStatefulWidget {
  const ShiftCloseScreen({super.key});

  @override
  ConsumerState<ShiftCloseScreen> createState() => _ShiftCloseScreenState();
}

class _ShiftCloseScreenState extends ConsumerState<ShiftCloseScreen> {
  String _countedCashStr = '';
  bool _isClosing = false;

  int get _countedCashCents {
    final val = int.tryParse(_countedCashStr) ?? 0;
    return val * 100; // Entered as whole CHF, stored as cents.
  }

  String _formatCents(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    final parts = <String>[];
    var s = whole.toString();
    for (var i = s.length; i > 0; i -= 3) {
      final start = i - 3 < 0 ? 0 : i - 3;
      parts.insert(0, s.substring(start, i));
    }
    return '${isNeg ? '-' : ''}${parts.join(',')}.$frac';
  }

  void _onDigit(String digit) {
    if (_countedCashStr.length >= 7) return;
    setState(() {
      if (_countedCashStr == '0') {
        _countedCashStr = digit;
      } else {
        _countedCashStr += digit;
      }
    });
  }

  void _onBackspace() {
    if (_countedCashStr.isEmpty) return;
    setState(() {
      _countedCashStr = _countedCashStr.length <= 1
          ? ''
          : _countedCashStr.substring(0, _countedCashStr.length - 1);
    });
  }

  void _onClear() => setState(() => _countedCashStr = '');

  void _onQuickDenomination(int amount) {
    setState(() {
      final current = int.tryParse(_countedCashStr) ?? 0;
      _countedCashStr = (current + amount).toString();
    });
  }

  Future<void> _onOpenCashDrawer() async {
    await ref.read(printerActionsProvider.notifier).openCashDrawer();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash drawer opened'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _onCloseShift(ShiftEntity shift) async {
    if (_isClosing) return;
    setState(() => _isClosing = true);

    try {
      // 1. Load payment breakdown before closing (while shift window is known).
      final breakdownMap = await ref
          .read(shiftRepositoryProvider)
          .getPaymentBreakdown(shift.id, shift.tenantId);

      // 2. Close the shift in the database.
      final closedShift = await ref
          .read(currentShiftProvider.notifier)
          .closeShift(closingCash: _countedCashCents);

      // 3. Trigger Z-report print if a printer is connected.
      if (closedShift != null) {
        await _printZReport(closedShift, breakdownMap);
      }

      // 4. Log out and navigate to login.
      if (mounted) {
        ref.read(currentUserProvider.notifier).logout();
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClosing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to close shift: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _printZReport(
      ShiftEntity shift, Map<String, int> rawBreakdown) async {
    try {
      final user = ref.read(currentUserProvider);
      // Map raw method keys to human-readable labels for the report.
      final reportBreakdown = {
        for (final e in rawBreakdown.entries)
          PaymentBreakdownLine.labelFor(e.key): e.value,
      };
      // Use shift count as report number (sequential approximation).
      final history =
          await ref.read(shiftRepositoryProvider).getShiftHistory(shift.tenantId);
      final reportNo = history.length;

      final data = ShiftReportData(
        reportTitle: 'Z-RAPPORT',
        reportNo: reportNo,
        cashierName: user?.name,
        terminalNo: shift.deviceId,
        shiftStart: shift.openedAt,
        shiftEnd: shift.closedAt ?? DateTime.now(),
        printedAt: DateTime.now(),
        grossSales: shift.totalSales,
        netSales: shift.totalSales,
        netRevenue: shift.totalSales,
        paymentBreakdown: reportBreakdown,
        orderCount: shift.totalOrders,
        openingFloat: shift.openingCash,
        closingFloat: shift.closingCash,
      );

      await ref.read(printReportUseCaseProvider).printZReport(data);
    } catch (_) {
      // Printing failure must not block shift close.
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final shift = ref.watch(currentShiftProvider);
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'Unknown';
    final userInitials = _initials(userName);

    if (shift == null) {
      return Scaffold(
        backgroundColor: AppColors.surfaceDim,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 48, color: AppColors.textDim),
              const SizedBox(height: 16),
              const Text(
                'No active shift',
                style: TextStyle(fontSize: 16, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => context.go('/login'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Go to Login',
                    style: TextStyle(
                      color: Color(0xFF0A1A3A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final totalSalesCents = shift.totalSales;
    final orderCount = shift.totalOrders;
    final openingCashCents = shift.openingCash;
    final expectedCashCents = openingCashCents + totalSalesCents;
    final varianceCents = _countedCashCents - expectedCashCents;

    // Load payment breakdown.
    final breakdownAsync = ref.watch(shiftPaymentBreakdownProvider(shift.id));

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(userInitials, userName),
          Expanded(
            child: Row(
              children: [
                // LEFT: Shift summary
                Expanded(
                  flex: 6,
                  child: _buildShiftSummary(
                    shift: shift,
                    totalSalesCents: totalSalesCents,
                    orderCount: orderCount,
                    openingCashCents: openingCashCents,
                    breakdownAsync: breakdownAsync,
                  ),
                ),
                // RIGHT: Reconciliation
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.38,
                  child: _buildReconciliation(
                    shift: shift,
                    expectedCashCents: expectedCashCents,
                    varianceCents: varianceCents,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar(String initials, String name) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surface,
      child: Row(
        children: [
          Row(
            children: [
              const Text(
                'Gastro',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryContainer],
                ).createShader(bounds),
                child: const Text(
                  'Core',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.greenDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'ONLINE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Shift summary (left column)
  // -------------------------------------------------------------------------

  Widget _buildShiftSummary({
    required ShiftEntity shift,
    required int totalSalesCents,
    required int orderCount,
    required int openingCashCents,
    required AsyncValue<Map<String, int>> breakdownAsync,
  }) {
    final avgOrderCents =
        orderCount > 0 ? (totalSalesCents / orderCount).round() : 0;

    final openedAt = shift.openedAt;
    final openTimeStr =
        '${openedAt.hour.toString().padLeft(2, '0')}:${openedAt.minute.toString().padLeft(2, '0')}';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateStr =
        '${openedAt.day} ${months[openedAt.month]} ${openedAt.year}';

    // Duration
    final dur = DateTime.now().difference(openedAt);
    final durH = dur.inHours;
    final durM = dur.inMinutes % 60;
    final durStr = durH > 0 ? '${durH}h ${durM}m' : '${durM}m';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shift Close Summary',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildInfoChip('$openTimeStr – Now  ($durStr)'),
              const SizedBox(width: 8),
              _buildInfoChip(dateStr),
              const SizedBox(width: 8),
              _buildInfoChip(shift.deviceId),
            ],
          ),
          const SizedBox(height: 28),

          // Total sales hero
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const Text(
                  'TOTAL SALES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDim,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'CHF ${_formatCents(totalSalesCents)}',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green,
                    letterSpacing: -1.0,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stats grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Order Count',
                  orderCount.toString(),
                  Icons.receipt_long_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Avg Order Value',
                  'CHF ${_formatCents(avgOrderCents)}',
                  Icons.trending_up_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Opening Cash',
                  'CHF ${_formatCents(openingCashCents)}',
                  Icons.money_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Payment breakdown
          _buildPaymentBreakdown(breakdownAsync),
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdown(AsyncValue<Map<String, int>> breakdownAsync) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments_outlined, size: 16, color: AppColors.textDim),
              SizedBox(width: 8),
              Text(
                'PAYMENT BREAKDOWN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDim,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          breakdownAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent),
              ),
            ),
            error: (_, __) => const Text(
              'Unable to load payment breakdown',
              style: TextStyle(fontSize: 12, color: AppColors.textDim),
            ),
            data: (breakdown) {
              if (breakdown.isEmpty) {
                return const Text(
                  'No payments recorded',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                );
              }
              final total =
                  breakdown.values.fold(0, (s, v) => s + v);
              return Column(
                children: [
                  ...breakdown.entries.map((e) {
                    final label = PaymentBreakdownLine.labelFor(e.key);
                    final pct = total > 0
                        ? (e.value / total * 100).round()
                        : 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                'CHF ${_formatCents(e.value)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: total > 0 ? e.value / total : 0,
                              backgroundColor:
                                  AppColors.surfaceContainerHigh,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                e.key == 'cash'
                                    ? AppColors.green
                                    : AppColors.accent,
                              ),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '$pct%',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textDim,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(color: AppColors.border, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'CHF ${_formatCents(total)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textDim),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Reconciliation (right column)
  // -------------------------------------------------------------------------

  Widget _buildReconciliation({
    required ShiftEntity shift,
    required int expectedCashCents,
    required int varianceCents,
  }) {
    return Container(
      color: AppColors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shift Reconciliation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Count the cash in your register and enter the total below.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textDim,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),

            // Cash amount label
            const Text(
              'CASH IN DRAWER',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textDim,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),

            // Cash amount display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'CHF',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _countedCashStr.isEmpty ? '0.00' : '$_countedCashStr.00',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                      letterSpacing: -0.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Quick denomination buttons
            Row(
              children: [200, 50, 20].map((amount) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: amount == 200 ? 0 : 4,
                      right: amount == 20 ? 0 : 4,
                    ),
                    child: GestureDetector(
                      onTap: () => _onQuickDenomination(amount),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '+CHF $amount',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            _buildNumpad(),
            const SizedBox(height: 20),

            // Variance display
            _buildVarianceDisplay(varianceCents),
            const SizedBox(height: 16),

            // Expected vs Counted comparison
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _buildComparisonRow(
                      'Expected', 'CHF ${_formatCents(expectedCashCents)}'),
                  const SizedBox(height: 8),
                  _buildComparisonRow(
                      'Counted', 'CHF ${_formatCents(_countedCashCents)}'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Cash drawer button
            GestureDetector(
              onTap: _onOpenCashDrawer,
              child: Container(
                width: double.infinity,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.point_of_sale,
                        size: 16, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Text(
                      'Open Cash Drawer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Print X-report button
            GestureDetector(
              onTap: () async {
                final s = ref.read(currentShiftProvider);
                if (s == null) return;
                final breakdownMap = await ref
                    .read(shiftRepositoryProvider)
                    .getPaymentBreakdown(s.id, s.tenantId);
                final user = ref.read(currentUserProvider);
                final reportBreakdown = {
                  for (final e in breakdownMap.entries)
                    PaymentBreakdownLine.labelFor(e.key): e.value,
                };
                final data = ShiftReportData(
                  reportTitle: 'X-RAPPORT',
                  reportNo: 0,
                  cashierName: user?.name,
                  terminalNo: s.deviceId,
                  shiftStart: s.openedAt,
                  printedAt: DateTime.now(),
                  grossSales: s.totalSales,
                  netSales: s.totalSales,
                  netRevenue: s.totalSales,
                  paymentBreakdown: reportBreakdown,
                  orderCount: s.totalOrders,
                  openingFloat: s.openingCash,
                );
                await ref
                    .read(printReportUseCaseProvider)
                    .printXReport(data);
              },
              child: Container(
                width: double.infinity,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.print_rounded,
                        size: 16, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Text(
                      'Print X-Report (Interim)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Close shift button
            GestureDetector(
              onTap: () {
                final shift = ref.read(currentShiftProvider);
                if (shift != null && !_isClosing) _onCloseShift(shift);
              },
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isClosing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF0A1A3A),
                        ),
                      )
                    else ...[
                      const Icon(Icons.lock_rounded,
                          size: 18, color: Color(0xFF0A1A3A)),
                      const SizedBox(width: 8),
                      const Text(
                        'CLOSE SHIFT & PRINT Z-REPORT',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0A1A3A),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVarianceDisplay(int varianceCents) {
    final hasInput = _countedCashStr.isNotEmpty;
    final isPerfect = hasInput && varianceCents == 0;
    final isShort = hasInput && varianceCents < 0;

    final String label;
    final Color color;
    final IconData icon;

    if (!hasInput) {
      label = 'Enter counted cash';
      color = AppColors.textDim;
      icon = Icons.info_outline_rounded;
    } else if (isPerfect) {
      label = 'Perfect Match';
      color = AppColors.green;
      icon = Icons.check_circle_rounded;
    } else if (isShort) {
      label = 'Short CHF ${_formatCents(varianceCents.abs())}';
      color = AppColors.red;
      icon = Icons.warning_rounded;
    } else {
      label = 'Over CHF ${_formatCents(varianceCents)}';
      color = AppColors.orange;
      icon = Icons.arrow_upward_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasInput
            ? color.withValues(alpha: 0.08)
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        _buildNumRow(['1', '2', '3']),
        const SizedBox(height: 8),
        _buildNumRow(['4', '5', '6']),
        const SizedBox(height: 8),
        _buildNumRow(['7', '8', '9']),
        const SizedBox(height: 8),
        _buildNumRow(['C', '0', '\u232B']),
      ],
    );
  }

  Widget _buildNumRow(List<String> keys) {
    return Row(
      children: keys.map((key) {
        final idx = keys.indexOf(key);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: idx == 0 ? 0 : 4,
              right: idx == keys.length - 1 ? 0 : 4,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (key == 'C') {
                    _onClear();
                  } else if (key == '\u232B') {
                    _onBackspace();
                  } else {
                    _onDigit(key);
                  }
                },
                borderRadius: BorderRadius.circular(10),
                splashColor: AppColors.accent.withValues(alpha: 0.12),
                child: Ink(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: key == '\u232B'
                        ? const Icon(Icons.backspace_outlined,
                            size: 16, color: AppColors.textSecondary)
                        : Text(
                            key,
                            style: TextStyle(
                              fontSize: key == 'C' ? 12 : 20,
                              fontWeight: FontWeight.w600,
                              color: key == 'C'
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
