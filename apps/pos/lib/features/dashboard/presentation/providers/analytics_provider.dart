/// Riverpod providers for the Analytics / Reporting screen.
library;

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/features/dashboard/data/repositories/analytics_repository.dart';
import 'package:gastrocore_pos/features/dashboard/domain/entities/analytics_report.dart';

// ---------------------------------------------------------------------------
// Date preset enum
// ---------------------------------------------------------------------------

enum AnalyticsPreset { today, thisWeek, thisMonth, custom }

// ---------------------------------------------------------------------------
// Selected date range value object
// ---------------------------------------------------------------------------

class AnalyticsDateState {
  final AnalyticsPreset preset;
  final DateRangeFilter filter;

  const AnalyticsDateState({required this.preset, required this.filter});

  static AnalyticsDateState forPreset(AnalyticsPreset preset,
      {DateTimeRange? custom}) {
    final now = DateTime.now();
    late DateTime start;
    late DateTime end;
    late String label;

    switch (preset) {
      case AnalyticsPreset.today:
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
        label = 'Bugün';
      case AnalyticsPreset.thisWeek:
        final weekday = now.weekday; // Mon=1, Sun=7
        start = DateTime(now.year, now.month, now.day - (weekday - 1));
        end = DateTime(now.year, now.month, now.day + 1);
        label = 'Bu Hafta';
      case AnalyticsPreset.thisMonth:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1);
        label = 'Bu Ay';
      case AnalyticsPreset.custom:
        if (custom == null) {
          start = DateTime(now.year, now.month, now.day);
          end = start.add(const Duration(days: 1));
          label = 'Özel';
        } else {
          start = DateTime(
              custom.start.year, custom.start.month, custom.start.day);
          end = DateTime(
              custom.end.year, custom.end.month, custom.end.day + 1);
          label = 'Özel';
        }
    }

    return AnalyticsDateState(
      preset: preset,
      filter: DateRangeFilter(start: start, end: end, label: label),
    );
  }
}

// ---------------------------------------------------------------------------
// Date range notifier
// ---------------------------------------------------------------------------

class AnalyticsDateNotifier extends StateNotifier<AnalyticsDateState> {
  AnalyticsDateNotifier()
      : super(AnalyticsDateState.forPreset(AnalyticsPreset.today));

  void select(AnalyticsPreset preset, {DateTimeRange? custom}) {
    state = AnalyticsDateState.forPreset(preset, custom: custom);
  }
}

final analyticsDateProvider =
    StateNotifierProvider.autoDispose<AnalyticsDateNotifier, AnalyticsDateState>(
  (ref) => AnalyticsDateNotifier(),
);

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(databaseProvider));
});

// ---------------------------------------------------------------------------
// Report provider – re-fetches whenever date range changes
// ---------------------------------------------------------------------------

final analyticsReportProvider =
    FutureProvider.autoDispose<AnalyticsReport>((ref) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  final tenantId = ref.watch(tenantIdProvider);
  final dateState = ref.watch(analyticsDateProvider);
  return repo.getReport(tenantId, dateState.filter);
});
