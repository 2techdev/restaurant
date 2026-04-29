/// Shift Opening Screen — Kinetic Grid redesign.
///
/// Two-column layout: left operator/date context card, right numpad with
/// quick-amount chips and primary gradient CTA. Light palette, zero-radius,
/// Swiss franc (CHF), Turkish copy only. Preserves widget keys used by the
/// integration test harness (`shift_open_screen`, `shift_start_btn`,
/// `quick_amount_200/500/1000`).
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';

// ---------------------------------------------------------------------------
// Shift Open Screen
// ---------------------------------------------------------------------------

class ShiftOpenScreen extends ConsumerStatefulWidget {
  const ShiftOpenScreen({super.key});

  @override
  ConsumerState<ShiftOpenScreen> createState() => _ShiftOpenScreenState();
}

class _ShiftOpenScreenState extends ConsumerState<ShiftOpenScreen> {
  String _amountStr = '500';
  bool _isOpening = false;
  int _selectedQuickAmount = 500;

  void _onDigit(String digit) {
    setState(() {
      if (_amountStr == '0') {
        _amountStr = digit;
      } else if (_amountStr.length < 8) {
        _amountStr += digit;
      }
      _selectedQuickAmount = -1;
    });
  }

  void _onDoubleZero() {
    setState(() {
      if (_amountStr != '0' && _amountStr.length < 7) {
        _amountStr += '00';
      }
      _selectedQuickAmount = -1;
    });
  }

  void _onBackspace() {
    setState(() {
      if (_amountStr.length <= 1) {
        _amountStr = '0';
      } else {
        _amountStr = _amountStr.substring(0, _amountStr.length - 1);
      }
      _selectedQuickAmount = -1;
    });
  }

  void _onQuickAmount(int amount) {
    setState(() {
      _amountStr = amount.toString();
      _selectedQuickAmount = amount;
    });
  }

  String _formatDisplayAmount() {
    final val = int.tryParse(_amountStr) ?? 0;
    final whole = val.toString();
    final parts = <String>[];
    for (var i = whole.length; i > 0; i -= 3) {
      final start = i - 3 < 0 ? 0 : i - 3;
      parts.insert(0, whole.substring(start, i));
    }
    return "${parts.join("'")}.00";
  }

  Future<void> _onStartShift() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);

    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    final openingCash = (int.tryParse(_amountStr) ?? 0) * 100;

    try {
      final shift = await ref.read(currentShiftProvider.notifier).openShift(
            userId: user.id,
            openingCash: openingCash,
          );

      final audit = ref.read(auditServiceProvider);
      audit.setUser(userId: user.id, userName: user.name);
      await audit.logDayOpened(shift.id, cashierName: user.name);

      if (mounted) context.go(AppRoutes.orderCenter);
    } catch (e) {
      if (mounted) {
        setState(() => _isOpening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vardiya açılamadı: $e'),
            backgroundColor: GcColors.error,
          ),
        );
      }
    }
  }

  String _roleLabel(UserRole role) => switch (role) {
        UserRole.admin => 'YÖNETİCİ',
        UserRole.manager => 'MÜDÜR',
        UserRole.waiter => 'GARSON',
        UserRole.cashier => 'KASİYER',
        UserRole.kitchen => 'MUTFAK',
      };

  String _formatDate(DateTime dt) {
    const months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    const days = [
      'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe',
      'Cuma', 'Cumartesi', 'Pazar',
    ];
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final now = DateTime.now();

    return Scaffold(
      key: const Key('shift_open_screen'),
      backgroundColor: GcColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 880;
            final left = _ContextPanel(
              user: user,
              roleLabel: user != null ? _roleLabel(user.role) : 'YÖNETİCİ',
              dateLine: _formatDate(now),
              timeLine: _formatTime(now),
            );
            final right = _AmountPanel(
              amountFormatted: _formatDisplayAmount(),
              isOpening: _isOpening,
              selectedQuickAmount: _selectedQuickAmount,
              onDigit: _onDigit,
              onDoubleZero: _onDoubleZero,
              onBackspace: _onBackspace,
              onQuickAmount: _onQuickAmount,
              onStart: _onStartShift,
              onBackToLogin: () => context.go(AppRoutes.login),
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 4, child: left),
                  Container(width: 1, color: GcColors.ghostBorder),
                  Expanded(flex: 5, child: right),
                ],
              );
            }

            return SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    height: 260,
                    child: left,
                  ),
                  Container(height: 1, color: GcColors.ghostBorder),
                  right,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left: operator + date context
// ---------------------------------------------------------------------------

class _ContextPanel extends StatelessWidget {
  const _ContextPanel({
    required this.user,
    required this.roleLabel,
    required this.dateLine,
    required this.timeLine,
  });

  final UserEntity? user;
  final String roleLabel;
  final String dateLine;
  final String timeLine;

