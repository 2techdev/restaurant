/// PIN-only login screen — Kinetic Grid.
///
/// Single centered column: terminal header, PIN dots, numpad, enter CTA.
/// Users identify themselves by PIN alone; the backend resolves the user
/// from the PIN hash (PIN uniqueness is enforced per-tenant at the
/// repository level — see [PinCollisionException]).
library;

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  final bool _isOnline = true;
  bool _showError = false;
  bool _isLoggingIn = false;
  late final Timer _clockTimer;
  String _currentTime = '';
  String _currentDate = '';
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  static const int _pinLength = 4;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTime(),
    );
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 12).chain(
      CurveTween(curve: Curves.elasticIn),
    ).animate(_shakeController);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(currentUserProvider.notifier).logout();
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    final h = now.hour > 12 ? now.hour - 12 : now.hour;
    final m = now.minute.toString().padLeft(2, '0');
    final amPm = now.hour >= 12 ? 'PM' : 'AM';
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    if (mounted) {
      setState(() {
        _currentTime = '$h:$m $amPm';
        _currentDate =
            '${days[now.weekday - 1]}, ${months[now.month]} ${now.day}, ${now.year}';
      });
    }
  }

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength) return;
    setState(() {
      _showError = false;
      _pin += digit;
    });
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _showError = false;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  void _onClear() {
    setState(() {
      _showError = false;
      _pin = '';
    });
  }

  Future<void> _onEnter() async {
    if (_pin.length < _pinLength || _isLoggingIn) return;

    setState(() => _isLoggingIn = true);

    final pinHash = sha256.convert(utf8.encode(_pin)).toString();

    final result =
        await ref.read(currentUserProvider.notifier).loginWithPin(pinHash);

    if (!mounted) return;

    if (result == LoginResult.success) {
      await ref.read(currentShiftProvider.notifier).loadCurrentShift();
      if (!mounted) return;

      final shift = ref.read(currentShiftProvider);
      final settings = ref.read(restaurantSettingsProvider).valueOrNull;
      final shiftRequired = settings?.shiftStartRequired ?? true;
      if (shift != null || !shiftRequired) {
        context.go(AppRoutes.orderCenter);
      } else {
        context.go(AppRoutes.shiftOpen);
      }
    } else {
      setState(() {
        _showError = true;
        _isLoggingIn = false;
      });
      _shakeController.forward(from: 0);
      if (result == LoginResult.pinCollision) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN çakışması — yöneticiyle görüşün.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _pin = '';
            _showError = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('pin_login_screen'),
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 32,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPrompt(),
                        const SizedBox(height: 40),
                        _buildPinDots(),
                        const SizedBox(height: 40),
                        _buildNumpad(),
                        const SizedBox(height: 24),
                        _buildEnterButton(),
                        const SizedBox(height: 32),
                        const Text(
                          'AUTHORIZED PERSONNEL ONLY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDim,
                            letterSpacing: 3.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildPrompt() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'TERMINAL 01',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 3.0,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Personel PIN',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '4 haneli PIN\'inizi girin',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      color: AppColors.surfaceDim,
      child: Row(
        children: [
          const Icon(Icons.restaurant, color: AppColors.primaryLight, size: 30),
          const SizedBox(width: 16),
          Flexible(
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.primaryLight, AppColors.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'GastroCore',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _currentTime,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: 3.0,
                ),
              ),
              const Text(
                'Terminal ID: T-001',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Icon(
            _isOnline ? Icons.cloud_done : Icons.cloud_off,
            color: AppColors.textSecondary,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildPinDots() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            _shakeController.isAnimating
                ? _shakeAnimation.value *
                    ((_shakeController.value * 10).toInt().isEven ? 1 : -1)
                : 0,
            0,
          ),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLength, (index) {
          final isFilled = index < _pin.length;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _showError
                    ? AppColors.red
                    : isFilled
                        ? AppColors.primaryLight
                        : const Color(0xFF33343B),
                boxShadow: isFilled && !_showError
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        _buildNumRow(const ['1', '2', '3']),
        const SizedBox(height: 12),
        _buildNumRow(const ['4', '5', '6']),
        const SizedBox(height: 12),
        _buildNumRow(const ['7', '8', '9']),
        const SizedBox(height: 12),
        _buildNumRow(const ['BACK', '0', 'CLEAR']),
      ],
    );
  }

  Widget _buildNumRow(List<String> keys) {
    return Row(
      children: keys.map((key) {
        final isSpecial = key == 'CLEAR' || key == 'BACK';
        final idx = keys.indexOf(key);
        final keyId = isSpecial
            ? 'pin_${key.toLowerCase()}_btn'
            : 'pin_numpad_$key';
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: idx == 0 ? 0 : 6,
              right: idx == keys.length - 1 ? 0 : 6,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: Key(keyId),
                onTap: () {
                  if (key == 'CLEAR') {
                    _onClear();
                  } else if (key == 'BACK') {
                    _onBackspace();
                  } else {
                    _onDigit(key);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                splashColor: AppColors.primary.withValues(alpha: 0.15),
                child: Ink(
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: isSpecial
                        ? Icon(
                            key == 'BACK'
                                ? Icons.backspace_outlined
                                : Icons.close,
                            size: 22,
                            color: AppColors.textSecondary,
                          )
                        : Text(
                            key,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
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

  Widget _buildEnterButton() {
    final isComplete = _pin.length == _pinLength && !_isLoggingIn;
    return GestureDetector(
      key: const Key('pin_enter_btn'),
      onTap: isComplete ? _onEnter : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isComplete ? 1.0 : 0.5,
        child: Container(
          width: double.infinity,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [AppColors.primaryLight, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoggingIn)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else ...[
                const Text(
                  'ENTER',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 4.0,
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.login, color: Colors.white, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      color: const Color(0xFF0C0E14),
      child: Row(
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  child: Text(
                    'Version 1.3.0',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDim,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const _FooterDot(),
                const SizedBox(width: 16),
                const Flexible(
                  child: Text(
                    'System Stable',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDim,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              _currentDate,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textDim,
                letterSpacing: 2.0,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF22C55E),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'SYNC ACTIVE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 2.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterDot extends StatelessWidget {
  const _FooterDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.textDim,
      ),
    );
  }
}
