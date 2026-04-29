/// Smoke test for the dark-mode toggle wired through AppSettings.
///
/// Covers the two contracts that broke before this change:
///   1. `appSettingsProvider.setTheme(AppThemeMode.dark)` actually flips
///      `MaterialApp.themeMode`, so `Theme.of(context).brightness` reports
///      dark without the app being restarted.
///   2. The active `V2Palette` extension on the theme flips in step with
///      the brightness — so the sales shell's surface tokens switch
///      together with the Material theme.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/orders/presentation/theme/pos_v2_theme.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/app_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

class _ThemeProbe extends ConsumerWidget {
  const _ThemeProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSettings = ref.watch(appSettingsProvider).valueOrNull ??
        const AppSettings();
    final mode = switch (appSettings.themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };
    return MaterialApp(
      theme: buildKineticTheme(),
      darkTheme: buildKineticThemeDark(),
      themeMode: mode,
      home: Builder(
        builder: (ctx) {
          final palette = ctx.v2;
          return Scaffold(
            body: Column(
              children: [
                Text(
                  'brightness:${Theme.of(ctx).brightness.name}',
                  key: const Key('probe-brightness'),
                ),
                Text(
                  'v2-dark:${palette.isDark}',
                  key: const Key('probe-v2'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('AppSettings toggle flips MaterialApp theme and V2 palette',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _ThemeProbe(),
      ),
    );

    // Let SharedPreferences resolve + first settings load complete.
    await tester.pumpAndSettle();

    // Default fresh install is light.
    expect(find.byKey(const Key('probe-brightness')), findsOneWidget);
    expect(
      (tester.widget<Text>(find.byKey(const Key('probe-brightness'))).data),
      'brightness:light',
    );
    expect(
      (tester.widget<Text>(find.byKey(const Key('probe-v2'))).data),
      'v2-dark:false',
    );

    // User flips the toggle through Settings.
    await container
        .read(appSettingsProvider.notifier)
        .setTheme(AppThemeMode.dark);
    await tester.pumpAndSettle();

    expect(
      (tester.widget<Text>(find.byKey(const Key('probe-brightness'))).data),
      'brightness:dark',
      reason: 'setTheme(dark) must flip MaterialApp.themeMode to dark',
    );
    expect(
      (tester.widget<Text>(find.byKey(const Key('probe-v2'))).data),
      'v2-dark:true',
      reason: 'Dark theme must carry the dark V2Palette extension',
    );

    // And back to light.
    await container
        .read(appSettingsProvider.notifier)
        .setTheme(AppThemeMode.light);
    await tester.pumpAndSettle();

    expect(
      (tester.widget<Text>(find.byKey(const Key('probe-brightness'))).data),
      'brightness:light',
    );
    expect(
      (tester.widget<Text>(find.byKey(const Key('probe-v2'))).data),
      'v2-dark:false',
    );
  });

  test('AppSettings.fromJson defaults themeMode to light on empty payload',
      () {
    expect(AppSettings().themeMode, AppThemeMode.light);
    expect(
      AppSettings.fromJson(const <String, dynamic>{}).themeMode,
      AppThemeMode.light,
    );
  });
}
