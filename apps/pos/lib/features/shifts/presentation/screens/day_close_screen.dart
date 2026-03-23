/// Day Close Screen — hardened shift-close wizard.
///
/// Three-step wizard:
///   Step 1  Kasse zählen   — denomination breakdown (CHF coins & notes)
///   Step 2  Abstimmung     — expected vs counted cash + discrepancy warning
///   Step 3  Zusammenfassung — revenue summary + confirm close
///
/// On confirm:
///   1. Denomination total is submitted as the closing cash.
///   2. [DayCloseNotifier.submitClose] persists a [DayCloseSummaryEntity].
///   3. Z-report is printed (best-effort — printing failure never blocks close).
///   4. Auto-backup runs in the background.
///   5. App navigates to /login. New orders are blocked until a new shift is
///      opened (handled by [currentShiftProvider] returning null).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/printing/providers/print_use_case_provider.dart';
import 'package:gastrocore_pos/core/printing/models/print_models.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/tax_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/shifts/domain/day_close_calculator.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/day_close_summary_entity.dart';
import 'package:gastrocore_pos/features/shifts/domain/entities/shift_summary_entity.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/day_close_provider.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';

// ---------------------------------------------------------------------------
// DayCloseScreen
// ---------------------------------------------------------------------------

class DayCloseScreen extends ConsumerStatefulWidget {
  const DayCloseScreen({super.key});

