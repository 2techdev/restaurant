/// Unit tests for ActiveTenantNotifier.
///
/// SharedPreferences is faked via setMockInitialValues so the test exercises
/// the same code path as production (no separate in-memory adapter).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/tenant/active_tenant_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts on primary tenant when no override stored', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier =
        ActiveTenantNotifier(primaryTenantId: 'pilot-zurich-001', prefs: prefs);
    expect(notifier.state, 'pilot-zurich-001');
  });

  test('hydrates from SharedPreferences override', () async {
    SharedPreferences.setMockInitialValues({
      'active_tenant_id': 'pilot-bern-002',
    });
    final prefs = await SharedPreferences.getInstance();
    final notifier =
        ActiveTenantNotifier(primaryTenantId: 'pilot-zurich-001', prefs: prefs);

    // Constructor reads sync from prefs.getString.
    expect(notifier.state, 'pilot-bern-002');
  });

  test('switchTo persists and updates state', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier =
        ActiveTenantNotifier(primaryTenantId: 'pilot-zurich-001', prefs: prefs);

    await notifier.switchTo('pilot-bern-002');

    expect(notifier.state, 'pilot-bern-002');
    expect(prefs.getString('active_tenant_id'), 'pilot-bern-002');
  });

  test('switchTo to same tenant is a no-op', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier =
        ActiveTenantNotifier(primaryTenantId: 'pilot-zurich-001', prefs: prefs);

    await notifier.switchTo('pilot-zurich-001');
    expect(prefs.getString('active_tenant_id'), isNull);
  });

  test('switchTo ignores empty tenantId', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier =
        ActiveTenantNotifier(primaryTenantId: 'pilot-zurich-001', prefs: prefs);

    await notifier.switchTo('');
    expect(notifier.state, 'pilot-zurich-001');
    expect(prefs.getString('active_tenant_id'), isNull);
  });

  test('resetToPrimary returns to startup tenant', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier =
        ActiveTenantNotifier(primaryTenantId: 'pilot-zurich-001', prefs: prefs);

    await notifier.switchTo('pilot-bern-002');
    expect(notifier.state, 'pilot-bern-002');

    await notifier.resetToPrimary();
    expect(notifier.state, 'pilot-zurich-001');
    expect(prefs.getString('active_tenant_id'), 'pilot-zurich-001');
  });

  test('hydrate is idempotent', () async {
    SharedPreferences.setMockInitialValues({
      'active_tenant_id': 'pilot-bern-002',
    });
    final notifier = ActiveTenantNotifier(primaryTenantId: 'pilot-zurich-001');
    await notifier.hydrate();
    await notifier.hydrate();
    expect(notifier.state, 'pilot-bern-002');
  });
}