  @override
  Widget build(BuildContext context) {
    final name = user?.name ?? 'Operatör';
    return Container(
      color: GcColors.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('VARDIYA BAŞLAT',
              style: TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
                color: GcColors.primary,
              )),
          const SizedBox(height: 12),
          Text('Günaydın,',
              style: GcText.body.copyWith(
                color: GcColors.onSurfaceVariant,
                fontSize: 16,
              )),
          const SizedBox(height: 4),
          Text(
            name,
            style: GcText.displayBlack.copyWith(fontSize: 32),
          ),
          const SizedBox(height: 24),
          _InfoRow(
            icon: Icons.badge_outlined,
            label: 'ROL',
            value: roleLabel,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: 'TARİH',
            value: dateLine,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.schedule_outlined,
            label: 'SAAT',
            value: timeLine,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            color: GcColors.surfaceContainer,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: GcColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kasadaki açılış bakiyesini girin. Bu tutar, gün sonu raporunda beklenen nakit ile karşılaştırılır.',
                    style: GcText.bodySmall.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: GcColors.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GcText.labelTiny),
              const SizedBox(height: 2),
              Text(value, style: GcText.body),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Right: amount entry + CTA
// ---------------------------------------------------------------------------

class _AmountPanel extends StatelessWidget {
  const _AmountPanel({
    required this.amountFormatted,
    required this.isOpening,
    required this.selectedQuickAmount,
    required this.onDigit,
    required this.onDoubleZero,
    required this.onBackspace,
    required this.onQuickAmount,
    required this.onStart,
    required this.onBackToLogin,
  });

  final String amountFormatted;
  final bool isOpening;
  final int selectedQuickAmount;
  final ValueChanged<String> onDigit;
  final VoidCallback onDoubleZero;
  final VoidCallback onBackspace;
  final ValueChanged<int> onQuickAmount;
  final VoidCallback onStart;
  final VoidCallback onBackToLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('AÇILIŞ KASASI', style: GcText.labelTiny),
          const SizedBox(height: 12),
          // Amount display
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            color: GcColors.surfaceContainerLowest,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('CHF',
                    style: GcText.labelTiny.copyWith(
                      color: GcColors.primary,
                      fontSize: 14,
                      letterSpacing: 1.4,
                    )),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    amountFormatted,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: GcText.displayBlack.copyWith(
                      fontSize: 44,
                      letterSpacing: -1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Quick chips
          Row(
            children: [
              _QuickChip(
                amount: 200,
                isSelected: selectedQuickAmount == 200,
                onTap: () => onQuickAmount(200),
              ),
              const SizedBox(width: 8),
              _QuickChip(
                amount: 500,
                isSelected: selectedQuickAmount == 500,
                onTap: () => onQuickAmount(500),
              ),
              const SizedBox(width: 8),
              _QuickChip(
                amount: 1000,
                isSelected: selectedQuickAmount == 1000,
                onTap: () => onQuickAmount(1000),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Numpad
          _Numpad(
            onDigit: onDigit,
            onDoubleZero: onDoubleZero,
            onBackspace: onBackspace,
          ),
          const SizedBox(height: 20),
          // CTA
          _PrimaryCta(
            label: 'VARDİYAYI BAŞLAT',
            isLoading: isOpening,
            onTap: isOpening ? null : onStart,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: onBackToLogin,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('GİRİŞE DÖN'),
              style: TextButton.styleFrom(
                foregroundColor: GcColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick-amount chip
// ---------------------------------------------------------------------------

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.amount,
    required this.isSelected,
    required this.onTap,
  });

  final int amount;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        key: Key('quick_amount_$amount'),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 52,
          decoration: BoxDecoration(
            color: isSelected
                ? GcColors.primary
                : GcColors.surfaceContainerLowest,
            border: Border.all(
              color: isSelected ? GcColors.primary : GcColors.outlineVariant,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            'CHF $amount',
            style: GcText.button.copyWith(
              fontSize: 14,
              color: isSelected ? GcColors.onPrimary : GcColors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Numpad
// ---------------------------------------------------------------------------

class _Numpad extends StatelessWidget {
  const _Numpad({
    required this.onDigit,
    required this.onDoubleZero,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDoubleZero;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['00', '0', 'BACK'],
    ];
    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            children: [
              for (final key in row) ...[
                Expanded(child: _NumKey(label: key, onTap: () {
                  if (key == 'BACK') {
                    onBackspace();
                  } else if (key == '00') {
                    onDoubleZero();
                  } else {
                    onDigit(key);
                  }
                })),
                if (key != row.last) const SizedBox(width: 8),
              ],
            ],
          ),
          if (row != rows.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _NumKey extends StatelessWidget {
  const _NumKey({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBack = label == 'BACK';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            color: GcColors.surfaceContainerLowest,
            border: Border.all(color: GcColors.outlineVariant, width: 1),
          ),
          child: Center(
            child: isBack
                ? const Icon(Icons.backspace_outlined,
                    size: 20, color: GcColors.onSurfaceVariant)
                : Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: label == '00' ? 18 : 22,
                      fontWeight: FontWeight.w700,
                      color: GcColors.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Primary CTA — gradient + top highlight strip
// ---------------------------------------------------------------------------

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.label,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('shift_start_btn'),
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: const BoxDecoration(
          gradient: kPrimaryGradient,
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0, left: 0, right: 0, height: 1,
              child: Container(color: kInsetHighlight),
            ),
            Center(
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: GcColors.onPrimary,
                      ),
                    )
                  : Text(
                      label,
                      style: GcText.button.copyWith(
                        color: GcColors.onPrimary,
                        fontSize: 15,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
