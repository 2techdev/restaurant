/// Receipt Preview Screen for GastroCore POS.
///
/// Displays a thermal-receipt-style preview on a dark background.
/// White receipt card simulates thermal paper output.
/// Follows Stitch S06 design reference.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/printing/models/print_models.dart';
import 'package:gastrocore_pos/core/printing/providers/print_use_case_provider.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/orders/domain/calculations/calculation_pipeline.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

// ---------------------------------------------------------------------------
// Receipt Preview Screen
// ---------------------------------------------------------------------------

class ReceiptPreviewScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const ReceiptPreviewScreen({super.key, required this.ticketId});

  @override
  ConsumerState<ReceiptPreviewScreen> createState() =>
      _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends ConsumerState<ReceiptPreviewScreen> {
  /// Cached ticket — updated whenever the async provider emits a new value.
  TicketEntity? _ticket;

  String _formatCents(int cents) {
    final isNeg = cents < 0;
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    final wholeStr = whole.toString();
    final parts = <String>[];
    for (var i = wholeStr.length; i > 0; i -= 3) {
      final start = i - 3 < 0 ? 0 : i - 3;
      parts.insert(0, wholeStr.substring(start, i));
    }
    return '${isNeg ? '-' : ''}${parts.join(',')}.$frac';
  }

  String _formatDateTime(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    return '$d  $t';
  }

  /// Build [SwissReceiptData] from the real ticket for printing.
  SwissReceiptData _buildReceiptData(TicketEntity ticket) {
    final isDineIn = ticket.orderType == OrderType.dineIn;

    final receiptItems = ticket.items.map((item) {
      return SwissReceiptItem(
        name: item.productName,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        totalPrice: item.subtotal,
        mwstCode: MwStCode.forProduct(
          taxGroup: item.taxGroup,
          isDineIn: isDineIn,
        ),
        modifiers: item.modifiers.map((m) => m.modifierName).toList(),
        notes: item.notes,
      );
    }).toList();

    // Per-MwSt-bucket subtotal, feeding the SambaPOS-style pipeline
    // (Discount → Service → Tax → Rounding). The pipeline apportions
    // discount + service across buckets before extracting MwSt so the
    // printed breakdown matches what the customer actually paid.
    final subtotalByMwst = <String, int>{};
    for (final item in ticket.items) {
      final code = MwStCode.forProduct(
        taxGroup: item.taxGroup,
        isDineIn: isDineIn,
      ).code;
      subtotalByMwst[code] = (subtotalByMwst[code] ?? 0) + item.subtotal;
    }
    final pipeline = runCalculationPipeline(
      PipelineInput(
        subtotalByMwst: subtotalByMwst,
        discountAmount: ticket.discountAmount,
        serviceAmount: ticket.serviceFeeAmount,
        // Receipt screen consumes TicketEntity.total which already
        // embeds its own rounding policy — skip 5-Rappen here to
        // avoid double-rounding the printed breakdown.
        applyRounding: false,
      ),
    );
    final breakdown = Map<String, int>.from(pipeline.taxableBaseByCode);

    final tenant = ref.read(tenantInfoProvider).valueOrNull;
    final restaurantName = tenant?.name ?? 'GastroCore Restaurant';
    final address = tenant?.address ?? '';
    final phone = tenant?.phone != null ? 'Tel: ${tenant!.phone}' : '';

    return SwissReceiptData(
      restaurantName: restaurantName.toUpperCase(),
      address: address,
      phone: phone,
      receiptNo: ticket.orderNumber,
      dateTime: ticket.openedAt,
      cashierName: ticket.cashierName,
      tableName: ticket.tableId,
      orderNo: ticket.orderNumber,
      orderTypeLabel: isDineIn ? 'Hier essen' : 'Zum Mitnehmen',
      items: receiptItems,
      total: ticket.total,
      subtotal: ticket.subtotal,
      discountAmount: ticket.discountAmount,
      serviceChargeAmount: ticket.serviceFeeAmount,
      mwstBreakdown: breakdown,
      footerText: 'Afiyet Olsun! · Merci de votre visite!',
      openDrawer: false,
    );
  }

  Future<void> _onPrint() async {
    final ticket = _ticket;
    if (ticket == null) return;
    final useCase = ref.read(printReceiptUseCaseProvider);
    await useCase(_buildReceiptData(ticket));
  }

  Future<void> _onShare() async {
    final ticket = _ticket;
    if (ticket == null) return;
    final data = _buildReceiptData(ticket);
    final text = _buildShareText(data);
    await Share.share(
      text,
      subject: '${data.restaurantName} - Fiş #${data.receiptNo}',
    );
  }

  String _buildShareText(SwissReceiptData data) {
    const w = 42;
    final lines = <String>[];

    // Header
    final name = data.restaurantName;
    lines.add(name.padLeft((w + name.length) ~/ 2));
    if (data.address != null && data.address!.isNotEmpty) {
      lines.add(data.address!);
    }
    if (data.phone != null && data.phone!.isNotEmpty) lines.add(data.phone!);
    lines.add('-' * w);

    // Meta
    if (data.dateTime != null) {
      lines.add('Tarih: ${_formatDateTime(data.dateTime!)}');
    }
    if (data.cashierName != null) lines.add('Kasiyer: ${data.cashierName}');
    if (data.tableName != null) lines.add('Masa:    ${data.tableName}');
    if (data.orderTypeLabel != null) lines.add(data.orderTypeLabel!);
    lines.add('=' * w);

    // Items
    for (final item in data.items) {
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(1);
      final label = '$qty x ${item.name}';
      final price = 'CHF ${_formatCents(item.totalPrice)}';
      final pad = w - label.length - price.length;
      lines.add('$label${' ' * (pad > 1 ? pad : 1)}$price');
      for (final m in item.modifiers) {
        lines.add('  + $m');
      }
      if (item.notes != null) lines.add('  * ${item.notes}');
    }

    lines.add('-' * w);
    if (data.discountAmount != 0) {
      lines.add('İndirim:  -CHF ${_formatCents(data.discountAmount)}');
    }
    if (data.serviceChargeAmount != 0) {
      lines.add('Servis:   CHF ${_formatCents(data.serviceChargeAmount)}');
    }
    final totalLabel = 'TOPLAM';
    final totalPrice = 'CHF ${_formatCents(data.total)}';
    final totalPad = w - totalLabel.length - totalPrice.length;
    lines.add('$totalLabel${' ' * (totalPad > 1 ? totalPad : 1)}$totalPrice');
    lines.add('=' * w);

    if (data.footerText != null) lines.add(data.footerText!);
    lines.add('Fiş No: ${data.receiptNo}');

    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    // Keep _ticket in sync with the database.
    ref.listen(ticketByIdProvider(widget.ticketId), (_, next) {
      next.whenData((t) {
        if (t != null && mounted) setState(() => _ticket = t);
      });
    });

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _ticket == null
                ? const Center(child: CircularProgressIndicator())
                : _buildReceiptArea(_ticket!),
          ),
          _buildBottomActions(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top navigation bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar() {
    // Kitchen / Inventory tabs removed — those features are not part of the
    // pilot POS scope and should not surface Pro-upgrade gates.
    const tabs = ['Dashboard', 'Tables', 'Orders', 'Reports'];
    const activeTab = 'Orders';

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surface,
      child: Row(
        children: [
          // Logo
          const Text(
            'Precision',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textDim,
              letterSpacing: -0.3,
            ),
          ),
          const Text(
            '.POS',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 24),

          // Tabs
          for (final tab in tabs) ...[
            GestureDetector(
              onTap: () {
                if (tab == 'Tables') context.go('/tables');
                if (tab == 'Orders') context.go('/order-center');
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: tab == activeTab
                      ? AppColors.accentDim
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tab,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        tab == activeTab ? FontWeight.w600 : FontWeight.w400,
                    color: tab == activeTab
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],

          const Spacer(),

          // Search icon
          GestureDetector(
            onTap: () => context.go('/order-center'),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Receipt area — rendered from real ticket data
  // -------------------------------------------------------------------------

  Widget _buildReceiptArea(TicketEntity ticket) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Container(
          width: 380,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFF8), // warm white paper tint
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.08),
                blurRadius: 40,
                spreadRadius: 8,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Restaurant name — from live tenant record
                Consumer(builder: (context, ref, _) {
                  final tenant =
                      ref.watch(tenantInfoProvider).valueOrNull;
                  final name = tenant?.name ?? 'GastroCore Restaurant';
                  return Text(
                    name.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                      letterSpacing: 1.5,
                    ),
                  );
                }),
                const SizedBox(height: 4),

                // Address — from tenant record
                Consumer(builder: (context, ref, _) {
                  final tenant =
                      ref.watch(tenantInfoProvider).valueOrNull;
                  final address = tenant?.address;
                  if (address == null || address.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    address,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF555555)),
                  );
                }),
                const SizedBox(height: 2),

                // Phone — from tenant record
                Consumer(builder: (context, ref, _) {
                  final tenant =
                      ref.watch(tenantInfoProvider).valueOrNull;
                  final phone = tenant?.phone;
                  if (phone == null || phone.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    'Tel: $phone',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF555555)),
                  );
                }),
                const SizedBox(height: 12),

                _buildDashedDivider(),
                const SizedBox(height: 10),

                // Date / Receipt #
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDateTime(ticket.openedAt),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF333333)),
                    ),
                    Text(
                      'Fis No: #${ticket.orderNumber}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Waiter + Table
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      ticket.cashierName != null
                          ? 'Bedient: ${ticket.cashierName}'
                          : '',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF555555)),
                    ),
                    Text(
                      ticket.tableId != null ? 'Masa ${ticket.tableId}' : '',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF555555)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                _buildDashedDivider(),
                const SizedBox(height: 10),

                // Column headers
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Urun Adi',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    Text(
                      'Tutar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Real order items
                for (final item in ticket.items) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.quantity.ceil()}x ${item.productName}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                            Text(
                              'CHF ${_formatCents(item.subtotal)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1A1A1A),
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        if (item.modifiers.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 14, top: 2),
                            child: Text(
                              item.modifiers.map((m) => m.modifierName).join(', '),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF777777),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        if (item.notes != null && item.notes!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 14, top: 1),
                            child: Text(
                              '* ${item.notes}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF777777),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                _buildDashedDivider(),
                const SizedBox(height: 10),

                // Subtotal
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Ara Toplam',
                      style: TextStyle(fontSize: 12, color: Color(0xFF555555)),
                    ),
                    Text(
                      'CHF${_formatCents(ticket.subtotal)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF333333),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Tax (inclusive — informational)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'KDV (dahil)',
                      style: TextStyle(fontSize: 12, color: Color(0xFF555555)),
                    ),
                    Text(
                      'CHF${_formatCents(ticket.taxAmount)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF333333),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),

                // Discount (if any)
                if (ticket.discountAmount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Indirim',
                        style: TextStyle(fontSize: 12, color: Color(0xFF555555)),
                      ),
                      Text(
                        '-CHF ${_formatCents(ticket.discountAmount)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF333333),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],

                // Service charge (if any) — dedicated line per
                // SambaPOS Discount → Service → Tax pipeline.
                if (ticket.serviceFeeAmount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Servis',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF555555)),
                      ),
                      Text(
                        'CHF ${_formatCents(ticket.serviceFeeAmount)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF333333),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                _buildDashedDivider(),
                const SizedBox(height: 10),

                // Grand total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOPLAM',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      'CHF${_formatCents(ticket.total)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _buildDashedDivider(),
                const SizedBox(height: 16),

                // Thank you message
                const Text(
                  'Afiyet Olsun!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 16),

                // QR code placeholder
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        size: 48,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Footer
                const Text(
                  'GastroCore v0.1.0 | Powered by GastroCore',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashedDivider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashCount =
            (constraints.maxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(dashCount, (_) {
            return Container(
              width: dashWidth,
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: dashSpace / 2),
              color: const Color(0xFFCCCCCC),
            );
          }),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Bottom action bar
  // -------------------------------------------------------------------------

  Widget _buildBottomActions() {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surface,
      child: Row(
        children: [
          const Spacer(),

          // Print button — wired to PrinterService via use case
          GestureDetector(
            onTap: _onPrint,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryContainer],
                  begin: Alignment(-0.7, -0.7),
                  end: Alignment(0.7, 0.7),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.print_rounded,
                      size: 18, color: Color(0xFF0D1B3A)),
                  SizedBox(width: 8),
                  Text(
                    'Yazdir',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D1B3A),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Email button (secondary)
          GestureDetector(
            onTap: _onShare,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.email_outlined,
                      size: 18, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Text(
                    'E-Posta',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Close button (ghost)
          GestureDetector(
            onTap: () => context.go('/order-center'),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded,
                      size: 18, color: AppColors.textDim),
                  SizedBox(width: 6),
                  Text(
                    'Kapat',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
