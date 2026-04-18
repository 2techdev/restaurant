/// Riverpod providers for the Z-report screen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'zreport_models.dart';
import 'zreport_repository.dart';

final zReportRepositoryProvider = Provider<ZReportRepository>(
  (ref) => ZReportRepository(),
);

final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final zReportProvider = FutureProvider<ZReport>((ref) {
  final date = ref.watch(selectedDateProvider);
  return ref.watch(zReportRepositoryProvider).fetchZReport(date);
});
