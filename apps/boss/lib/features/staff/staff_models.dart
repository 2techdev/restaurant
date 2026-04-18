/// Live staff DTO for the Boss staff status screen.
///
/// TODO(boss-sprint2): replace with `gastrocore_models` `ActiveStaff`
/// once the StaffApi.activeStaff endpoint lands (commit a1e3fc0).
library;

class ActiveStaffMember {
  final String id;
  final String name;
  final String roleLabel;
  final DateTime clockedInAt;
  final int openTableCount;
  final Duration averageTicketTime;

  const ActiveStaffMember({
    required this.id,
    required this.name,
    required this.roleLabel,
    required this.clockedInAt,
    required this.openTableCount,
    required this.averageTicketTime,
  });

  Duration get shiftDuration => DateTime.now().difference(clockedInAt);
}
