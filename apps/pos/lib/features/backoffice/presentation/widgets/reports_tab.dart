/// Reports tab for the Back Office screen.
///
/// Read-only local data reports: total sales, orders, average order value,
/// sales by category, top products, payment breakdown, and hourly sales.
/// All data sourced from local SQLite via Drift raw queries.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/database/app_database.dart';

// ---------------------------------------------------------------------------
// Report data models
// ---------------------------------------------------------------------------

class _ReportData {
  final int totalSales; // cents
  final int totalOrders;
  final int totalItemsSold;
  final List<_CategorySales> salesByCategory;
  final List<_TopProduct> topProducts;
  final List<_PaymentBreakdown> paymentBreakdown;
  final List<_HourlySales> hourlySales;

  const _ReportData({
    required this.totalSales,
    required this.totalOrders,
    required this.totalItemsSold,
    required this.salesByCategory,
    required this.topProducts,
    required this.paymentBreakdown,
    required this.hourlySales,
  });

  double get averageOrderValue =>
      totalOrders > 0 ? totalSales / totalOrders : 0;
}

class _CategorySales {
  final String categoryName;
  final int total; // cents
  const _CategorySales(this.categoryName, this.total);
}

class _TopProduct {
  final String name;
  final int quantity;
  final int revenue; // cents
  const _TopProduct(this.name, this.quantity, this.revenue);
}

class _PaymentBreakdown {
  final String method;
  final int count;
  final int total; // cents
  const _PaymentBreakdown(this.method, this.count, this.total);
}

class _HourlySales {
  final int hour;
  final int total; // cents
  const _HourlySales(this.hour, this.total);
}

// ---------------------------------------------------------------------------
// Date range enum
// ---------------------------------------------------------------------------

enum _DateRange { today, thisWeek, thisMonth, custom }

// ---------------------------------------------------------------------------
// ReportsTab
// ---------------------------------------------------------------------------

class ReportsTab extends ConsumerStatefulWidget {
  const ReportsTab({super.key});

  @override
  ConsumerState<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<ReportsTab> {
  _DateRange _selectedRange = _DateRange.today;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  _ReportData? _reportData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _updateDateRange(_DateRange.today);
  }

  void _updateDateRange(_DateRange range) {
    final now = DateTime.now();
    setState(() {
      _selectedRange = range;
      switch (range) {
        case _DateRange.today:
          _startDate = DateTime(now.year, now.month, now.day);
          _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        case _DateRange.thisWeek:
          final weekday = now.weekday;
          _startDate = DateTime(now.year, now.month, now.day - (weekday - 1));
          _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        case _DateRange.thisMonth:
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        case _DateRange.custom:
          // Keep existing dates
          break;
      }
    });
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);

