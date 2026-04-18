/// Local DTOs for the Boss live dashboard.
///
/// TODO(boss-sprint2): replace with `gastrocore_models` versions once the
/// shared `LiveMetrics` / `TopProduct` types from commit a1e3fc0 land in
/// this branch.
library;

class LiveMetrics {
  final double todayRevenueChf;
  final int openTableCount;
  final int activeOrderCount;
  final int last15MinCovers;
  final List<TopProduct> top5;
  final DateTime asOf;

  const LiveMetrics({
    required this.todayRevenueChf,
    required this.openTableCount,
    required this.activeOrderCount,
    required this.last15MinCovers,
    required this.top5,
    required this.asOf,
  });

  factory LiveMetrics.empty() => LiveMetrics(
        todayRevenueChf: 0,
        openTableCount: 0,
        activeOrderCount: 0,
        last15MinCovers: 0,
        top5: const [],
        asOf: DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class TopProduct {
  final String name;
  final int quantity;
  final double revenueChf;

  const TopProduct({
    required this.name,
    required this.quantity,
    required this.revenueChf,
  });
}

class PaymentEvent {
  final double amountChf;
  final DateTime at;
  const PaymentEvent({required this.amountChf, required this.at});
}
