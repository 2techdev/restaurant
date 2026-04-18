import 'package:flutter_test/flutter_test.dart';
import 'package:gastrocore_printers/gastrocore_printers.dart';

PrinterConfig _cfg({
  required String id,
  required PrinterTarget target,
  bool backup = false,
  bool enabled = true,
}) =>
    PrinterConfig(
      id: id,
      storeId: 'store-1',
      target: target,
      name: 'Mock $id',
      ip: '192.168.1.${id.length}',
      port: 9100,
      enabled: enabled,
      isBackup: backup,
    );

KitchenTicketData _kitchen() => KitchenTicketData(
      ticketNumber: 'R-000001',
      tableLabel: 'Tisch 12',
      guestCount: 2,
      waiterName: 'Anna',
      firedAt: DateTime(2026, 4, 17, 19, 42),
      gangs: const [
        KitchenTicketGang(
          courseNumber: 1,
          label: 'Vorspeise',
          items: [
            KitchenTicketItem(name: 'Salat Niçoise', quantity: 2),
          ],
        ),
        KitchenTicketGang(
          courseNumber: 2,
          label: 'Hauptgang',
          items: [
            KitchenTicketItem(
              name: 'Entrecôte 300g',
              quantity: 1,
              modifierLines: ['+ medium-rare'],
              allergens: ['Milch'],
            ),
          ],
        ),
      ],
    );

ReceiptData _receipt() => ReceiptData(
      storeName: 'Zum Frohsinn',
      storeAddress: 'Bahnhofstrasse 1, 8001 Zürich',
      storePhone: '+41 44 123 45 67',
      vatNumber: 'CHE-123.456.789',
      ticketNumber: 'R-000001',
      tableLabel: 'Tisch 12',
      waiterName: 'Anna',
      guestCount: 2,
      issuedAt: DateTime(2026, 4, 17, 19, 42),
      items: const [
        ReceiptLineItem(
          name: 'Entrecôte 300g',
          quantity: 1,
          unitPriceCents: 5400,
          lineTotalCents: 5400,
        ),
      ],
      subtotalCents: 5400,
      grandTotalCents: 5400,
      taxLines: const [
        ReceiptTaxLine(
          label: 'MWST 8.1%',
          ratePercent: 8.1,
          netCents: 4995,
          taxCents: 405,
          grossCents: 5400,
        ),
      ],
      payments: const [
        ReceiptPayment(method: 'cash', amountCents: 6000, changeCents: 600),
      ],
      thankYouMessage: 'Danke für Ihren Besuch!',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MockPrinterService', () {
    test('captures kitchen ticket on primary printer', () async {
      final service = await MockPrinterService.create(configs: [
        _cfg(id: 'p1', target: PrinterTarget.kitchen),
      ]);

      final result = await service.printKitchenTicket(
        _kitchen(),
        target: PrinterTarget.kitchen,
      );

      expect(result.success, isTrue);
      expect(result.configId, 'p1');
      expect(service.printHistory, hasLength(1));
      expect(service.printHistory.first.kind, 'kitchen');
      expect(service.printHistory.first.bytes, isNotEmpty);
    });

    test('kitchen ticket bytes contain human-readable table + item text',
        () async {
      final service = await MockPrinterService.create(configs: [
        _cfg(id: 'p1', target: PrinterTarget.kitchen),
      ]);
      await service.printKitchenTicket(_kitchen(),
          target: PrinterTarget.kitchen);

      final text = service.printHistory.first.asciiText;
      expect(text, contains('Tisch 12'));
      expect(text, contains('Entrec')); // accented ô may be non-ASCII
      expect(text, contains('ALLERGEN'));
    });

    test('receipt template emits Swiss MWST line and grand total', () async {
      final service = await MockPrinterService.create(configs: [
        _cfg(id: 'p2', target: PrinterTarget.receipt),
      ]);

      final r = await service.printReceipt(_receipt());

      expect(r.success, isTrue);
      final text = service.printHistory.first.asciiText;
      expect(text, contains('MWST 8.1'));
      expect(text, contains('TOTAL CHF'));
    });

    test('falls back to backup when primary fails', () async {
      final service = await MockPrinterService.create(
        configs: [
          _cfg(id: 'primary', target: PrinterTarget.kitchen),
          _cfg(id: 'backup', target: PrinterTarget.kitchen, backup: true),
        ],
        failPrimary: true,
      );

      final r = await service.printKitchenTicket(_kitchen(),
          target: PrinterTarget.kitchen);

      expect(r.success, isTrue);
      expect(r.configId, 'backup');
    });

    test('returns failure when no enabled printer matches target', () async {
      final service = await MockPrinterService.create(configs: [
        _cfg(id: 'p', target: PrinterTarget.kitchen, enabled: false),
      ]);
      final r = await service.printKitchenTicket(_kitchen(),
          target: PrinterTarget.kitchen);
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('no_enabled_printer'));
    });

    test('statusAll reflects enabled/disabled flag', () async {
      final service = await MockPrinterService.create(configs: [
        _cfg(id: 'on', target: PrinterTarget.kitchen),
        _cfg(id: 'off', target: PrinterTarget.bar, enabled: false),
      ]);
      final statuses = await service.statusAll();
      expect(statuses, hasLength(2));
      expect(statuses.firstWhere((s) => s.configId == 'on').health,
          PrinterHealth.online);
      expect(statuses.firstWhere((s) => s.configId == 'off').health,
          PrinterHealth.offline);
    });
  });

  group('PrinterConfig JSON', () {
    test('round-trips', () {
      final c = PrinterConfig(
        id: 'prn_1',
        storeId: 'store-1',
        target: PrinterTarget.kitchen,
        name: 'K1',
        ip: '10.0.0.10',
        port: 9100,
      );
      final decoded = PrinterConfig.fromJson(c.toJson());
      expect(decoded.id, c.id);
      expect(decoded.target, c.target);
      expect(decoded.ip, c.ip);
      expect(decoded.port, c.port);
      expect(decoded.paperWidth, c.paperWidth);
    });

    test('rejects unknown target on fromJson', () {
      expect(
          () => PrinterConfig.fromJson({
                'id': 'x',
                'store_id': 's',
                'target': 'garbage',
                'name': 'n',
              }),
          throwsArgumentError);
    });
  });
}
