import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/license/flag_gate_widget.dart';
import 'package:gastrocore_pos/features/license/license_models.dart';
import 'package:gastrocore_pos/features/license/license_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [widget] in a [ProviderScope] with a pre-configured [licenseTokenProvider].
Widget buildWithLicense({
  required Widget widget,
  LicenseEdition edition = LicenseEdition.free,
  List<FeatureFlag> explicitFeatures = const [],
}) {
  final now = DateTime.now().toUtc();
  final token = LicenseToken(
    edition: edition,
    features: explicitFeatures,
    expiresAt: now.add(const Duration(days: 365)),
    deviceLimit: 1,
    customerName: 'Test Restaurant',
    issuedAt: now,
  );

  return ProviderScope(
    overrides: [
      licenseTokenProvider.overrideWithValue(token),
      licenseEditionProvider.overrideWithValue(edition),
      isFlagEnabledProvider.overrideWith((ref, flag) => token.hasFlag(flag)),
    ],
    child: MaterialApp(home: Scaffold(body: widget)),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FlagGate', () {
    testWidgets('shows child when flag is enabled', (tester) async {
      await tester.pumpWidget(
        buildWithLicense(
          edition: LicenseEdition.pro, // pro enables kds
          widget: const FlagGate(
            flag: FeatureFlag.kds,
            child: Text('KDS Screen'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('KDS Screen'), findsOneWidget);
    });

    testWidgets('hides child and shows locked placeholder when flag is disabled',
        (tester) async {
      await tester.pumpWidget(
        buildWithLicense(
          edition: LicenseEdition.free, // free cannot access kds
          widget: const FlagGate(
            flag: FeatureFlag.kds,
            child: Text('KDS Screen'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('KDS Screen'), findsNothing);
      // The lock icon should be present in the placeholder.
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    });

    testWidgets('shows custom fallback instead of default placeholder',
        (tester) async {
      await tester.pumpWidget(
        buildWithLicense(
          edition: LicenseEdition.free,
          widget: const FlagGate(
            flag: FeatureFlag.cloudSync,
            fallback: Text('Custom Fallback'),
            child: Text('Sync Feature'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sync Feature'), findsNothing);
      expect(find.text('Custom Fallback'), findsOneWidget);
    });

    testWidgets('explicit feature override shows child even on lower edition',
        (tester) async {
      await tester.pumpWidget(
        buildWithLicense(
          edition: LicenseEdition.free,
          explicitFeatures: [FeatureFlag.kds], // explicit override
          widget: const FlagGate(
            flag: FeatureFlag.kds,
            child: Text('Granted KDS'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Granted KDS'), findsOneWidget);
    });

    testWidgets('enterprise edition shows all gated features', (tester) async {
      for (final flag in FeatureFlag.values) {
        await tester.pumpWidget(
          buildWithLicense(
            edition: LicenseEdition.enterprise,
            widget: FlagGate(
              flag: flag,
              child: Text('Feature: ${flag.name}'),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('Feature: ${flag.name}'),
          findsOneWidget,
          reason: '${flag.name} should be visible on enterprise',
        );
      }
    });
  });

  group('FlagBadge', () {
    testWidgets('shows FREE badge on free edition', (tester) async {
      await tester.pumpWidget(
        buildWithLicense(
          edition: LicenseEdition.free,
          widget: const FlagBadge(),
        ),
      );
      await tester.pump();
      expect(find.text('FREE'), findsOneWidget);
    });

    testWidgets('shows PRO badge on pro edition', (tester) async {
      await tester.pumpWidget(
        buildWithLicense(
          edition: LicenseEdition.pro,
          widget: const FlagBadge(),
        ),
      );
      await tester.pump();
      expect(find.text('PRO'), findsOneWidget);
    });

    testWidgets('shows ENT badge on enterprise edition', (tester) async {
      await tester.pumpWidget(
        buildWithLicense(
          edition: LicenseEdition.enterprise,
          widget: const FlagBadge(),
        ),
      );
      await tester.pump();
      expect(find.text('ENT'), findsOneWidget);
    });
  });
}
