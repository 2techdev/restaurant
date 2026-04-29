import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController(text: 'admin@demo.ch');
  final _passwordCtrl = TextEditingController(text: 'demo');
  bool _rememberMe = true;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authProvider.notifier).login(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          rememberMe: _rememberMe,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.restaurant, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'GastroCore',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Dashboard & Administration',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 40),

                // Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Anmelden',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Zugang für Restaurant-Manager',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 28),

                          // Email
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'E-Mail-Adresse',
                              prefixIcon: Icon(Icons.email_outlined, size: 20),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'E-Mail erforderlich';
                              if (!v.contains('@')) return 'Ungültige E-Mail';
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 16),

                          // Password
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Passwort',
                              prefixIcon: const Icon(Icons.lock_outlined, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Passwort erforderlich';
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 12),

                          // Remember me
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (v) => setState(() => _rememberMe = v ?? true),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => setState(() => _rememberMe = !_rememberMe),
                                child: const Text('Angemeldet bleiben', style: TextStyle(fontSize: 14)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Error
                          if (authState.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withAlpha(26),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.error.withAlpha(77)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: AppColors.error, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        authState.error!,
                                        style: const TextStyle(color: AppColors.error, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // Submit button
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: authState.isLoading ? null : _submit,
                              child: authState.isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Anmelden'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Demo: admin@demo.ch / demo',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
