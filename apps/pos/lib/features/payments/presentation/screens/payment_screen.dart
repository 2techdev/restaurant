/// Payment Screen for GastroCore POS - Stitch V2 Design.
///
/// Left order summary, center numpad, right total display.
/// 4 payment method tabs (Nakit/Kredi/Banka/Bol Ode).
/// Matches Stitch V2 payment design exactly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Demo data (MVP)
// ---------------------------------------------------------------------------

enum _PaymentMethod { cash, creditCard, debitCard, split }

class _DemoOrderItem {
  final String name;
  final int qty;
  final int price;
  final String? detail;

  const _DemoOrderItem({
    required this.name,
    required this.qty,
    required this.price,
    this.detail,
  });

  int get subtotal => price * qty;
}

const _kDemoItems = [
  _DemoOrderItem(name: 'Ribeye Steak', qty: 2, price: 42000, detail: 'Medium Rare, Peppercorn'),
  _DemoOrderItem(name: 'Truffle Fries', qty: 1, price: 14500),
  _DemoOrderItem(name: 'Efes Pilsen 50cl', qty: 3, price: 12000),
];

// ---------------------------------------------------------------------------
// Payment Screen
// ---------------------------------------------------------------------------

class PaymentScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const PaymentScreen({super.key, required this.ticketId});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  _PaymentMethod _selectedMethod = _PaymentMethod.cash;
  String _amountStr = '';
  bool _paymentComplete = false;

  int get _subtotal =>
      _kDemoItems.fold<int>(0, (sum, item) => sum + item.subtotal);
  int get _taxAmount => (_subtotal * 0.10).round();
  int get _grandTotal => _subtotal + _taxAmount;

  int get _enteredAmount {
    if (_amountStr.isEmpty) return 0;
    return int.tryParse(_amountStr) ?? 0;
  }

  int get _changeAmount {
    final entered = _enteredAmount * 100;
    if (entered <= _grandTotal) return 0;
    return entered - _grandTotal;
  }

  String _formatCents(int cents) {
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    final wholeStr = whole.toString();
    final parts = <String>[];
    for (var i = wholeStr.length; i > 0; i -= 3) {
      final start = i - 3 < 0 ? 0 : i - 3;
      parts.insert(0, wholeStr.substring(start, i));
    }
    return '${parts.join(',')}.$frac';
  }

  void _onDigit(String digit) {
    if (_amountStr.length >= 8) return;
    setState(() => _amountStr += digit);
  }

  void _onBackspace() {
    if (_amountStr.isEmpty) return;
    setState(() => _amountStr = _amountStr.substring(0, _amountStr.length - 1));
  }

  void _onQuickAmount(int amount) {
    setState(() => _amountStr = amount.toString());
  }

  void _onCompletePayment() {
    setState(() => _paymentComplete = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) context.go('/order-center');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_paymentComplete) {
      return _buildCompletionView();
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),
          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(),
                // Content: order summary + payment
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        // Left: Order summary (4/12)
                        Expanded(
                          flex: 4,
                          child: _buildOrderSummary(),
                        ),
                        const SizedBox(width: 24),
                        // Right: Payment interface (8/12)
                        Expanded(
                          flex: 8,
                          child: _buildPaymentInterface(),
                        ),
                      ],
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

  // -------------------------------------------------------------------------
  // Completion view
  // -------------------------------------------------------------------------

  Widget _buildCompletionView() {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.greenDim,
              ),
              child: const Icon(Icons.check_rounded, size: 40, color: AppColors.green),
            ),
            const SizedBox(height: 24),
            const Text(
              'Odeme Tamamlandi!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Para Ustu: \u20BA${_formatCents(_changeAmount)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.green),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sidebar
  // -------------------------------------------------------------------------

  Widget _buildSidebar() {
    return Container(
      width: 96,
      color: AppColors.surfaceDim,
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Text('GC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          _buildSidebarItem(Icons.shopping_cart, 'Order', true),
          _buildSidebarItem(Icons.receipt_long, 'Records', false),
          _buildSidebarItem(Icons.grid_view, 'Table', false),
          _buildSidebarItem(Icons.restaurant_menu, 'Menu', false),
          _buildSidebarItem(Icons.kitchen, 'KDS', false),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF33343B),
            ),
            child: const Icon(Icons.person, size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String label, bool isActive) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: isActive ? AppColors.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: isActive ? AppColors.textPrimary : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      color: AppColors.surfaceDim,
      child: Row(
        children: [
          Flexible(
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.primaryLight, AppColors.primary],
              ).createShader(bounds),
              child: const Text(
                'GastroCore POS',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Flexible(
            child: Text(
              'Menu',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
          ),
          const Spacer(),
          const Icon(Icons.cloud_done, color: AppColors.textSecondary),
          const SizedBox(width: 16),
          const Icon(Icons.account_circle, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Order Summary (left panel)
  // -------------------------------------------------------------------------

  Widget _buildOrderSummary() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Flexible(
                  child: Text(
                    'Order Summary',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFE2E2EB)),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Table #14',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFFC3C6D7)),
                  ),
                ),
              ],
            ),
          ),
          // Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _kDemoItems.length,
              itemBuilder: (context, index) {
                final item = _kDemoItems[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF33343B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            '${item.qty}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE2E2EB)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE2E2EB)),
                            ),
                            if (item.detail != null)
                              Text(
                                item.detail!,
                                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFFC3C6D7)),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '\u20BA${_formatCents(item.subtotal)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFE2E2EB)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Totals
          Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1F26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildTotalRow('Subtotal', '\u20BA${_formatCents(_subtotal)}', false),
                const SizedBox(height: 12),
                _buildTotalRow('KDV (10%)', '\u20BA${_formatCents(_taxAmount)}', false),
                const SizedBox(height: 12),
                Container(height: 1, color: const Color(0xFF424753).withValues(alpha: 0.2)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE2E2EB))),
                    Flexible(
                      child: Text(
                        '\u20BA${_formatCents(_grandTotal)}',
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primaryLight),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.print, size: 16, color: Color(0xFFE2E2EB)),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Print',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE2E2EB)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () => context.go('/order-center'),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF93000A).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close, size: 16, color: Color(0xFFFFB4AB)),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Cancel',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFFB4AB)),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildTotalRow(String label, String value, bool isBold) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Color(0xFFC3C6D7)),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: const Color(0xFFE2E2EB),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Payment Interface (right panel)
  // -------------------------------------------------------------------------

  Widget _buildPaymentInterface() {
    return Column(
      children: [
        // Payment methods + numpad area
        Expanded(
          child: Row(
            children: [
              // Left: methods + numpad (8/12)
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    // Payment method buttons
                    Row(
                      children: [
                        _buildMethodButton('Nakit', Icons.payments, _PaymentMethod.cash),
                        const SizedBox(width: 16),
                        _buildMethodButton('Kredi', Icons.credit_card, _PaymentMethod.creditCard),
                        const SizedBox(width: 16),
                        _buildMethodButton('Banka', Icons.account_balance, _PaymentMethod.debitCard),
                        const SizedBox(width: 16),
                        _buildMethodButton('Bol Ode', Icons.group, _PaymentMethod.split),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Numpad
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _buildNumpad(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Right: display + quick amounts + action (4/12)
              Expanded(
                child: Column(
                  children: [
                    // Amount display
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            const Text(
                              'ODENEN TUTAR',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFC3C6D7),
                                letterSpacing: 2.0,
                              ),
                            ),
                            Text(
                              _amountStr.isEmpty ? '\u20BA0.00' : '\u20BA$_amountStr.00',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFE2E2EB),
                              ),
                            ),
                            // Change display
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7990C6).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'PARA USTU',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryLight,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '\u20BA${_formatCents(_changeAmount)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.primaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Quick amounts
                    Row(
                      children: [
                        _buildQuickBtn(10),
                        const SizedBox(width: 12),
                        _buildQuickBtn(20),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildQuickBtn(50),
                        const SizedBox(width: 12),
                        _buildQuickBtn(100),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Complete payment button
                    GestureDetector(
                      key: const Key('complete_payment_btn'),
                      onTap: _enteredAmount * 100 >= _grandTotal ||
                              _selectedMethod != _PaymentMethod.cash
                          ? _onCompletePayment
                          : null,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _enteredAmount * 100 >= _grandTotal ||
                                _selectedMethod != _PaymentMethod.cash
                            ? 1.0
                            : 0.4,
                        child: Container(
                          width: double.infinity,
                          height: 96,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primaryLight, AppColors.primary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryLight.withValues(alpha: 0.2),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'ODEMEYI TAMAMLA',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF002D6D),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Siparisi Kapat & Yazdir',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF002D6D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMethodButton(String label, IconData icon, _PaymentMethod method) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMethod = method),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 64,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.surfaceContainerHigh
                : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
            boxShadow: isSelected
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 12)]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: isSelected ? AppColors.primary : const Color(0xFFC3C6D7)),
              const SizedBox(height: 2),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppColors.primary : const Color(0xFFC3C6D7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickBtn(int amount) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _onQuickAmount(amount),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1D1F26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              '$amount',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE2E2EB),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        Expanded(child: _buildNumRow(['1', '2', '3'])),
        const SizedBox(height: 16),
        Expanded(child: _buildNumRow(['4', '5', '6'])),
        const SizedBox(height: 16),
        Expanded(child: _buildNumRow(['7', '8', '9'])),
        const SizedBox(height: 16),
        Expanded(child: _buildNumRow(['.', '0', 'BACK'])),
      ],
    );
  }

  Widget _buildNumRow(List<String> keys) {
    return Row(
      children: keys.map((key) {
        final idx = keys.indexOf(key);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: idx == 0 ? 0 : 8,
              right: idx == keys.length - 1 ? 0 : 8,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (key == 'BACK') {
                    _onBackspace();
                  } else {
                    _onDigit(key);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  decoration: BoxDecoration(
                    color: const Color(0xFF33343B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: key == 'BACK'
                        ? const Icon(Icons.backspace_outlined, size: 22, color: Color(0xFFC3C6D7))
                        : Text(
                            key,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFE2E2EB),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
