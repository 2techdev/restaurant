import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/models.dart';
import '../../core/auth/auth_provider.dart';

// Tab selection
final reportsTabProvider = StateProvider.autoDispose<int>((ref) => 0);

// Date range
class DateRange {
  final String from;
  final String to;

  const DateRange({required this.from, required this.to});

  static DateRange get lastMonth {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 29));
    return DateRange(
      from: fmt(from),
      to: fmt(now),
    );
  }

  static DateRange get thisMonth {
    final now = DateTime.now();
    return DateRange(
      from: '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
      to: fmt(now),
    );
  }

  static String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final reportsDateRangeProvider = StateProvider.autoDispose<DateRange>((ref) => DateRange.lastMonth);
final reportsGroupByProvider = StateProvider.autoDispose<String>((ref) => 'day');

final salesTimelineProvider = FutureProvider.autoDispose<List<SalesPoint>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final range = ref.watch(reportsDateRangeProvider);
  final groupBy = ref.watch(reportsGroupByProvider);
  return client.getSalesTimeline(from: range.from, to: range.to, groupBy: groupBy);
});

final mwstReportProvider = FutureProvider.autoDispose<MWSTReport>((ref) async {
  final client = ref.watch(apiClientProvider);
  final range = ref.watch(reportsDateRangeProvider);
  return client.getMWSTReport(from: range.from, to: range.to);
});
