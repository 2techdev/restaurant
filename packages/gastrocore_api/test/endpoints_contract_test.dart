import 'dart:convert';

import 'package:gastrocore_api/gastrocore_api.dart';
import 'package:gastrocore_models/gastrocore_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Contract tests for the new endpoint groups. We do not assert on the full
/// request body — only on path, method, and the envelope of the response
/// DTO. That keeps the tests resilient to additive server-side changes while
/// still catching an endpoint that points at the wrong URL.

GastrocoreClient _client(MockClient mock) =>
    GastrocoreClient(baseUrl: 'https://example.test', httpClient: mock);

void main() {
  group('Client wires up every endpoint group', () {
    test('payments, staff, settings, reports, dashboard all present', () {
      final c = _client(MockClient((_) async => http.Response('{}', 200)));
      addTearDown(c.dispose);
      expect(c.payments, isA<PaymentEndpoint>());
      expect(c.staff, isA<StaffEndpoint>());
      expect(c.settings, isA<SettingsEndpoint>());
      expect(c.reports, isA<ReportEndpoint>());
      expect(c.dashboard, isA<DashboardEndpoint>());
    });
  });

  group('PaymentEndpoint', () {
    test('listMethods GETs /api/v1/payments/methods with tenant_id', () async {
      late http.BaseRequest seen;
      final c = _client(MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'data': []}), 200);
      }));
      addTearDown(c.dispose);

      final methods = await c.payments.listMethods('t1');
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/payments/methods');
      expect(seen.url.queryParameters['tenant_id'], 't1');
      expect(methods, isEmpty);
    });

    test('openBill POSTs to /api/v1/payments/bills', () async {
      late http.Request seen;
      final c = _client(MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'id': 'bill-1',
            'tenant_id': 't1',
            'ticket_id': 'tk-1',
            'bill_number': '001',
            'subtotal': 1000,
            'tax_amount': 81,
            'total': 1081,
            'status': 'open',
          }),
          200,
        );
      }));
      addTearDown(c.dispose);

      final bill = await c.payments.openBill(tenantId: 't1', ticketId: 'tk-1');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/payments/bills');
      expect(jsonDecode(seen.body)['ticket_id'], 'tk-1');
      expect(bill.id, 'bill-1');
      expect(bill.total, 1081);
    });
  });

  group('StaffEndpoint', () {
    test('listRoles GETs /api/v1/staff/roles', () async {
      late http.BaseRequest seen;
      final c = _client(MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'data': []}), 200);
      }));
      addTearDown(c.dispose);

      await c.staff.listRoles('t1');
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/staff/roles');
      expect(seen.url.queryParameters['tenant_id'], 't1');
    });

    test('setPin PUTs /api/v1/staff/users/{id}/pin', () async {
      late http.Request seen;
      final c = _client(MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      }));
      addTearDown(c.dispose);

      await c.staff.setPin(userId: 'u1', pin: '1234');
      expect(seen.method, 'PUT');
      expect(seen.url.path, '/api/v1/staff/users/u1/pin');
      expect(jsonDecode(seen.body)['pin'], '1234');
    });
  });

  group('SettingsEndpoint', () {
    test('getRestaurantSettings hydrates RestaurantSettings from bag',
        () async {
      final c = _client(MockClient((_) async {
        return http.Response(
          jsonEncode({
            'id': 'set-1',
            'tenant_id': 't1',
            'values': {
              SettingsKeys.gangsEnabled: {'type': 'bool', 'value': true},
              SettingsKeys.gangsMax: {'type': 'int', 'value': 4},
              SettingsKeys.gangsLabels: {
                'type': 'json',
                'value': ['Amuse', 'Entrée', 'Plat', 'Dessert'],
              },
            },
            'updated_at': '2026-04-17T00:00:00.000Z',
          }),
          200,
        );
      }));
      addTearDown(c.dispose);

      final s = await c.settings.getRestaurantSettings(tenantId: 't1');
      expect(s.gangsEnabled, isTrue);
      expect(s.maxGangs, 4);
      expect(s.gangLabels, ['Amuse', 'Entrée', 'Plat', 'Dessert']);
    });

    test('putRestaurantSettings PATCHes /api/v1/settings with typed keys',
        () async {
      late http.Request seen;
      final c = _client(MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'id': 'set-1',
            'tenant_id': 't1',
            'values': (req.body.isNotEmpty
                    ? jsonDecode(req.body)['values']
                    : <String, dynamic>{}) as Map<String, dynamic>,
            'updated_at': '2026-04-17T00:00:00.000Z',
          }),
          200,
        );
      }));
      addTearDown(c.dispose);

      final revived = await c.settings.putRestaurantSettings(
        tenantId: 't1',
        settings: const RestaurantSettings(
          gangsEnabled: false,
          maxGangs: 2,
          gangLabels: ['A', 'B'],
          serviceChargeEnabled: true,
          serviceChargePercent: 7.5,
        ),
      );
      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/api/v1/settings');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['tenant_id'], 't1');
      expect(body['values'], isA<Map>());
      expect(revived.gangsEnabled, isFalse);
      expect(revived.gangLabels, ['A', 'B']);
    });
  });

  group('ReportEndpoint', () {
    test('zReport GETs /api/v1/reports/z with from/to/tenant_id', () async {
      late http.BaseRequest seen;
      final c = _client(MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'tenant_id': 't1',
            'from': '2026-04-17T00:00:00.000Z',
            'to': '2026-04-17T23:59:59.000Z',
            'taxable_by_bucket': {'standard': 10000, 'reduced': 2000},
            'tax_by_bucket': {'standard': 810, 'reduced': 52},
            'payments_by_method': {'cash': 5000, 'creditCard': 7000},
            'gross_sales': 12000,
            'net_sales': 11138,
            'discounts_total': 0,
            'service_charge_total': 500,
            'tips_total': 300,
            'cash_count_expected': 5300,
            'ticket_count': 42,
          }),
          200,
        );
      }));
      addTearDown(c.dispose);

      final z = await c.reports.zReport(
        tenantId: 't1',
        from: DateTime.utc(2026, 4, 17),
        to: DateTime.utc(2026, 4, 17, 23, 59, 59),
      );
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/reports/z');
      expect(z.ticketCount, 42);
      expect(z.taxableByBucket[SwissMwstBucket.standard], 10000);
      expect(z.paymentsByMethod[PaymentMethod.creditCard], 7000);
    });
  });

  group('DashboardEndpoint', () {
    test('getLiveMetrics parses the snapshot DTO', () async {
      final c = _client(MockClient((_) async {
        return http.Response(
          jsonEncode({
            'tenant_id': 't1',
            'as_of': '2026-04-17T12:00:00.000Z',
            'open_ticket_count': 7,
            'today_ticket_count': 32,
            'today_revenue': 8820,
            'today_guest_count': 74,
            'active_staff_count': 4,
            'average_ticket': 27.56,
            'pending_kds_orders': 3,
          }),
          200,
        );
      }));
      addTearDown(c.dispose);

      final m = await c.dashboard.getLiveMetrics(tenantId: 't1');
      expect(m.openTicketCount, 7);
      expect(m.todayRevenue, 8820);
      expect(m.averageTicket, 27.56);
    });

    test('seatedGuestCount extracts { count: N }', () async {
      final c = _client(MockClient((_) async {
        return http.Response(jsonEncode({'count': 12}), 200);
      }));
      addTearDown(c.dispose);

      final count = await c.dashboard.seatedGuestCount(tenantId: 't1');
      expect(count, 12);
    });
  });
}
