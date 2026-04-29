/// Unit tests for the Swiss MWST fiscal export service.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/fiscal_ch/domain/swiss_mwst_export.dart';
import 'package:gastrocore_pos/features/reports/domain/entities/report_entities.dart';

ReportSnapshot _fixture() => ReportSnapshot(
      fromTs: DateTime(2026, 4, 22),
      toTs: DateTime(2026, 4, 23),
      ticketCount: 12,
      grossTotalCents: 120000,
      netTotalCents: 110400,
      taxTotalCents: 9600,
      discountTotalCents: 0,
      giftTotalCents: 0,
      tipTotalCents: 2400,
      voidCount: 1,
      mwstBuckets: const [
        MwstBucket(
          rateBps: 810,
          grossCents: 80000,
          netCents: 73993,
          taxCents: 6007,
        ),
        MwstBucket(
          rateBps: 260,
          grossCents: 40000,
          netCents: 38985,
          taxCents: 1015,
        ),
      ],
      payments: const [
        PaymentBreakdownEntry(method: 'cash', totalCents: 60000, count: 6),
        PaymentBreakdownEntry(
            method: 'credit_card', totalCents: 60000, count: 6),
      ],
      topProducts: const [],
      categories: const [],
      hourly: const [
        HourlyBreakdownEntry(hour: 12, ticketCount: 5, revenueCents: 50000),
        HourlyBreakdownEntry(hour: 13, ticketCount: 7, revenueCents: 70000),
      ],
    );

SwissFiscalMeta _meta() => const SwissFiscalMeta(
      tenantId: 'tenant-1',
      restaurantName: 'Gastro Test AG',
      mwstNumber: 'CHE-123.456.789 MWST',
      address: 'Bahnhofstrasse 1, 8001 Zürich',
    );

void main() {
  group('SwissMwstExportService.export', () {
    test('produces CSV with BOM + header + totals row', () {
      final result = const SwissMwstExportService().export(
        snapshot: _fixture(),
        meta: _meta(),
        generatedAt: DateTime(2026, 4, 22, 22, 0),
      );
      final csv = result.csv;
      expect(csv.codeUnitAt(0), 0xFEFF, reason: 'BOM must be first byte');
      expect(csv, contains('# Betrieb: Gastro Test AG'));
      expect(csv, contains('# MWST-Nr: CHE-123.456.789 MWST'));
      expect(csv, contains('MwSt-Satz-%,Brutto_CHF,Netto_CHF,MwSt_CHF'));
      expect(csv, contains('# TOTAL | 12 Belege'));
      expect(csv, contains('#SUMMARY_START'));
      expect(csv, contains('#SUMMARY_END'));
    });

    test('CSV sorts MWST rates ascending by rate basis points', () {
      final result = const SwissMwstExportService()
          .export(snapshot: _fixture(), meta: _meta());
      final lines = result.csv.split('\n');
      final idx260 =
          lines.indexWhere((l) => l.startsWith('2.60,'));
      final idx810 =
          lines.indexWhere((l) => l.startsWith('8.10,'));
      expect(idx260, isNonNegative);
      expect(idx810, isNonNegative);
      expect(idx260, lessThan(idx810),
          reason: 'lower rate 2.6% must appear before 8.1%');
    });

    test('empty MWST number renders as "—" in CSV', () {
      final noVat = const SwissFiscalMeta(
        tenantId: 't',
        restaurantName: 'Trial',
        mwstNumber: '',
      );
      final result = const SwissMwstExportService()
          .export(snapshot: _fixture(), meta: noVat);
      expect(result.csv, contains('# MWST-Nr: —'));
    });

    test('JSON is well-formed, schema-tagged, and mirrors totals', () {
      final result = const SwissMwstExportService().export(
        snapshot: _fixture(),
        meta: _meta(),
        generatedAt: DateTime(2026, 4, 22, 22, 0),
      );
      final parsed = jsonDecode(result.json) as Map<String, dynamic>;
      expect(parsed['schema'], 'ch.mwst.export.v1');
      final meta = parsed['meta'] as Map<String, dynamic>;
      expect(meta['tenantId'], 'tenant-1');
      expect(meta['mwstNumber'], 'CHE-123.456.789 MWST');
      final totals = parsed['totals'] as Map<String, dynamic>;
      expect(totals['ticketCount'], 12);
      expect(totals['grossCents'], 120000);
      expect(totals['netCents'], 110400);
      expect(totals['taxCents'], 9600);
      expect(totals['tipCents'], 2400);
      final buckets = parsed['mwstBuckets'] as List<dynamic>;
      expect(buckets.length, 2);
      // Ascending order by rate.
      expect((buckets.first as Map)['rateBps'], 260);
      expect((buckets.last as Map)['rateBps'], 810);
    });

    test('filename base uses single date for same-day windows', () {
      final result = const SwissMwstExportService()
          .export(snapshot: _fixture(), meta: _meta());
      // Window is 22.04 00:00 → 23.04 00:00 (same business day).
      expect(result.filenameBase, 'mwst-export_2026-04-22');
    });

    test('filename base uses range for multi-day windows', () {
      final multi = ReportSnapshot(
        fromTs: DateTime(2026, 4, 1),
        toTs: DateTime(2026, 5, 1),
        ticketCount: 0,
        grossTotalCents: 0,
        netTotalCents: 0,
        taxTotalCents: 0,
        discountTotalCents: 0,
        giftTotalCents: 0,
        tipTotalCents: 0,
        voidCount: 0,
        mwstBuckets: const [],
        payments: const [],
        topProducts: const [],
        categories: const [],
        hourly: const [],
      );
      final result = const SwissMwstExportService()
          .export(snapshot: multi, meta: _meta());
      expect(result.filenameBase, 'mwst-export_2026-04-01_2026-04-30');
    });

    test('name with comma is quoted in CSV header', () {
      final meta = const SwissFiscalMeta(
        tenantId: 't',
        restaurantName: 'Gastro AG, Zürich',
        mwstNumber: 'CHE-111.222.333 MWST',
      );
      final result = const SwissMwstExportService()
          .export(snapshot: _fixture(), meta: meta);
      expect(result.csv, contains('# Betrieb: "Gastro AG, Zürich"'));
    });
  });
}
