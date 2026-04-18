import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_boss/features/staff/staff_models.dart';
import 'package:gastrocore_boss/features/staff/staff_providers.dart';
import 'package:gastrocore_boss/features/staff/staff_repository.dart';
import 'package:gastrocore_boss/features/staff/staff_screen.dart';

class _StaticStaffRepo extends StaffRepository {
  @override
  Stream<List<ActiveStaffMember>> watchActiveStaff(
      {Duration interval = const Duration(seconds: 30)}) {
    return Stream.value([
      ActiveStaffMember(
        id: 'a',
        name: 'Max Müller',
        roleLabel: 'Garson',
        clockedInAt:
            DateTime.now().subtract(const Duration(hours: 4, minutes: 12)),
        openTableCount: 4,
        averageTicketTime: const Duration(minutes: 18, seconds: 22),
      ),
      ActiveStaffMember(
        id: 'b',
        name: 'Sarah Weber',
        roleLabel: 'Garson',
        clockedInAt:
            DateTime.now().subtract(const Duration(hours: 3, minutes: 45)),
        openTableCount: 3,
        averageTicketTime: const Duration(minutes: 21, seconds: 5),
      ),
    ]);
  }
}

class _EmptyStaffRepo extends StaffRepository {
  @override
  Stream<List<ActiveStaffMember>> watchActiveStaff(
      {Duration interval = const Duration(seconds: 30)}) {
    return Stream.value(const []);
  }
}

void main() {
  testWidgets('StaffScreen renders summary header + tiles', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffRepositoryProvider.overrideWithValue(_StaticStaffRepo()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StaffScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Vardiyada'), findsOneWidget);
    expect(find.text('Açık masa'), findsOneWidget);
    expect(find.text('Max Müller'), findsOneWidget);
    expect(find.text('Sarah Weber'), findsOneWidget);
    expect(find.text('4 masa'), findsOneWidget);
    expect(find.text('3 masa'), findsOneWidget);
  });

  testWidgets('StaffScreen shows empty state when nobody is clocked in',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffRepositoryProvider.overrideWithValue(_EmptyStaffRepo()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StaffScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Vardiyada kimse yok'), findsOneWidget);
  });
}
