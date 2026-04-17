import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

void main() {
  group('GastrocoreTheme', () {
    test('dark() builds a usable Material 3 ThemeData', () {
      final theme = GastrocoreTheme.dark();
      expect(theme, isA<ThemeData>());
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, AppColors.primary);
    });

    testWidgets('MaterialApp renders with GastrocoreTheme.dark', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: GastrocoreTheme.dark(),
        home: const Scaffold(body: Text('hello')),
      ));
      expect(find.text('hello'), findsOneWidget);
    });
  });
}
