import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_boss/features/auth/login_screen.dart';

void main() {
  testWidgets('LoginScreen shows PIN and Email tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PIN'), findsOneWidget);
    expect(find.text('E-posta'), findsOneWidget);
    expect(find.text('Boss'), findsOneWidget);
  });

  testWidgets('LoginScreen PIN tab shows PIN field', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('boss-login-pin')), findsOneWidget);
    expect(find.byKey(const Key('boss-login-pin-submit')), findsOneWidget);
  });

  testWidgets('Switching to email tab reveals email + password fields',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('E-posta'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('boss-login-email')), findsOneWidget);
    expect(find.byKey(const Key('boss-login-password')), findsOneWidget);
    expect(find.byKey(const Key('boss-login-email-submit')), findsOneWidget);
  });
}
