/// PIN Login Screen for GastroCore POS - Stitch V2 Design.
///
/// Three-column layout: left branding/station info, center staff grid,
/// right PIN pad. Matches Stitch V2 pin_login design exactly.
///
/// Loads users from [usersListProvider] and authenticates via
/// [currentUserProvider] / [currentShiftProvider].
library;

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/shifts/presentation/providers/shift_provider.dart';

// ---------------------------------------------------------------------------
// PIN Login Screen
// ---------------------------------------------------------------------------

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen>
    with SingleTickerProviderStateMixin {
  int _selectedUserIndex = 0;
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
    final months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    if (mounted) {
      setState(() {
        _currentTime = '$h:$m $amPm';
        _currentDate = '${days[now.weekday - 1]}, ${months[now.month]} ${now.day}, ${now.year}';
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

    final success =
        await ref.read(currentUserProvider.notifier).loginWithPin(pinHash);

    if (!mounted) return;

    if (success) {
      await ref.read(currentShiftProvider.notifier).loadCurrentShift();
      if (!mounted) return;

      final shift = ref.read(currentShiftProvider);
      if (shift != null) {
        context.go('/home');
      } else {
        context.go('/shift-open');
      }
    } else {
      setState(() {
        _showError = true;
        _isLoggingIn = false;
      });
      _shakeController.forward(from: 0);
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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  String _roleLabel(UserRole role) {
    return switch (role) {
      UserRole.admin => 'Admin',
      UserRole.manager => 'Manager',
      UserRole.waiter => 'Server',
      UserRole.cashier => 'Cashier',
      UserRole.kitchen => 'Chef',
    };
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersListProvider);

    return Scaffold(
      key: const Key('pin_login_screen'),
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        child: usersAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
              color: AppColors.primaryLight,
            ),
          ),
          error: (err, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load users',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          data: (users) {
            if (users.isEmpty) {
              return const Center(
                child: Text(
                  'No users found',
                  style: TextStyle(fontSize: 16, color: AppColors.textDim),
                ),
              );
            }
            if (_selectedUserIndex >= users.length) {
              _selectedUserIndex = 0;
            }
            return _buildContent(users);
          },
        ),
      ),
    );
  }

  Widget _buildContent(List<UserEntity> users) {
    return Column(
      children: [
        // -- Top Status Bar --
        _buildTopBar(),
        // -- Main 3-column layout --
        Expanded(
          child: ClipRect(
            child: Row(
              children: [
                // LEFT: Branding + Station info
                _buildLeftBranding(),
                // CENTER: Staff selection grid
                Expanded(child: _buildStaffGrid(users)),
                // RIGHT: PIN Pad
                _buildPinPad(),
              ],
            ),
          ),
        ),
        // -- Footer --
        _buildFooter(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Top Status Bar
  // ---------------------------------------------------------------------------

  Widget _buildTopBar() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      color: AppColors.surfaceDim,
      child: Row(
        children: [
          // Logo
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
          // Time + Terminal
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

  // ---------------------------------------------------------------------------
  // Left Branding Section (1/4 width)
  // ---------------------------------------------------------------------------

  Widget _buildLeftBranding() {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.25,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              const Text(
                'GastroCore',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Restaurant POS System',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 32),
              // Gradient accent line
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primary],
                  ),
                ),
              ),
              const SizedBox(height: 48),
              // Station info card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACTIVE STATION',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDim,
                        letterSpacing: 3.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Station 01',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.wifi, color: AppColors.primaryLight, size: 16),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Network Connected',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Center Staff Grid
  // ---------------------------------------------------------------------------

  Widget _buildStaffGrid(List<UserEntity> users) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          bottomLeft: Radius.circular(32),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(bottom: 48, top: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Flexible(
                      child: Text(
                        'Select Staff Member',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        '${users.length} Staff Online',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Grid of staff avatars (4 columns)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Wrap(
                  spacing: 32,
                  runSpacing: 48,
                  alignment: WrapAlignment.start,
                  children: List.generate(users.length, (index) {
                    final user = users[index];
                    final isSelected = index == _selectedUserIndex;
                    return _buildStaffAvatar(user, isSelected, index);
                  }),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaffAvatar(UserEntity user, bool isSelected, int index) {
    return GestureDetector(
      key: Key('user_avatar_$index'),
      onTap: () => setState(() {
        _selectedUserIndex = index;
        _pin = '';
        _showError = false;
      }),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isSelected ? 1.0 : 0.7,
        child: SizedBox(
          width: 96,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar circle
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceDim,
                  border: isSelected
                      ? Border.all(color: const AppColors.primary, width: 4)
                      : null,
                ),
                child: Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF33343B),
                    ),
                    child: Center(
                      child: Text(
                        _initials(user.name),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE2E2EB),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Name
              Text(
                user.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              // Role
              Text(
                _roleLabel(user.role),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Right PIN Pad Section (400px wide)
  // ---------------------------------------------------------------------------

  Widget _buildPinPad() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Container(
        color: AppColors.surfaceDim,
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // PIN dots
              _buildPinDots(),
              const SizedBox(height: 48),
              // Numpad
              _buildNumpad(),
              const SizedBox(height: 24),
              // Enter button
              _buildEnterButton(),
              const SizedBox(height: 48),
              // Footer text
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
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _showError
                    ? AppColors.red
                    : isFilled
                        ? const AppColors.primaryLight
                        : const Color(0xFF33343B),
                boxShadow: isFilled && !_showError
                    ? [
                        BoxShadow(
                          color: const AppColors.primary.withValues(alpha: 0.4),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Column(
        children: [
          _buildNumRow(['1', '2', '3']),
          const SizedBox(height: 12),
          _buildNumRow(['4', '5', '6']),
          const SizedBox(height: 12),
          _buildNumRow(['7', '8', '9']),
          const SizedBox(height: 12),
          _buildNumRow(['BACK', '0', 'CLEAR']),
        ],
      ),
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
                splashColor: const AppColors.primary.withValues(alpha: 0.15),
                child: Ink(
                  height: 64,
                  decoration: BoxDecoration(
                    color: const AppColors.surfaceContainerHigh,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: GestureDetector(
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
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Footer
  // ---------------------------------------------------------------------------

  Widget _buildFooter() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      color: const Color(0xFF0C0E14),
      child: Row(
        children: [
          // Version info
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  child: Text(
                    'Version 0.1.0',
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
          // Date
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
          // Sync status
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
