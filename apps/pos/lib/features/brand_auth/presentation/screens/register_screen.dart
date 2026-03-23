/// Registration screen for new brand + store sign-up.
///
/// After successful registration the user is auto-logged in and redirected
/// to the PIN login screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/features/brand_auth/domain/entities/register_request.dart';
import 'package:gastrocore_pos/features/brand_auth/presentation/providers/brand_auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _restaurantNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _termsAccepted = false;

  @override
  void dispose() {
    _restaurantNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRegister() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_termsAccepted) {
      _showTermsError();
      return;
    }

    final request = RegisterRequest(
      restaurantName: _restaurantNameCtrl.text.trim(),
      ownerName: _ownerNameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      address: _addressCtrl.text.trim().isNotEmpty
          ? _addressCtrl.text.trim()
          : null,
      phone: _phoneCtrl.text.trim().isNotEmpty
          ? _phoneCtrl.text.trim()
          : null,
    );

    final success =
        await ref.read(brandAuthProvider.notifier).register(request);
    if (success && mounted) {
      context.go(AppRoutes.login); // → PIN screen
    }
  }

  void _showTermsError() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surfaceContainerHigh,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: const Text(
          'Bitte akzeptieren Sie die Nutzungsbedingungen.',
          style: TextStyle(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(brandAuthProvider);
    final isLoading = authState.isLoading;
    final error = authState.error;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDim,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textSecondary,
          ),
          onPressed: () => context.go(AppRoutes.brandLogin),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 40,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  _buildLogo(),
                  const SizedBox(height: 40),

                  // Heading
                  const Text(
                    'Konto erstellen',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Registrieren Sie Ihr Restaurant kostenlos.',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Error banner
                  if (error != null) ...[
                    _buildErrorBanner(error),
                    const SizedBox(height: 20),
                  ],

                  // Form
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Restaurant name
                        _buildLabel('Restaurantname *'),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _restaurantNameCtrl,
                          hint: 'z.B. Restaurant Zur Sonne',
                          icon: Icons.storefront_rounded,
                          validator: _requiredValidator('Restaurantname'),
                        ),
                        const SizedBox(height: 18),

                        // Owner name
                        _buildLabel('Name des Inhabers *'),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _ownerNameCtrl,
                          hint: 'Vor- und Nachname',
                          icon: Icons.person_outline_rounded,
                          validator: _requiredValidator('Name'),
                        ),
                        const SizedBox(height: 18),

                        // Email
                        _buildLabel('E-Mail *'),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _emailCtrl,
                          hint: 'name@restaurant.ch',
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'E-Mail ist erforderlich';
                            }
                            if (!v.contains('@')) {
                              return 'Ungültige E-Mail-Adresse';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                        // Password
                        _buildLabel('Passwort *'),
                        const SizedBox(height: 8),
                        _buildPasswordField(
                          controller: _passwordCtrl,
                          hint: 'Mindestens 8 Zeichen',
                          obscure: _obscurePassword,
                          onToggle: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          autofillHints: const [AutofillHints.newPassword],
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Passwort ist erforderlich';
                            }
                            if (v.length < 8) {
                              return 'Mindestens 8 Zeichen erforderlich';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                        // Confirm password
                        _buildLabel('Passwort bestätigen *'),
                        const SizedBox(height: 8),
                        _buildPasswordField(
                          controller: _confirmPasswordCtrl,
                          hint: 'Passwort wiederholen',
                          obscure: _obscureConfirm,
                          onToggle: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                          autofillHints: const [AutofillHints.newPassword],
                          validator: (v) {
                            if (v != _passwordCtrl.text) {
                              return 'Passwörter stimmen nicht überein';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),

                        // Address (optional)
                        _buildLabel('Adresse (optional)'),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _addressCtrl,
                          hint: 'Musterstrasse 1, 8001 Zürich',
                          icon: Icons.location_on_outlined,
                          keyboardType: TextInputType.streetAddress,
                        ),
                        const SizedBox(height: 18),

                        // Phone (optional)
                        _buildLabel('Telefon (optional)'),
                        const SizedBox(height: 8),
                        _buildField(
                          controller: _phoneCtrl,
                          hint: '+41 44 123 45 67',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 28),

                        // Terms checkbox
                        _buildTermsCheckbox(),
                        const SizedBox(height: 32),

                        // Submit button
                        _buildSubmitButton(isLoading),
                        const SizedBox(height: 20),

                        // Login link
                        _buildLoginLink(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Logo
  // ---------------------------------------------------------------------------

  Widget _buildLogo() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              colors: [Color(0xFF90ABFF), Color(0xFF316BF3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(
            Icons.restaurant_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF90ABFF), Color(0xFF316BF3)],
          ).createShader(bounds),
          child: const Text(
            'GASTROCORE',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 3.0,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Form helpers
  // ---------------------------------------------------------------------------

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<String>? autofillHints,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: _inputDecoration(hint: hint, prefixIcon: icon),
      validator: validator,
      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    List<String>? autofillHints,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      autofillHints: autofillHints,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: _inputDecoration(
        hint: hint,
        prefixIcon: Icons.lock_outline_rounded,
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppColors.textDim,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
      onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 15),
      filled: true,
      fillColor: AppColors.bgInput,
      prefixIcon: Icon(prefixIcon, color: AppColors.textDim, size: 20),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.borderFocused,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
      errorStyle: const TextStyle(color: AppColors.red, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    );
  }

  String? Function(String?) _requiredValidator(String fieldName) {
    return (v) {
      if (v == null || v.trim().isEmpty) return '$fieldName ist erforderlich';
      return null;
    };
  }

  // ---------------------------------------------------------------------------
  // Terms checkbox
  // ---------------------------------------------------------------------------

  Widget _buildTermsCheckbox() {
    return GestureDetector(
      onTap: () => setState(() => _termsAccepted = !_termsAccepted),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: _termsAccepted
                  ? const Color(0xFF316BF3)
                  : AppColors.surfaceContainerHigh,
            ),
            child: _termsAccepted
                ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Ich akzeptiere die Nutzungsbedingungen und '
              'Datenschutzrichtlinie von GastroCore.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Buttons
  // ---------------------------------------------------------------------------

  Widget _buildSubmitButton(bool isLoading) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : _onRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF316BF3),
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              const Color(0xFF316BF3).withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Konto erstellen',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Bereits ein Konto? ',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        GestureDetector(
          onTap: () => context.go(AppRoutes.brandLogin),
          child: const Text(
            'Anmelden',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF90ABFF),
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFF90ABFF),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Error banner
  // ---------------------------------------------------------------------------

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.redDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.red, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.red),
            ),
          ),
        ],
      ),
    );
  }
}