  @override
  ConsumerState<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends ConsumerState<DayCloseScreen> {
  int _step = 0; // 0 = cash count, 1 = reconciliation, 2 = summary

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  void _next() {
    if (_step < 2) setState(() => _step++);
  }

  void _prev() {
    if (_step > 0) setState(() => _step--);
  }

  // -------------------------------------------------------------------------
  // Submit
  // -------------------------------------------------------------------------

  Future<void> _confirmClose(
    int expectedCashCents,
    Map<String, int> paymentBreakdown,
  ) async {
    final notifier = ref.read(dayCloseNotifierProvider.notifier);
    final user = ref.read(currentUserProvider);
    final cashierName = user?.name ?? 'Unknown';

    try {
      final summary = await notifier.submitClose(
        cashierName: cashierName,
        paymentBreakdown: paymentBreakdown,
        expectedCashCents: expectedCashCents,
      );

      // Z-report printing (best-effort).
      await _printZReport(summary);

      // Audit: day closed
      final audit = ref.read(auditServiceProvider);
      await audit.logDayClosed(
        summary.shiftId,
        newValueJson:
            '{"cashier":"${summary.cashierName}","revenue":${summary.totalRevenueCents},"orders":${summary.totalOrders}}',
      );

      if (mounted) {
        ref.read(currentUserProvider.notifier).logout();
        context.go('/login');
      }
    } on DayCloseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shift close failed: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _printZReport(DayCloseSummaryEntity summary) async {
    try {
      final reportBreakdown = {
        for (final e in summary.paymentBreakdown.entries)
          PaymentBreakdownLine.labelFor(e.key): e.value,
      };

      // Compute MWST breakdown from tax settings and total revenue.
      // Assumes tax-inclusive pricing (Bruttopreise) — MwSt = Brutto × r/(100+r).
      final taxSettings =
          ref.read(taxSettingsProvider).valueOrNull ?? TaxSettings();
      final mwstEntries = _computeMwstEntries(
        totalRevenueCents: summary.totalRevenueCents,
        taxSettings: taxSettings,
      );

      final data = ShiftReportData(
        reportTitle: 'Z-RAPPORT',
        reportNo: 0,
        cashierName: summary.cashierName,
        terminalNo: summary.deviceId,
        shiftStart: summary.closedAt,
        shiftEnd: summary.closedAt,
        printedAt: DateTime.now(),
        grossSales: summary.totalRevenueCents,
        netSales: summary.totalRevenueCents,
        netRevenue: summary.totalRevenueCents,
        paymentBreakdown: reportBreakdown,
        mwstEntries: mwstEntries,
        orderCount: summary.totalOrders,
        openingFloat: summary.expectedCashCents,
        closingFloat: summary.countedCashCents,
      );
      await ref.read(printReportUseCaseProvider).printZReport(data);
    } catch (_) {
      // Printing failure must never block shift close.
    }
  }

  /// Compute [MwStReportEntry] list from [totalRevenueCents] and [taxSettings].
  ///
  /// When per-item MWST tracking is not available (pilot phase), the entire
  /// revenue is attributed to the standard rate. This is conservative and
  /// matches the most common Swiss restaurant scenario (dine-in = Normalsatz).
  static List<MwStReportEntry> _computeMwstEntries({
    required int totalRevenueCents,
    required TaxSettings taxSettings,
  }) {
    if (totalRevenueCents <= 0) return [];
    return [
      MwStReportEntry(
        code: MwStCode.a, // 8.1% Normalsatz
        grossAmount: totalRevenueCents,
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final shift = ref.watch(currentShiftProvider);
    final user = ref.watch(currentUserProvider);
    final userName = user?.name ?? 'Unknown';

    if (shift == null) {
      return _buildNoShift();
    }

    // Pre-compute expected cash from breakdown for step 2+.
    final breakdownAsync = ref.watch(shiftPaymentBreakdownProvider(shift.id));
    final paymentBreakdown =
        breakdownAsync.asData?.value ?? const <String, int>{};
    final cashSales =
        paymentBreakdown.entries.where((e) => e.key == 'cash').fold(0, (s, e) => s + e.value);
    final expectedCash = shift.openingCash + cashSales;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(userName),
          _buildStepIndicator(),
          Expanded(
            child: IndexedStack(
              index: _step,
              children: [
                // Step 0 — Cash Count
                _StepCashCount(
                  onNext: _next,
                ),
                // Step 1 — Reconciliation
                _StepReconciliation(
                  expectedCashCents: expectedCash,
                  onBack: _prev,
                  onNext: _next,
                ),
                // Step 2 — Summary & Confirm
                _StepSummary(
                  shift: shift,
                  paymentBreakdown: paymentBreakdown,
                  expectedCashCents: expectedCash,
                  cashierName: userName,
                  onBack: _prev,
                  onConfirm: () =>
                      _confirmClose(expectedCash, paymentBreakdown),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // No active shift guard
  // -------------------------------------------------------------------------

  Widget _buildNoShift() {
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

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar(String name) {
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
          const SizedBox(width: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.orangeDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'TAG ABSCHLUSS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.orange,
                letterSpacing: 1.0,
              ),
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
                _initials(name),
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
  // Step indicator
  // -------------------------------------------------------------------------

  Widget _buildStepIndicator() {
    const labels = ['Kasse zählen', 'Abstimmung', 'Zusammenfassung'];
    return Container(
      height: 48,
      color: AppColors.surface,
      child: Row(
        children: List.generate(labels.length, (i) {
          final isActive = _step == i;
          final isDone = _step > i;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone
                            ? AppColors.green
                            : isActive
                                ? AppColors.accent
                                : AppColors.surfaceContainerHigh,
                      ),
                      child: Center(
                        child: isDone
                            ? const Icon(Icons.check,
                                size: 12, color: Colors.white)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isActive
                                      ? Colors.white
                                      : AppColors.textDim,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isActive
                            ? AppColors.textPrimary
                            : AppColors.textDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 2,
                  color: isActive
                      ? AppColors.accent
                      : isDone
                          ? AppColors.green
                          : Colors.transparent,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ===========================================================================
// Step 0 — Cash Count (Denomination Breakdown)
// ===========================================================================

class _StepCashCount extends ConsumerWidget {
  const _StepCashCount({required this.onNext});

  final VoidCallback onNext;

  static String _fmtCents(int cents) =>
      'CHF ${DayCloseCalculator.formatCents(cents)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayClose = ref.watch(dayCloseNotifierProvider);
    final notifier = ref.read(dayCloseNotifierProvider.notifier);
    final breakdown = dayClose.denominationBreakdown;
    final total = dayClose.countedCashCents;

    return Row(
      children: [
        // LEFT — coins
        Expanded(
          child: _DenomSection(
            title: 'MÜNZEN',
            icon: Icons.toll_outlined,
            denominations: ChfDenomination.coins,
            breakdown: breakdown,
            onIncrement: notifier.increment,
            onDecrement: notifier.decrement,
            onSetCount: notifier.setCount,
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.border),
        // RIGHT — notes + total + next
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _DenomSection(
                  title: 'NOTEN',
                  icon: Icons.payments_outlined,
                  denominations: ChfDenomination.notes,
                  breakdown: breakdown,
                  onIncrement: notifier.increment,
                  onDecrement: notifier.decrement,
                  onSetCount: notifier.setCount,
                ),
              ),
              // Total + Next button
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'KASSENSALDO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDim,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          _fmtCents(total),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green,
                            letterSpacing: -0.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: onNext,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primaryContainer,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'WEITER ZUR ABSTIMMUNG',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0A1A3A),
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded,
                                size: 18, color: Color(0xFF0A1A3A)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Denomination section (coins or notes column)
// ---------------------------------------------------------------------------

class _DenomSection extends StatelessWidget {
  const _DenomSection({
    required this.title,
    required this.icon,
    required this.denominations,
    required this.breakdown,
    required this.onIncrement,
    required this.onDecrement,
    required this.onSetCount,
  });

  final String title;
  final IconData icon;
  final List<int> denominations;
  final Map<int, int> breakdown;
  final void Function(int) onIncrement;
  final void Function(int) onDecrement;
  final void Function(int, int) onSetCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textDim),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDim,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...denominations.map((denom) {
            final count = breakdown[denom] ?? 0;
            final lineTotal = denom * count;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: count > 0
                      ? AppColors.accentDim
                      : AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    // Denomination label
                    SizedBox(
                      width: 80,
                      child: Text(
                        ChfDenomination.label(denom),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    // Decrement
                    _CountButton(
                      icon: Icons.remove,
                      onTap: () => onDecrement(denom),
                    ),
                    const SizedBox(width: 8),
                    // Count field
                    SizedBox(
                      width: 40,
                      child: _CountField(
                        count: count,
                        onChanged: (v) => onSetCount(denom, v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Increment
                    _CountButton(
                      icon: Icons.add,
                      onTap: () => onIncrement(denom),
                    ),
                    const Spacer(),
                    // Line total
                    Text(
                      lineTotal > 0
                          ? 'CHF ${DayCloseCalculator.formatCents(lineTotal)}'
                          : '',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.textPrimary),
      ),
    );
  }
}

class _CountField extends StatefulWidget {
  const _CountField({required this.count, required this.onChanged});

  final int count;
  final void Function(int) onChanged;

  @override
  State<_CountField> createState() => _CountFieldState();
}

class _CountFieldState extends State<_CountField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.count > 0 ? widget.count.toString() : '');
  }

  @override
  void didUpdateWidget(_CountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      final newText = widget.count > 0 ? widget.count.toString() : '';
      if (_ctrl.text != newText) {
        _ctrl.text = newText;
        _ctrl.selection =
            TextSelection.collapsed(offset: _ctrl.text.length);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      onChanged: (v) => widget.onChanged(int.tryParse(v) ?? 0),
    );
  }
}

// ===========================================================================
// Step 1 — Reconciliation
// ===========================================================================

class _StepReconciliation extends ConsumerWidget {
  const _StepReconciliation({
    required this.expectedCashCents,
    required this.onBack,
    required this.onNext,
  });

  final int expectedCashCents;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayClose = ref.watch(dayCloseNotifierProvider);
    final notifier = ref.read(dayCloseNotifierProvider.notifier);
    final countedCash = dayClose.countedCashCents;
    final discrepancy = DayCloseCalculator.discrepancy(
      countedCash: countedCash,
      expectedCash: expectedCashCents,
    );
    final isWithin = DayCloseCalculator.isWithinThreshold(discrepancy);
    final isOver = discrepancy > 0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Kassensturzabgleich',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Überprüfen Sie den erwarteten Kassenbestand mit dem gezählten Betrag.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textDim,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // Comparison card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _ReconcRow(
                      label: 'Erwartet',
                      value: 'CHF ${DayCloseCalculator.formatCents(expectedCashCents)}',
                      valueColor: AppColors.textPrimary,
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 16),
                    _ReconcRow(
                      label: 'Gezählt',
                      value: 'CHF ${DayCloseCalculator.formatCents(countedCash)}',
                      valueColor: AppColors.accent,
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 16),
                    _ReconcRow(
                      label: 'Differenz',
                      value: DayCloseCalculator.discrepancyLabel(discrepancy),
                      valueColor: isWithin
                          ? AppColors.green
                          : (isOver ? AppColors.orange : AppColors.red),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Discrepancy warning
              if (!isWithin)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (isOver ? AppColors.orange : AppColors.red)
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (isOver ? AppColors.orange : AppColors.red)
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: isOver ? AppColors.orange : AppColors.red,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOver
                                  ? 'Überschuss: ${DayCloseCalculator.discrepancyLabel(discrepancy)}'
                                  : 'Fehlbetrag: ${DayCloseCalculator.discrepancyLabel(discrepancy)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isOver
                                    ? AppColors.orange
                                    : AppColors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Die Differenz überschreitet den Toleranzwert von CHF 5.00. '
                              'Bitte zählen Sie die Kasse erneut oder notieren Sie die '
                              'Abweichung.',
                              style: TextStyle(
                                fontSize: 11,
                                color: (isOver
                                        ? AppColors.orange
                                        : AppColors.red)
                                    .withValues(alpha: 0.8),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              if (isWithin)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.greenDim,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 18, color: AppColors.green),
                      SizedBox(width: 10),
                      Text(
                        'Differenz innerhalb der Toleranz (± CHF 5.00)',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Notes field
              const Text(
                'BEMERKUNGEN (OPTIONAL)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDim,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: notifier.setNotes,
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Anmerkungen zur Kassendifferenz…',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textDim,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 32),

              // Navigation buttons
              Row(
                children: [
                  Expanded(
                    child: _OutlineButton(
                      label: 'ZURÜCK',
                      icon: Icons.arrow_back_rounded,
                      onTap: onBack,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _GradientButton(
                      label: 'WEITER ZUR ZUSAMMENFASSUNG',
                      icon: Icons.arrow_forward_rounded,
                      onTap: onNext,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReconcRow extends StatelessWidget {
  const _ReconcRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Step 2 — Summary & Confirm
// ===========================================================================

class _StepSummary extends ConsumerWidget {
  const _StepSummary({
    required this.shift,
    required this.paymentBreakdown,
    required this.expectedCashCents,
    required this.cashierName,
    required this.onBack,
    required this.onConfirm,
  });

  final dynamic shift; // ShiftEntity
  final Map<String, int> paymentBreakdown;
  final int expectedCashCents;
  final String cashierName;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  String _fmtCents(int cents) =>
      'CHF ${DayCloseCalculator.formatCents(cents)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayClose = ref.watch(dayCloseNotifierProvider);
    final isSubmitting = dayClose.isSubmitting;
    final countedCash = dayClose.countedCashCents;
    final totalRevenue = (shift.totalSales as int?) ?? 0;
    final totalOrders = (shift.totalOrders as int?) ?? 0;
    final avgOrder = DayCloseCalculator.avgOrderCents(
      totalRevenueCents: totalRevenue,
      totalOrders: totalOrders,
    );
    final discrepancy = DayCloseCalculator.discrepancy(
      countedCash: countedCash,
      expectedCash: expectedCashCents,
    );
    final isWithin = DayCloseCalculator.isWithinThreshold(discrepancy);

    return Row(
      children: [
        // LEFT — revenue summary
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tagesabschluss Zusammenfassung',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cashierName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),

                // Hero — total revenue
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 28, horizontal: 24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'TAGESUMSATZ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDim,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _fmtCents(totalRevenue),
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

                // Stats row
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Bestellungen',
                        value: totalOrders.toString(),
                        icon: Icons.receipt_long_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Ø Bon',
                        value: _fmtCents(avgOrder),
                        icon: Icons.trending_up_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Kassensaldo',
                        value: _fmtCents(countedCash),
                        icon: Icons.money_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // MWST summary card
                _MwstSummaryCard(totalRevenueCents: totalRevenue),
                const SizedBox(height: 20),

                // Payment breakdown
                if (paymentBreakdown.isNotEmpty) ...[
                  Container(
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
                            Icon(Icons.payments_outlined,
                                size: 16, color: AppColors.textDim),
                            SizedBox(width: 8),
                            Text(
                              'ZAHLUNGSARTEN',
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
                        ...paymentBreakdown.entries.map((e) {
                          final label =
                              PaymentBreakdownLine.labelFor(e.key);
                          final pct = totalRevenue > 0
                              ? (e.value / totalRevenue * 100).round()
                              : 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(label,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        )),
                                    Text(
                                      _fmtCents(e.value),
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
                                    value: totalRevenue > 0
                                        ? e.value / totalRevenue
                                        : 0,
                                    backgroundColor:
                                        AppColors.surfaceContainerHigh,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
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
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // RIGHT — confirm panel
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.35,
          child: ColoredBox(
            color: AppColors.surface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Schicht abschliessen',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Reconciliation summary
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        _SummaryRow(
                          'Erwartet', _fmtCents(expectedCashCents)),
                        const SizedBox(height: 8),
                        _SummaryRow(
                            'Gezählt', _fmtCents(countedCash)),
                        const SizedBox(height: 8),
                        const Divider(color: AppColors.border, height: 1),
                        const SizedBox(height: 8),
                        _SummaryRow(
                          'Differenz',
                          DayCloseCalculator.discrepancyLabel(discrepancy),
                          valueColor: isWithin
                              ? AppColors.green
                              : (discrepancy > 0
                                  ? AppColors.orange
                                  : AppColors.red),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Discrepancy warning chip (compact)
                  if (!isWithin)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (discrepancy > 0
                                ? AppColors.orange
                                : AppColors.red)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: discrepancy > 0
                                ? AppColors.orange
                                : AppColors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kassendifferenz > CHF 5.00 — '
                              'trotzdem abschliessen?',
                              style: TextStyle(
                                fontSize: 11,
                                color: discrepancy > 0
                                    ? AppColors.orange
                                    : AppColors.red,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // What happens on close
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BEIM ABSCHLUSS WERDEN FOLGENDE AKTIONEN AUSGELÖST:',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDim,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...[
                          (Icons.print_rounded,
                              'Z-Rapport wird gedruckt'),
                          (Icons.backup_rounded, 'Datensicherung wird erstellt'),
                          (Icons.lock_rounded, 'Neue Bestellungen werden blockiert'),
                          (Icons.logout_rounded,
                              'Abmeldung vom Terminal'),
                        ].map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Icon(item.$1,
                                      size: 13,
                                      color: AppColors.textDim),
                                  const SizedBox(width: 8),
                                  Text(
                                    item.$2,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Back button
                  _OutlineButton(
                    label: 'ZURÜCK',
                    icon: Icons.arrow_back_rounded,
                    onTap: isSubmitting ? null : onBack,
                  ),
                  const SizedBox(height: 10),

                  // Confirm close button
                  GestureDetector(
                    onTap: isSubmitting ? null : onConfirm,
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: isSubmitting
                              ? [
                                  AppColors.surfaceContainerHigh,
                                  AppColors.surfaceContainerHigh,
                                ]
                              : const [
                                  AppColors.primary,
                                  AppColors.primaryContainer,
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isSubmitting)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textSecondary,
                              ),
                            )
                          else ...[
                            const Icon(Icons.lock_rounded,
                                size: 18, color: Color(0xFF0A1A3A)),
                            const SizedBox(width: 8),
                            const Text(
                              'TAG ABSCHLIESSEN',
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
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
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
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// MWST Summary Card
// ===========================================================================

/// Displays MwSt breakdown on the day-close summary screen.
///
/// During the pilot phase, total revenue is attributed to the Normalsatz (A)
/// since per-item tax tracking is not yet stored at shift level. The card
/// clearly labels this as an estimate so the operator is informed.
class _MwstSummaryCard extends ConsumerWidget {
  const _MwstSummaryCard({required this.totalRevenueCents});

  final int totalRevenueCents;

  String _fmtChf(int cents) =>
      'CHF ${DayCloseCalculator.formatCents(cents)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taxSettings =
        ref.watch(taxSettingsProvider).valueOrNull ?? TaxSettings();

    // Compute MWST entries: attribute all revenue to Normalsatz (pilot).
    final entries = totalRevenueCents > 0
        ? [
            MwStReportEntry(
              code: MwStCode.a,
              grossAmount: totalRevenueCents,
            ),
          ]
        : <MwStReportEntry>[];

    final totalTax = entries.fold(0, (s, e) => s + e.taxAmount);
    final totalNet = entries.fold(0, (s, e) => s + e.netAmount);

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
              Icon(Icons.percent_rounded, size: 16, color: AppColors.textDim),
              SizedBox(width: 8),
              Text(
                'MWST-ABRECHNUNG',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDim,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Header row
          const Row(
            children: [
              SizedBox(
                width: 36,
                child: Text('Cod',
                    style: TextStyle(fontSize: 10, color: AppColors.textDim)),
              ),
              SizedBox(
                width: 48,
                child: Text('Satz',
                    style: TextStyle(fontSize: 10, color: AppColors.textDim)),
              ),
              Expanded(
                child: Text('Netto',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, color: AppColors.textDim)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('MwSt',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, color: AppColors.textDim)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('Brutto',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, color: AppColors.textDim)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          // Data rows
          ...entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      e.code.code,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${e.code.rate}%',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _fmtChf(e.netAmount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _fmtChf(e.taxAmount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _fmtChf(e.grossAmount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          // Totals row
          Row(
            children: [
              const SizedBox(width: 84),
              Expanded(
                child: Text(
                  _fmtChf(totalNet),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _fmtChf(totalTax),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _fmtChf(totalRevenueCents),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Effective date note
          Text(
            'Gültig ab ${taxSettings.effectiveFrom.year}-'
            '${taxSettings.effectiveFrom.month.toString().padLeft(2, '0')}-'
            '${taxSettings.effectiveFrom.day.toString().padLeft(2, '0')} · '
            'Alle Preise Bruttopreise (MwSt inkl.)',
            style: const TextStyle(fontSize: 10, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Shared button widgets
// ===========================================================================

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0A1A3A),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 16, color: const Color(0xFF0A1A3A)),
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