    try {
      final db = ref.read(databaseProvider);
      final tenantId = ref.read(tenantIdProvider);
      final data = await _fetchReportData(db, tenantId);
      if (mounted) {
        setState(() {
          _reportData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<_ReportData> _fetchReportData(
    AppDatabase db,
    String tenantId,
  ) async {
    final start = _startDate;
    final end = _endDate;

    // Total sales & orders from closed tickets
    final ticketQuery = db.select(db.tickets)
      ..where((t) =>
          t.tenantId.equals(tenantId) &
          t.isDeleted.equals(false) &
          t.createdAt.isBiggerOrEqualValue(start) &
          t.createdAt.isSmallerOrEqualValue(end) &
          (t.status.equals('closed') | t.status.equals('fully_paid')));
    final tickets = await ticketQuery.get();

    final totalSales = tickets.fold<int>(0, (sum, t) => sum + t.total);
    final totalOrders = tickets.length;

    // Order items for date range
    final ticketIds = tickets.map((t) => t.id).toList();
    List<OrderItem> orderItems = [];
    if (ticketIds.isNotEmpty) {
      final oiQuery = db.select(db.orderItems)
        ..where((oi) =>
            oi.ticketId.isIn(ticketIds) &
            oi.isDeleted.equals(false) &
            oi.status.isNotIn(const ['void']));
      orderItems = await oiQuery.get();
    }

    final totalItemsSold =
        orderItems.fold<int>(0, (sum, oi) => sum + oi.quantity.round());

    // Sales by category (join products to get category)
    final categoryMap = <String, int>{};
    for (final oi in orderItems) {
      // Look up category name via product
      final prodQuery = db.select(db.products)
        ..where((p) => p.id.equals(oi.productId));
      final prod = await prodQuery.getSingleOrNull();
      if (prod != null) {
        final catQuery = db.select(db.categories)
          ..where((c) => c.id.equals(prod.categoryId));
        final cat = await catQuery.getSingleOrNull();
        final catName = cat?.name ?? 'Bilinmeyen';
        categoryMap[catName] = (categoryMap[catName] ?? 0) + oi.subtotal;
      }
    }
    final salesByCategory = categoryMap.entries
        .map((e) => _CategorySales(e.key, e.value))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    // Top 10 products
    final productMap = <String, _TopProduct>{};
    for (final oi in orderItems) {
      final existing = productMap[oi.productName];
      if (existing != null) {
        productMap[oi.productName] = _TopProduct(
          oi.productName,
          existing.quantity + oi.quantity.round(),
          existing.revenue + oi.subtotal,
        );
      } else {
        productMap[oi.productName] = _TopProduct(
          oi.productName,
          oi.quantity.round(),
          oi.subtotal,
        );
      }
    }
    final topProducts = productMap.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    // Payment breakdown
    List<Payment> payments = [];
    if (ticketIds.isNotEmpty) {
      final payQuery = db.select(db.payments)
        ..where((p) =>
            p.ticketId.isIn(ticketIds) & p.isDeleted.equals(false));
      payments = await payQuery.get();
    }

    final paymentMethodMap = <String, ({int count, int total})>{};
    for (final p in payments) {
      final existing = paymentMethodMap[p.paymentMethod];
      if (existing != null) {
        paymentMethodMap[p.paymentMethod] = (
          count: existing.count + 1,
          total: existing.total + p.amount,
        );
      } else {
        paymentMethodMap[p.paymentMethod] = (count: 1, total: p.amount);
      }
    }
    final paymentBreakdown = paymentMethodMap.entries
        .map((e) => _PaymentBreakdown(e.key, e.value.count, e.value.total))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    // Hourly sales
    final hourlyMap = <int, int>{};
    for (final t in tickets) {
      final hour = t.createdAt.hour;
      hourlyMap[hour] = (hourlyMap[hour] ?? 0) + t.total;
    }
    final hourlySales = List.generate(24, (h) {
      return _HourlySales(h, hourlyMap[h] ?? 0);
    });

    return _ReportData(
      totalSales: totalSales,
      totalOrders: totalOrders,
      totalItemsSold: totalItemsSold,
      salesByCategory: salesByCategory,
      topProducts: topProducts.take(10).toList(),
      paymentBreakdown: paymentBreakdown,
      hourlySales: hourlySales,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date range selector
          _buildDateSelector(),
          const SizedBox(height: 20),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  )
                : _reportData == null
                    ? const Center(
                        child: Text(
                          'Rapor yuklenemedi',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 14),
                        ),
                      )
                    : _buildReportContent(_reportData!),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Date selector
  // =========================================================================

  Widget _buildDateSelector() {
    return Row(
      children: [
        _dateChip('Bugun', _DateRange.today),
        const SizedBox(width: 8),
        _dateChip('Bu Hafta', _DateRange.thisWeek),
        const SizedBox(width: 8),
        _dateChip('Bu Ay', _DateRange.thisMonth),
      ],
    );
  }

  Widget _dateChip(String label, _DateRange range) {
    final isSelected = _selectedRange == range;
    return GestureDetector(
      onTap: () => _updateDateRange(range),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentDim : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // Report content
  // =========================================================================

  Widget _buildReportContent(_ReportData data) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats cards
          _buildStatsRow(data),
          const SizedBox(height: 24),

          // Two-column layout for charts
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Kategoriye Gore Satis'),
                    const SizedBox(height: 12),
                    _buildCategoryBars(data.salesByCategory),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Odeme Yontemi'),
                    const SizedBox(height: 12),
                    _buildPaymentList(data.paymentBreakdown),
                  ],
                ),
              ),
              const SizedBox(width: 24),

              // Right column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('En Cok Satan 10 Urun'),
                    const SizedBox(height: 12),
                    _buildTopProductsList(data.topProducts),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Saatlik Satis'),
                    const SizedBox(height: 12),
                    _buildHourlyChart(data.hourlySales),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Stats row
  // =========================================================================

  Widget _buildStatsRow(_ReportData data) {
    return Row(
      children: [
        _buildStatCard(
          'Toplam Satis',
          'CHF ${(data.totalSales / 100).toStringAsFixed(2)}',
          AppColors.green,
          Icons.trending_up_rounded,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          'Toplam Siparis',
          '${data.totalOrders}',
          AppColors.primary,
          Icons.receipt_long_rounded,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          'Ort. Siparis',
          'CHF ${(data.averageOrderValue / 100).toStringAsFixed(2)}',
          AppColors.orange,
          Icons.analytics_rounded,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          'Satilan Urun',
          '${data.totalItemsSold}',
          AppColors.purple,
          Icons.inventory_2_rounded,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Section title
  // =========================================================================

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }

  // =========================================================================
  // Category bars
  // =========================================================================

  Widget _buildCategoryBars(List<_CategorySales> categories) {
    if (categories.isEmpty) {
      return _emptyState('Veri yok');
    }

    final maxVal =
        categories.fold<int>(0, (m, c) => math.max(m, c.total));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: categories.map((cat) {
          final fraction = maxVal > 0 ? cat.total / maxVal : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    cat.categoryName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          Container(
                            height: 24,
                            width: constraints.maxWidth * fraction,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primaryContainer
                                ],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: Text(
                    'CHF ${(cat.total / 100).toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // =========================================================================
  // Top products list
  // =========================================================================

  Widget _buildTopProductsList(List<_TopProduct> products) {
    if (products.isEmpty) {
      return _emptyState('Veri yok');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < products.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  // Rank
                  SizedBox(
                    width: 28,
                    child: Text(
                      '#${i + 1}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: i < 3 ? AppColors.orange : AppColors.textDim,
                      ),
                    ),
                  ),
                  // Name
                  Expanded(
                    child: Text(
                      products[i].name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Qty
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${products[i].quantity}x',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Revenue
                  SizedBox(
                    width: 80,
                    child: Text(
                      'CHF ${(products[i].revenue / 100).toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================================
  // Payment breakdown
  // =========================================================================

  Widget _buildPaymentList(List<_PaymentBreakdown> payments) {
    if (payments.isEmpty) {
      return _emptyState('Veri yok');
    }

    final methodLabels = {
      'cash': 'Nakit',
      'credit_card': 'Kredi Karti',
      'debit_card': 'Banka Karti',
      'other': 'Diger',
    };

    final methodIcons = {
      'cash': Icons.payments_rounded,
      'credit_card': Icons.credit_card_rounded,
      'debit_card': Icons.credit_card_rounded,
      'other': Icons.more_horiz_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: payments.map((p) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  methodIcons[p.method] ?? Icons.payment_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    methodLabels[p.method] ?? p.method,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${p.count}x',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: Text(
                    'CHF ${(p.total / 100).toStringAsFixed(0)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // =========================================================================
  // Hourly sales chart (custom painted)
  // =========================================================================

  Widget _buildHourlyChart(List<_HourlySales> hourly) {
    // Filter to show only hours with data or typical restaurant hours (8-24)
    final displayHours =
        hourly.where((h) => h.hour >= 8 && h.hour <= 23).toList();
    final maxVal =
        displayHours.fold<int>(0, (m, h) => math.max(m, h.total));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        height: 160,
        child: CustomPaint(
          size: const Size(double.infinity, 160),
          painter: _HourlyBarPainter(
            data: displayHours,
            maxValue: maxVal,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String text) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textDim,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom painter for hourly bar chart
// ---------------------------------------------------------------------------

class _HourlyBarPainter extends CustomPainter {
  final List<_HourlySales> data;
  final int maxValue;

  _HourlyBarPainter({required this.data, required this.maxValue});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || maxValue == 0) return;

    final barWidth = (size.width - 40) / data.length - 4;
    final chartHeight = size.height - 30; // leave room for labels
    final barPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [AppColors.primaryContainer, AppColors.primary],
      ).createShader(Rect.fromLTWH(0, 0, barWidth, chartHeight));

    final labelStyle = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w500,
      color: AppColors.textDim.toARGB32() == 0xFF5A5A6A
          ? const Color(0xFF5A5A6A)
          : AppColors.textDim,
    );

    for (int i = 0; i < data.length; i++) {
      final x = 20 + i * (barWidth + 4);
      final fraction = data[i].total / maxValue;
      final barHeight = chartHeight * fraction;

      // Bar
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, chartHeight - barHeight, barWidth, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(barRect, barPaint);

      // Hour label
      final textSpan = TextSpan(text: '${data[i].hour}', style: labelStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(x + (barWidth - textPainter.width) / 2, chartHeight + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyBarPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.maxValue != maxValue;
  }
}
