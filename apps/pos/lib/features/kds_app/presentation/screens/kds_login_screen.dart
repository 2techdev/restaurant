/// KDS Login Screen — PIN or auto-login for kitchen station.
///
/// If a station PIN has been saved in SharedPreferences the screen
/// auto-advances to [KdsRoutes.main] without user interaction.
/// Otherwise a 4-digit PIN pad is shown.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/kds_app/router/kds_router.dart';

// ---------------------------------------------------------------------------
// Provider — saved station PIN
// ---------------------------------------------------------------------------

final _savedPinProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('kds_station_pin');
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class KdsLoginScreen extends ConsumerStatefulWidget {
  const KdsLoginScreen({super.key});

  @override
  ConsumerState<KdsLoginScreen> createState() => _KdsLoginScreenState();
}

class _KdsLoginScreenState extends ConsumerState<KdsLoginScreen> {
  final List<String> _digits = [];
  bool _error = false;

  // Correct PIN — configurable via settings; default 1234.
  static const String _defaultPin = '1234';

  // -------------------------------------------------------------------------

  Future<void> _tryAutoLogin(String? savedPin) async {
    if (savedPin != null && savedPin.isNotEmpty) {
      await Future.microtask(() {});
      if (mounted) context.go(KdsRoutes.main);
    }
  }

  void _onDigit(String d) {
    if (_digits.length >= 4) return;
    setState(() {
      _digits.add(d);
      _error = false;
    });
    if (_digits.length == 4) _validate();
  }

  void _onDelete() {
    if (_digits.isEmpty) return;
    setState(() {
      _digits.removeLast();
      _error = false;
    });
  }

  Future<void> _validate() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('kds_station_pin') ?? _defaultPin;
    final entered = _digits.join();
    if (entered == savedPin) {
      if (mounted) context.go(KdsRoutes.main);
    } else {
      setState(() {
        _digits.clear();
        _error = true;
      });
      HapticFeedback.heavyImpact();
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final savedPinAsync = ref.watch(_savedPinProvider);

    savedPinAsync.whenData((pin) => _tryAutoLogin(pin));

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFAFC6FF), Color(0xFF528DFF)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.restaurant,
                  size: 32,
                  color: Color(0xFF001944),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'GastroCore KDS',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter station PIN to continue',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 40),

              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _digits.length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _error
                            ? AppColors.red
                            : filled
                                ? AppColors.primary
                                : AppColors.surfaceContainerHigh,
                        border: Border.all(
                          color: _error
                              ? AppColors.red
                              : filled
                                  ? AppColors.primary
                                  : AppColors.outlineVariant,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }),
              ),

              if (_error) ...[
                const SizedBox(height: 12),
                const Text(
                  'Incorrect PIN. Try again.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // PIN pad
              _buildPinPad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinPad() {
    final labels = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];

    return Column(
      children: labels.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: row.map((key) {
              if (key.isEmpty) return const SizedBox(width: 88);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _PinKey(
                  label: key,
                  onTap: () {
                    if (key == 'del') {
                      _onDelete();
                    } else {
                      _onDigit(key);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// PIN key widget
// ---------------------------------------------------------------------------

class _PinKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PinKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDelete = label == 'del';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: isDelete
              ? const Icon(
                  Icons.backspace_outlined,
                  size: 22,
                  color: AppColors.textSecondary,
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}
