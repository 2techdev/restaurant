import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/models.dart';
import '../../core/theme/app_theme.dart';
import 'orders_provider.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);
    final filters = ref.watch(orderFiltersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bestellungen', style: theme.textTheme.headlineMedium),
                    Text('Alle Bestellungen verwalten', style: theme.textTheme.bodyMedium),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('CSV Export'),
                  onPressed: () => _exportCsv(context, ordersAsync.valueOrNull ?? []),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Filters
            _FilterBar(filters: filters),
            const SizedBox(height: 16),

            // Table
            Expanded(
              child: Card(
                child: ordersAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 40, color: AppColors.error),
                        const SizedBox(height: 8),
                        Text(e.toString()),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => ref.invalidate(ordersProvider),
                          child: const Text('Erneut versuchen'),
                        ),
                      ],
                    ),
                  ),
                  data: (orders) => orders.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 48, color: theme.colorScheme.outline),
                              const SizedBox(height: 8),
                              Text('Keine Bestellungen', style: theme.textTheme.bodyLarge),
                            ],
                          ),
                        )
                      : _OrdersTable(orders: orders),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _exportCsv(BuildContext context, List<Order> orders) {
    final sb = StringBuffer();
    sb.writeln('Nummer,Status,Typ,Gesamt CHF,Zahlungsmethode,Kellner,Datum');
    for (final o in orders) {
      sb.writeln([
        o.orderNumber,
        _statusLabel(o.status),
        o.orderType,
        (o.total / 100).toStringAsFixed(2),
        o.paymentMethod ?? '-',
        o.waiterName ?? '-',
        o.createdAt,
      ].join(','));
    }
    // Web: copy to clipboard as fallback
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV in Zwischenablage kopiert')),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------

class _FilterBar extends ConsumerStatefulWidget {
  final OrderFilters filters;

  const _FilterBar({required this.filters});

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const statuses = [
      ('', 'Alle'),
      ('open', 'Offen'),
      ('preparing', 'In Zubereitung'),
      ('fully_paid', 'Bezahlt'),
      ('closed', 'Geschlossen'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Status filter
        ...statuses.map((s) {
          final selected = widget.filters.status == (s.$1.isEmpty ? null : s.$1);
          return FilterChip(
            label: Text(s.$2),
            selected: selected || (s.$1.isEmpty && widget.filters.status == null),
            onSelected: (_) => ref.read(orderFiltersProvider.notifier).update(
                  (f) => f.copyWith(
                    status: s.$1.isEmpty ? null : s.$1,
                    clearStatus: s.$1.isEmpty,
                  ),
                ),
          );
        }),

        const SizedBox(width: 8),

        // Date from
        SizedBox(
          width: 140,
          child: TextFormField(
            controller: _fromCtrl,
            decoration: const InputDecoration(
              labelText: 'Von',
              hintText: 'JJJJ-MM-TT',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) => ref.read(orderFiltersProvider.notifier).update(
                  (f) => f.copyWith(dateFrom: v.isEmpty ? null : v),
                ),
          ),
        ),
        SizedBox(
          width: 140,
          child: TextFormField(
            controller: _toCtrl,
            decoration: const InputDecoration(
              labelText: 'Bis',
              hintText: 'JJJJ-MM-TT',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) => ref.read(orderFiltersProvider.notifier).update(
                  (f) => f.copyWith(dateTo: v.isEmpty ? null : v),
                ),
          ),
        ),

        // Clear
        if (widget.filters.status != null || widget.filters.dateFrom != null)
          TextButton(
            onPressed: () {
              _fromCtrl.clear();
              _toCtrl.clear();
              ref.read(orderFiltersProvider.notifier).state = const OrderFilters();
            },
            child: const Text('Zurücksetzen'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Orders table
// ---------------------------------------------------------------------------

class _OrdersTable extends StatefulWidget {
  final List<Order> orders;

  const _OrdersTable({required this.orders});

  @override
  State<_OrdersTable> createState() => _OrdersTableState();
}

class _OrdersTableState extends State<_OrdersTable> {
  int _sortColumn = 0;
  bool _sortAsc = false;
  int _rowsPerPage = 15;
  int _currentPage = 0;

  List<Order> get _sorted {
    final sorted = [...widget.orders];
    sorted.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 0:
          cmp = a.orderNumber.compareTo(b.orderNumber);
        case 1:
          cmp = a.status.compareTo(b.status);
        case 2:
          cmp = a.orderType.compareTo(b.orderType);
        case 3:
          cmp = a.total.compareTo(b.total);
        case 4:
          cmp = a.createdAt.compareTo(b.createdAt);
        default:
          cmp = 0;
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final orders = _sorted;
    final totalPages = (orders.length / _rowsPerPage).ceil().clamp(1, 999);
    final page = _currentPage.clamp(0, totalPages - 1);
    final pageOrders = orders.skip(page * _rowsPerPage).take(_rowsPerPage).toList();
    final theme = Theme.of(context);

    void sort(int col) {
      setState(() {
        if (_sortColumn == col) {
          _sortAsc = !_sortAsc;
        } else {
          _sortColumn = col;
          _sortAsc = true;
        }
      });
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                sortColumnIndex: _sortColumn,
                sortAscending: _sortAsc,
                columnSpacing: 24,
                dataRowMaxHeight: 52,
                columns: [
                  DataColumn(label: const Text('Nummer'), numeric: true, onSort: (c, _) => sort(0)),
                  DataColumn(label: const Text('Status'), onSort: (c, _) => sort(1)),
                  DataColumn(label: const Text('Typ'), onSort: (c, _) => sort(2)),
                  DataColumn(label: const Text('Gesamt'), numeric: true, onSort: (c, _) => sort(3)),
                  DataColumn(label: const Text('Zahlung')),
                  DataColumn(label: const Text('Kellner')),
                  DataColumn(label: const Text('Datum/Zeit'), onSort: (c, _) => sort(4)),
                  const DataColumn(label: Text('')),
                ],
                rows: pageOrders.map((o) {
                  return DataRow(
                    cells: [
                      DataCell(Text('#${o.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(_StatusBadge(status: o.status)),
                      DataCell(Text(_typeLabel(o.orderType))),
                      DataCell(Text('CHF ${(o.total / 100).toStringAsFixed(2)}')),
                      DataCell(Text(o.paymentMethod ?? '-')),
                      DataCell(Text(o.waiterName ?? '-')),
                      DataCell(Text(_formatDate(o.createdAt))),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.open_in_new, size: 16),
                          onPressed: () => _showDetail(context, o),
                          tooltip: 'Details',
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),

        // Pagination
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${orders.length} Bestellungen',
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              DropdownButton<int>(
                value: _rowsPerPage,
                underline: const SizedBox.shrink(),
                items: [10, 15, 25, 50].map((n) => DropdownMenuItem(value: n, child: Text('$n / Seite'))).toList(),
                onChanged: (v) => setState(() {
                  _rowsPerPage = v!;
                  _currentPage = 0;
                }),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: page > 0 ? () => setState(() => _currentPage--) : null,
              ),
              Text('${page + 1} / $totalPages'),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: page < totalPages - 1 ? () => setState(() => _currentPage++) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDetail(BuildContext context, Order order) {
    showDialog(
      context: context,
      builder: (_) => _OrderDetailDialog(order: order),
    );
  }
}

// ---------------------------------------------------------------------------
// Order detail dialog
// ---------------------------------------------------------------------------

class _OrderDetailDialog extends StatelessWidget {
  final Order order;

  const _OrderDetailDialog({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Bestellung #${order.orderNumber}', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 4),
              _StatusBadge(status: order.status),
              const SizedBox(height: 20),
              _DetailRow('Typ', _typeLabel(order.orderType)),
              _DetailRow('Datum', _formatDate(order.createdAt)),
              if (order.waiterName != null) _DetailRow('Kellner', order.waiterName!),
              if (order.paymentMethod != null) _DetailRow('Zahlung', order.paymentMethod!),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Text('Artikel', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ...order.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Text('${item.quantity}×', style: theme.textTheme.bodyMedium),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.productName)),
                        Text('CHF ${(item.quantity * item.unitPrice / 100).toStringAsFixed(2)}'),
                      ],
                    ),
                  )),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  Text(
                    'CHF ${(order.total / 100).toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

(String, Color) _statusStyle(String status) => switch (status) {
      'fully_paid' => ('Bezahlt', AppColors.success),
      'open' => ('Offen', AppColors.primary),
      'preparing' || 'sent_to_kitchen' => ('In Zubereitung', AppColors.warning),
      'closed' => ('Geschlossen', Colors.grey),
      'cancelled' => ('Storniert', AppColors.error),
      _ => (status, Colors.grey),
    };

String _statusLabel(String status) => _statusStyle(status).$1;

String _typeLabel(String type) => switch (type) {
      'dine_in' => 'Im Restaurant',
      'takeaway' => 'Takeaway',
      _ => type,
    };

String _formatDate(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}
