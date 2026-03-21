/// Shift Opening Screen for GastroCore POS - Stitch V2 Design.
///
/// Centered card with icon, numpad, quick amounts, gradient button.
/// Matches Stitch V2 shift_opening design exactly.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
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
  String _amountStr = '1000';
  bool _isOpening = false;
  int _selectedQuickAmount = 1000; // track which quick button is selected

  @override
  void initState() {
    super.initState();
  }

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
    if (val == 0) return '0,00';
    final formatted = val.toStringAsFixed(0);
    final parts = <String>[];
    for (var i = formatted.length; i > 0; i -= 3) {
      final start = i - 3 < 0 ? 0 : i - 3;
      parts.insert(0, formatted.substring(start, i));
    }
    return '${parts.join(".")},00';
  }

  Future<void> _onStartShift() async {
    if (_isOpening) return;
    setState(() => _isOpening = true);

    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    final openingCash = (int.tryParse(_amountStr) ?? 0) * 100;

    try {
      await ref.read(currentShiftProvider.notifier).openShift(
            userId: user.id,
            openingCash: openingCash,
          );

      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        setState(() => _isOpening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open shift: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  String _roleLabel(UserRole role) {
    return switch (role) {
      UserRole.admin => 'ADMIN',
      UserRole.manager => 'MANAGER',
      UserRole.waiter => 'WAITER',
      UserRole.cashier => 'CASHIER',
      UserRole.kitchen => 'KITCHEN',
    };
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final userRole = user != null ? _roleLabel(user.role) : 'ADMIN';

    return Scaffold(
      key: const Key('shift_open_screen'),
      backgroundColor: AppColors.surfaceDim,
      // Action buttons pinned at bottom so they are always in the viewport
      // (important for automated tests running at 800x600).
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Start shift button
            GestureDetector(
              key: const Key('shift_start_btn'),
              onTap: _isOpening ? null : _onStartShift,
              child: Container(
                width: double.infinity,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const AppColors.primaryLight.withValues(alpha: 0.1),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Center(
                  child: _isOpening
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF002D6D),
                          ),
                        )
                      : const Text(
                          'VARDIYAYI BASLAT',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF002D6D),
                            letterSpacing: 1.0,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Back to login
            GestureDetector(
              onTap: () => context.go('/login'),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.arrow_back, size: 16, color: Color(0xFFC3C6D7)),
                    const SizedBox(width: 8),
                    const Text(
                      'Back to Login',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFC3C6D7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Background blur accents
          Positioned(
            top: -96,
            left: -96,
            child: Container(
              width: 384,
              height: 384,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const AppColors.primaryLight.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -96,
            right: -96,
            child: Container(
              width: 384,
              height: 384,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const AppColors.primaryLight.withValues(alpha: 0.10),
              ),
            ),
          ),
          // Main centered card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top section: icon + title
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.payments,
                              size: 30,
                              color: AppColors.primaryLight,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'VARDIYA AC / OPEN SHIFT',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE2E2EB),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                userRole,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFFB4B8C9),
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Amount display
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDim,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'ACILIS KASASI',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFC3C6D7).withValues(alpha: 0.6),
                                letterSpacing: 2.0,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Flexible(
                                  child: Text(
                                    _formatDisplayAmount(),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFE2E2EB),
                                      letterSpacing: -2.0,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '\u20BA',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Quick amounts
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
                      child: Row(
                        children: [
                          _buildQuickBtn(200),
                          const SizedBox(width: 16),
                          _buildQuickBtn(500),
                          const SizedBox(width: 16),
                          _buildQuickBtn(1000),
                        ],
                      ),
                    ),

                    // Numpad
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                      child: _buildNumpad(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickBtn(int amount) {
    final isSelected = _selectedQuickAmount == amount;
    return Expanded(
      child: GestureDetector(
        key: Key('quick_amount_$amount'),
        onTap: () => _onQuickAmount(amount),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF33343B)
                : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: const AppColors.primaryLight.withValues(alpha: 0.2), width: 2)
                : null,
          ),
          child: Center(
            child: Text(
              '$amount',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? const AppColors.primaryLight
                    : const Color(0xFFE2E2EB),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        _buildNumRow(['1', '2', '3']),
        const SizedBox(height: 12),
        _buildNumRow(['4', '5', '6']),
        const SizedBox(height: 12),
        _buildNumRow(['7', '8', '9']),
        const SizedBox(height: 12),
        _buildNumRow(['00', '0', 'BACK']),
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
              left: idx == 0 ? 0 : 6,
              right: idx == keys.length - 1 ? 0 : 6,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (key == 'BACK') {
                    _onBackspace();
                  } else if (key == '00') {
                    _onDoubleZero();
                  } else {
                    _onDigit(key);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Ink(
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1F26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: key == 'BACK'
                        ? const Icon(
                            Icons.backspace_outlined,
                            size: 22,
                            color: AppColors.primaryLight,
                          )
                        : Text(
                            key,
                            style: TextStyle(
                              fontSize: key == '00' ? 20 : 24,
                              fontWeight: FontWeight.w700,
                              color: key == '00'
                                  ? const Color(0xFFB4B8C9)
                                  : const Color(0xFFE2E2EB),
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
