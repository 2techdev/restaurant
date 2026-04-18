/// Riverpod providers for the staff live status screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'staff_models.dart';
import 'staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(),
);

final activeStaffProvider = StreamProvider<List<ActiveStaffMember>>((ref) {
  return ref.watch(staffRepositoryProvider).watchActiveStaff();
});
