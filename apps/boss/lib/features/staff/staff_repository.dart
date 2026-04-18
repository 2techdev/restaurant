/// Staff repository — fetches the list of currently clocked-in staff with
/// their assigned tables and average ticket time.
///
/// TODO(boss-sprint2): wire to `StaffApi.activeStaff` once available.
library;

import 'staff_models.dart';

class StaffRepository {
  Stream<List<ActiveStaffMember>> watchActiveStaff({
    Duration interval = const Duration(seconds: 30),
  }) async* {
    yield _placeholder();
    await for (final _ in Stream<void>.periodic(interval)) {
      yield _placeholder();
    }
  }

  List<ActiveStaffMember> _placeholder() {
    final now = DateTime.now();
    return [
      ActiveStaffMember(
        id: 'u-max',
        name: 'Max Müller',
        roleLabel: 'Garson',
        clockedInAt: now.subtract(const Duration(hours: 4, minutes: 12)),
        openTableCount: 4,
        averageTicketTime: const Duration(minutes: 18, seconds: 22),
      ),
      ActiveStaffMember(
        id: 'u-sarah',
        name: 'Sarah Weber',
        roleLabel: 'Garson',
        clockedInAt: now.subtract(const Duration(hours: 3, minutes: 45)),
        openTableCount: 3,
        averageTicketTime: const Duration(minutes: 21, seconds: 5),
      ),
      ActiveStaffMember(
        id: 'u-luca',
        name: 'Luca Bernasconi',
        roleLabel: 'Şef',
        clockedInAt: now.subtract(const Duration(hours: 5, minutes: 30)),
        openTableCount: 0,
        averageTicketTime: const Duration(minutes: 14, seconds: 50),
      ),
      ActiveStaffMember(
        id: 'u-anna',
        name: 'Anna Fischer',
        roleLabel: 'Kasiyer',
        clockedInAt: now.subtract(const Duration(hours: 2, minutes: 10)),
        openTableCount: 2,
        averageTicketTime: const Duration(minutes: 9, seconds: 18),
      ),
    ];
  }
}
