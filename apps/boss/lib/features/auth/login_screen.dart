/// Boss login screen — PIN tab + email tab.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

import 'auth_controller.dart';
import 'auth_state.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _pinCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _pinCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final isLoading = state is AuthLoading;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(),
                  const SizedBox(height: 32),
                  Card(
                    color: AppColors.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TabBar(
                            controller: _tab,
                            indicatorColor: AppColors.accent,
                            labelColor: AppColors.textPrimary,
                            unselectedLabelColor: AppColors.textSecondary,
                            tabs: const [
                              Tab(text: 'PIN'),
                              Tab(text: 'E-posta'),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 220,
                            child: TabBarView(
                              controller: _tab,
                              children: [
                                _PinForm(
                                  controller: _pinCtrl,
                                  enabled: !isLoading,
                                  onSubmit: _submitPin,
                                ),
                                _EmailForm(
                                  emailCtrl: _emailCtrl,
                                  passwordCtrl: _passwordCtrl,
                                  enabled: !isLoading,
                                  onSubmit: _submitEmail,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (state is AuthFailure)
                    _Banner(
                      color: AppColors.redDim,
                      icon: Icons.error_outline,
                      iconColor: AppColors.red,
                      message: state.message,
                    ),
                  if (state is AuthUnauthorized)
                    _Banner(
                      color: AppColors.orangeDim,
                      icon: Icons.lock_outline,
                      iconColor: AppColors.orange,
                      message: state.message,
                    ),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submitPin() {
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4 || pin.length > 6) return;
    ref.read(authControllerProvider.notifier).loginWithPin(pin);
  }

  void _submitEmail() {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) return;
    ref
        .read(authControllerProvider.notifier)
        .loginWithEmail(email: email, password: password);
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.accentDim,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.business_center,
            color: AppColors.accent,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Boss',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'İşletme sahibi panosu',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _PinForm extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;

  const _PinForm({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('boss-login-pin'),
          controller: controller,
          enabled: enabled,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'PIN (4-6 hane)',
            counterText: '',
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('boss-login-pin-submit'),
          onPressed: enabled ? onSubmit : null,
          child: const Text('Giriş yap'),
        ),
      ],
    );
  }
}

class _EmailForm extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool enabled;
  final VoidCallback onSubmit;

  const _EmailForm({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.enabled,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('boss-login-email'),
          controller: emailCtrl,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-posta'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('boss-login-password'),
          controller: passwordCtrl,
          enabled: enabled,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Şifre'),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('boss-login-email-submit'),
          onPressed: enabled ? onSubmit : null,
          child: const Text('Giriş yap'),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Color iconColor;
  final String message;

  const _Banner({
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
