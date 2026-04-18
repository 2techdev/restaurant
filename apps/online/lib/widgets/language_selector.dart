/// Language selector floating button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_online/core/theme/app_theme.dart';
import 'package:gastrocore_online/providers/locale_provider.dart';

class LanguageSelector extends ConsumerWidget {
  const LanguageSelector({super.key, this.onLight = false});
  final bool onLight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    final langs = [
      {'code': 'de', 'label': 'DE'},
      {'code': 'tr', 'label': 'TR'},
      {'code': 'en', 'label': 'EN'},
      {'code': 'fr', 'label': 'FR'},
      {'code': 'it', 'label': 'IT'},
    ];

    return GestureDetector(
      onTap: () => _showPicker(context, ref, langs),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: onLight
              ? OnlineColors.bgCard
              : Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 16,
              color: onLight
                  ? OnlineColors.textSecondary
                  : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              locale.languageCode.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: onLight
                    ? OnlineColors.textPrimary
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, String>> langs,
  ) {
    final notifier = ref.read(localeProvider.notifier);
    final current = ref.read(localeProvider);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusXl)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: OnlineColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ...langs.map((lang) {
                final isSelected =
                    current.languageCode == lang['code'];
                return ListTile(
                  leading: Text(
                    _flag(lang['code']!),
                    style: const TextStyle(fontSize: 24),
                  ),
                  title: Text(
                    _languageName(lang['code']!),
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: isSelected
                          ? OnlineColors.primary
                          : OnlineColors.textPrimary,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check,
                          color: OnlineColors.primary)
                      : null,
                  onTap: () {
                    notifier.setLocale(Locale(lang['code']!));
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  String _flag(String code) {
    switch (code) {
      case 'de':
        return '🇨🇭';
      case 'tr':
        return '🇹🇷';
      case 'en':
        return '🇬🇧';
      case 'fr':
        return '🇫🇷';
      case 'it':
        return '🇮🇹';
      default:
        return '🌐';
    }
  }

  String _languageName(String code) {
    switch (code) {
      case 'de':
        return 'Deutsch';
      case 'tr':
        return 'Türkçe';
      case 'en':
        return 'English';
      case 'fr':
        return 'Français';
      case 'it':
        return 'Italiano';
      default:
        return code;
    }
  }
}
