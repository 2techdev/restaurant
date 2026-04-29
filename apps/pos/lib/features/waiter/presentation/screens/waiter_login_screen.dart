/// Waiter-mode PIN login screen.
///
/// Simplified, phone-optimised version of the POS [PinLoginScreen].
/// Single-column layout: branding at the top, staff picker in the middle,
/// PIN pad at the bottom. Dark theme suits dim restaurant lighting.
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
import 'package:gastrocore_pos/features/waiter/router/waiter_router.dart';

// ---------------------------------------------------------------------------
// WaiterLoginScreen
// ---------------------------------------------------------------------------

class WaiterLoginScreen extends ConsumerStatefulWidget {
  const WaiterLoginScreen({super.key});

  @override
  ConsumerState<WaiterLoginScreen> createState() => _WaiterLoginScreenState();
}

class _WaiterLoginScreenState extends ConsumerState<WaiterLoginScreen> {
  int _selectedIndex = 0;
  String _pin = '';
  bool _showError = false;
  bool _isLoggingIn = false;
  late final Timer _clockTimer;
  String _currentTime = '';

  static const int _pinLength = 4;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTime(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(currentUserProvider.notifier).logout();
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final m = now.minute.toString().padLeft(2, '0');
    final amPm = now.hour >= 12 ? 'PM' : 'AM';
    if (mounted) setState(() => _currentTime = '$h:$m $amPm');
  }

  void _onDigit(String digit) {
    if (_pin.length >= _pinLength) return;
    setState(() {
      _showError = false;
      _pin += digit;
    });
    if (_pin.length == _pinLength) _onEnter();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _showError = false;
      _pin = _pin.substring(0, _pin.length - 1);
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
      context.go(WaiterRoutes.tables);
    } else {
      setState(() {
        _showError = true;
        _isLoggingIn = false;
        _pin = '';
      });
      if (result == LoginResult.pinCollision) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN çakışması — yöneticiyle görüşün.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) setState(() => _showError = false);
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
    final usersAsync = ref.watch(usersListProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        child: usersAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => Center(
            child: Text(e.toString(),
                style: const TextStyle(color: AppColors.red)),
          ),
          data: (users) {
            if (users.isEmpty) {
              return const Center(
                child: Text('No staff found',
                    style: TextStyle(color: AppColors.textDim)),
              );
            }
            if (_selectedIndex >= users.length) _selectedIndex = 0;
            return Column(
              children: [
                _buildHeader(),
                _buildStaffRow(users),
                const Spacer(),
                _buildPinDots(),
                const SizedBox(height: 24),
                _buildNumpad(),
                const SizedBox(height: 32),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          const Icon(Icons.restaurant_menu,
              color: AppColors.primary, size: 28),
          const SizedBox(width: 12),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryContainer],
            ).createShader(bounds),
            child: const Text(
              'GastroCore Waiter',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          Text(
            _currentTime,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Staff row (horizontal scrollable)
  // ---------------------------------------------------------------------------

  Widget _buildStaffRow(List<UserEntity> users) {
    return Container(
      height: 120,
      color: AppColors.surfaceContainerLow,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          final isSelected = index == _selectedIndex;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedIndex = index;
              _pin = '';
              _showError = false;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accentDim
                    : AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: isSelected
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.surfaceContainerHighest,
                    child: Text(
                      _initials(user.name),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user.name.split(' ').first,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PIN dots
  // ---------------------------------------------------------------------------

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pinLength, (index) {
        final isFilled = index < _pin.length;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _showError
                  ? AppColors.red
                  : isFilled
                      ? AppColors.primary
                      : AppColors.surfaceContainerHighest,
              boxShadow: isFilled && !_showError
                  ? [
                      BoxShadow(
                        color: AppColors.primaryContainer.withValues(alpha: 0.4),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Numpad
  // ---------------------------------------------------------------------------

  Widget _buildNumpad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'DEL'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: keys.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: row.map((key) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _buildKey(key),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKey(String key) {
    if (key.isEmpty) return const SizedBox.shrink();

    final isDel = key == 'DEL';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDel ? _onBackspace : () => _onDigit(key),
        borderRadius: BorderRadius.circular(14),
        splashColor: AppColors.primaryContainer.withValues(alpha: 0.15),
        child: Ink(
          height: 68,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: isDel
                ? const Icon(Icons.backspace_outlined,
                    color: AppColors.textSecondary, size: 22)
                : Text(
                    key,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
