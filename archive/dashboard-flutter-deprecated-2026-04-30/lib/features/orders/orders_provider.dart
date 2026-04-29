import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/models.dart';
import '../../core/auth/auth_provider.dart';

class OrderFilters {
  final String? status;
  final String? dateFrom;
  final String? dateTo;
  final String? paymentMethod;

  const OrderFilters({this.status, this.dateFrom, this.dateTo, this.paymentMethod});

  OrderFilters copyWith({
    String? status,
    String? dateFrom,
    String? dateTo,
    String? paymentMethod,
    bool clearStatus = false,
    bool clearPayment = false,
  }) =>
      OrderFilters(
        status: clearStatus ? null : status ?? this.status,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
        paymentMethod: clearPayment ? null : paymentMethod ?? this.paymentMethod,
      );
}

final orderFiltersProvider = StateProvider.autoDispose<OrderFilters>((ref) => const OrderFilters());

final ordersProvider = FutureProvider.autoDispose<List<Order>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final filters = ref.watch(orderFiltersProvider);
  return client.getOrders(
    status: filters.status,
    dateFrom: filters.dateFrom,
    dateTo: filters.dateTo,
  );
});
