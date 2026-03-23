/// Language selection screen.
///
/// Large flag-style buttons for the 4 Swiss national languages + English.
/// Selecting a language updates the app locale and navigates to the menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/features/kiosk/presentation/providers/kiosk_provider.dart';
import 'package:gastrocore_pos/features/kiosk/router/kiosk_router.dart';
import 'package:gastrocore_pos/features/kiosk/theme/kiosk_theme.dart';
import 'package:gastrocore_pos/features/kiosk/presentation/screens/kiosk_welcome_screen.dart';

// ---------------------------------------------------------------------------
// Language data
// ---------------------------------------------------------------------------

class _LangOption {
  final String code;
  final String nativeName;
  final String englishName;
  final String flag;
  final Locale locale;

  const _LangOption({
    required this.code,
    required this.nativeName,
    required this.englishName,
    required this.flag,
    required this.locale,
  });
}

const _languages = [
  _LangOption(
    code: 'DE',
    nativeName: 'Deutsch',
    englishName: 'German',
    flag: '🇩🇪',
    locale: Locale('de'),
  ),
  _LangOption(
    code: 'FR',
    nativeName: 'Français',
    englishName: 'French',
    flag: '🇫🇷',
    locale: Locale('fr'),
  ),
  _LangOption(
    code: 'IT',
    nativeName: 'Italiano',
    englishName: 'Italian',
    flag: '🇮🇹',
    locale: Locale('it'),
  ),
  _LangOption(
    code: 'EN',
    nativeName: 'English',
    englishName: 'English',
    flag: '🇬🇧',
    locale: Locale('en'),
  ),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class KioskLanguageScreen extends ConsumerWidget {
  const KioskLanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(kioskLocaleProvider);

    return Scaffold(
      backgroundColor: KioskColors.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _Header(onBack: () => context.go(KioskRoutes.welcome)),

            // ── Title ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Text(
                    'Choose your language',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Wähle deine Sprache  ·  Choisissez votre langue  ·  Scegli la tua lingua',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: KioskColors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // ── Language grid ────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 24,
                  childAspectRatio: 1.6,
                  shrinkWrap: true,
                  children: _languages.map((lang) {
                    final isSelected =
                        currentLocale.languageCode == lang.locale.languageCode;
                    return _LangCard(
                      lang: lang,
                      isSelected: isSelected,
                      onTap: () {
                        ref.read(kioskLocaleProvider.notifier).state = lang.locale;
                        context.go(KioskRoutes.menu);
                      },
                    );
                  }).toList(),
                ),
              ),
            ),

            // ── Step indicator ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: const KioskStepIndicator(currentStep: 0),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language card
// ---------------------------------------------------------------------------

class _LangCard extends StatefulWidget {
  final _LangOption lang;
  final bool isSelected;
  final VoidCallback onTap;

  const _LangCard({
    required this.lang,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_LangCard> createState() => _LangCardState();
}

class _LangCardState extends State<_LangCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _ctrl.forward();
    await _ctrl.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? KioskColors.primaryContainer
                : KioskColors.bgCard,
            borderRadius: BorderRadius.circular(kKioskRadiusLarge),
            border: Border.all(
              color: widget.isSelected
                  ? KioskColors.primary
                  : KioskColors.border,
              width: widget.isSelected ? 3 : 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: KioskColors.primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : const [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.lang.flag,
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 12),
              Text(
                widget.lang.nativeName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: widget.isSelected
                      ? KioskColors.primary
                      : KioskColors.textPrimary,
                ),
              ),
              Text(
                widget.lang.code,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: widget.isSelected
                      ? KioskColors.primaryDark
                      : KioskColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          _KioskBackButton(onTap: onBack),
          const Spacer(),
          Text(
            'GastroCore',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: KioskColors.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const Spacer(),
          const SizedBox(width: 56), // balance the back button
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared kiosk back button
// ---------------------------------------------------------------------------

/// A large, touchscreen-friendly back button used across kiosk screens.
class _KioskBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _KioskBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: KioskColors.bgCardAlt,
          borderRadius: BorderRadius.circular(kKioskRadiusMedium),
          border: Border.all(color: KioskColors.border),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 22,
          color: KioskColors.textPrimary,
        ),
      ),
    );
  }
}

/// Exported for reuse across kiosk screens.
class KioskBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const KioskBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => _KioskBackButton(onTap: onTap);
}
