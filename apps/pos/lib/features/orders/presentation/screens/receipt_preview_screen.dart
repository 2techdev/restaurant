/// Receipt Preview Screen for GastroCore POS.
///
/// Displays a thermal-receipt-style preview on a dark background.
/// White receipt card simulates thermal paper output.
/// Follows Stitch S06 design reference.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Demo data (MVP)
// ---------------------------------------------------------------------------

class _ReceiptItem {
  final int qty;
  final String name;
  final int unitPrice; // cents

  const _ReceiptItem({
    required this.qty,
    required this.name,
    required this.unitPrice,
  });

  int get subtotal => qty * unitPrice;
}

class _ReceiptData {
  final String restaurantName;
  final String address;
  final String phone;
  final String receiptNumber;
  final String dateTime;
  final String waiter;
  final String tableName;
  final List<_ReceiptItem> items;
  final int subtotal;
  final int taxAmount;
  final int grandTotal;
  final int paidAmount;
  final int changeAmount;
  final String paymentMethod;

  const _ReceiptData({
    required this.restaurantName,
    required this.address,
    required this.phone,
    required this.receiptNumber,
    required this.dateTime,
    required this.waiter,
    required this.tableName,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    required this.grandTotal,
    required this.paidAmount,
    required this.changeAmount,
    required this.paymentMethod,
  });
}

_ReceiptData _buildDemoReceipt() {
  const items = [
    _ReceiptItem(qty: 2, name: 'Izgara Tavuk', unitPrice: 18500),
    _ReceiptItem(qty: 1, name: 'Adana Kebap', unitPrice: 21000),
    _ReceiptItem(qty: 1, name: 'Sezar Salata', unitPrice: 12000),
    _ReceiptItem(qty: 2, name: 'Ayran', unitPrice: 3500),
    _ReceiptItem(qty: 1, name: 'Kunefe', unitPrice: 11000),
  ];
  final subtotal = items.fold<int>(0, (s, i) => s + i.subtotal);
  final tax = (subtotal * 0.10).round();
  final total = subtotal + tax;

  return _ReceiptData(
    restaurantName: 'GASTROCORE RESTAURANT',
    address: 'Bahnhofstrasse 42, Zurich',
    phone: 'Tel: +41 (044) 123 45 67',
    receiptNumber: '#0412',
    dateTime: '20.03.2026  14:32',
    waiter: 'Ahmet K.',
    tableName: 'Masa 12',
    items: items,
    subtotal: subtotal,
    taxAmount: tax,
    grandTotal: total,
    paidAmount: 100000,
    changeAmount: 100000 - total,
    paymentMethod: 'Nakit',
  );
}

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
  // TODO: Replace with real receipt data from provider using widget.ticketId
  late final _ReceiptData _receipt;

  @override
  void initState() {
    super.initState();
    _receipt = _buildDemoReceipt();
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(child: _buildReceiptArea()),
          _buildBottomActions(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top navigation bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar() {
    const tabs = ['Dashboard', 'Tables', 'Orders', 'Kitchen', 'Inventory', 'Reports'];
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
                if (tab == 'Kitchen') context.go('/kitchen');
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
            onTap: () {
              // TODO: Search orders
            },
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
  // Receipt area (center)
  // -------------------------------------------------------------------------

  Widget _buildReceiptArea() {
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
                // Restaurant name
                Text(
                  _receipt.restaurantName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),

                // Address
                Text(
                  _receipt.address,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF555555),
                  ),
                ),
                const SizedBox(height: 2),

                // Phone
                Text(
                  _receipt.phone,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF555555),
                  ),
                ),
                const SizedBox(height: 12),

                // Dashed divider
                _buildDashedDivider(),
                const SizedBox(height: 10),

                // Date / Receipt #
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _receipt.dateTime,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF333333),
                      ),
                    ),
                    Text(
                      'Fis No: ${_receipt.receiptNumber}',
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
                      'Garson: ${_receipt.waiter}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF555555),
                      ),
                    ),
                    Text(
                      _receipt.tableName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF555555),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Dashed divider
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

                // Items
                for (final item in _receipt.items) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.qty}x ${item.name}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ),
                        Text(
                          '\u20BA${_formatCents(item.subtotal)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1A1A1A),
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // Dashed divider
                _buildDashedDivider(),
                const SizedBox(height: 10),

                // Subtotal
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Ara Toplam',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF555555),
                      ),
                    ),
                    Text(
                      '\u20BA${_formatCents(_receipt.subtotal)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF333333),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Tax
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'KDV (%10)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF555555),
                      ),
                    ),
                    Text(
                      '\u20BA${_formatCents(_receipt.taxAmount)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF333333),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
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
                      '\u20BA${_formatCents(_receipt.grandTotal)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Payment info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_receipt.paymentMethod}:',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF555555),
                      ),
                    ),
                    Text(
                      '\u20BA${_formatCents(_receipt.paidAmount)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF333333),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Para Ustu:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF555555),
                      ),
                    ),
                    Text(
                      '\u20BA${_formatCents(_receipt.changeAmount)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF333333),
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
                  style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF999999),
                  ),
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

          // Print button (gradient blue)
          GestureDetector(
            onTap: () {
              // TODO: Integrate with printer service
            },
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
            onTap: () {
              // TODO: Send receipt via email
            },
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

          // QR-Bill button
          GestureDetector(
            onTap: () => context.go(
              AppRoutes.qrBill,
              extra: {
                'ticketId': widget.ticketId,
                'amountCents': _receipt.grandTotal,
                'invoiceId': _receipt.receiptNumber,
              },
            ),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_2_rounded,
                      size: 18, color: AppColors.accent),
                  SizedBox(width: 6),
                  Text(
                    'QR-Bill',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
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
