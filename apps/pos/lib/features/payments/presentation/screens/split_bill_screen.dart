/// Split Bill Screen for GastroCore POS - Stitch V2 Design.
///
/// Equal Split / By Item / Custom Amount tabs.
/// Guest count selector, per-person calculation, guest cards with
/// paid/unpaid status, rounding adjustment.
/// Matches Stitch V2 split_bill design exactly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Demo data (MVP)
// ---------------------------------------------------------------------------

class _BillItem {
  final String id;
  final String name;
  final String detail;
  final int qty;
  final int unitPrice;

  const _BillItem({
    required this.id,
    required this.name,
    this.detail = '',
    required this.qty,
    required this.unitPrice,
  });

  int get subtotal => qty * unitPrice;
}

const _kDemoBillItems = [
  _BillItem(id: 'bi1', name: 'Izgara Tavuk', detail: 'Medium rare, no onions', qty: 2, unitPrice: 18500),
  _BillItem(id: 'bi2', name: 'Adana Kebap', detail: 'Extra spicy', qty: 1, unitPrice: 21000),
  _BillItem(id: 'bi3', name: 'Sezar Salata', qty: 1, unitPrice: 12000),
  _BillItem(id: 'bi4', name: 'Ayran', detail: '300ml', qty: 2, unitPrice: 3500),
  _BillItem(id: 'bi5', name: 'Kunefe', detail: 'Antep fistikli', qty: 1, unitPrice: 11000),
  _BillItem(id: 'bi6', name: 'Mercimek Corbasi', qty: 2, unitPrice: 6500),
];

// ---------------------------------------------------------------------------
// Split Bill Screen
// ---------------------------------------------------------------------------

class SplitBillScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const SplitBillScreen({super.key, required this.ticketId});

  @override
  ConsumerState<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends ConsumerState<SplitBillScreen> {
  int _activeTab = 0; // 0 = Equal Split, 1 = By Item, 2 = Custom Amount
  int _guestCount = 3;

  // Track which guests have paid (for demo)
  final Set<int> _paidGuests = {1}; // Guest 2 is paid by default

  int get _grandTotal =>
      _kDemoBillItems.fold<int>(0, (s, i) => s + i.subtotal);

  String _formatCHF(int cents) {
    final abs = cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return 'CHF $whole.$frac';
  }

  int get _perPerson => _guestCount > 0 ? _grandTotal ~/ _guestCount : 0;
  int get _remainder => _guestCount > 0 ? _grandTotal % _guestCount : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Row(
        children: [
          // Left sidebar
          _buildSidebar(),
          // Main content
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                _buildTabSelector(),
                Expanded(child: _buildContent()),
                _buildFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sidebar
  // -------------------------------------------------------------------------

  Widget _buildSidebar() {
    return Container(
      width: 240,
      color: AppColors.surface,
      child: Column(
        children: [
          // Brand
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primary],
                  ).createShader(bounds),
                  child: const Text(
                    'GastroCore',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'STATION 01',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8C909F),
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Nav items
          _buildNavItem(Icons.shopping_cart, 'Order', true),
          _buildNavItem(Icons.receipt_long, 'Records', false),
          _buildNavItem(Icons.grid_view, 'Tables', false),
          _buildNavItem(Icons.restaurant_menu, 'Menu', false),
          _buildNavItem(Icons.terminal, 'KDS', false),
          const Spacer(),
          // Support
          _buildNavItem(Icons.help, 'Support', false),
          // Profile
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF33343B),
                  ),
                  child: const Icon(Icons.person, size: 20, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Marco R.',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE2E2EB)),
                    ),
                    Text(
                      'Lead Chef',
                      style: TextStyle(fontSize: 10, color: Color(0xFF8C909F)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isActive ? AppColors.surfaceContainer : Colors.transparent,
        border: isActive
            ? const Border(left: BorderSide(color: AppColors.primary, width: 4))
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isActive ? AppColors.textPrimary : AppColors.textSecondary),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      height: 96,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      color: AppColors.surfaceContainerHigh,
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => context.go('/order-center'),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back, color: Color(0xFFE2E2EB)),
            ),
          ),
          const SizedBox(width: 24),
          // Title
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Split Bill',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'TABLE #12 \u2014 4 GUESTS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFC3C6D7),
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Total
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'TOTAL BALANCE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8C909F),
                  letterSpacing: 2.0,
                ),
              ),
              Text(
                _formatCHF(_grandTotal),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  letterSpacing: -2.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tab Selector
  // -------------------------------------------------------------------------

  Widget _buildTabSelector() {
    const tabs = ['Equal Split', 'By Item', 'Custom Amount'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(tabs.length, (i) {
              final isActive = _activeTab == i;
              return GestureDetector(
                onTap: () => setState(() => _activeTab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.surfaceContainerHigh : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isActive
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12)]
                        : null,
                  ),
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Content
  // -------------------------------------------------------------------------

  Widget _buildContent() {
    switch (_activeTab) {
      case 0:
        return _buildEqualSplitContent();
      case 1:
        return _buildByItemContent();
      case 2:
        return _buildCustomContent();
      default:
        return _buildEqualSplitContent();
    }
  }

  // -- Equal Split --
  Widget _buildEqualSplitContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Controls
          Expanded(
            flex: 5,
            child: Column(
              children: [
                // Guest count
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1F26),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'NUMBER OF GUESTS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8C909F),
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (_guestCount > 2) setState(() => _guestCount--);
                            },
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.remove, size: 28, color: Color(0xFFE2E2EB)),
                            ),
                          ),
                          const SizedBox(width: 48),
                          Text(
                            '$_guestCount',
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 48),
                          GestureDetector(
                            onTap: () {
                              if (_guestCount < 20) setState(() => _guestCount++);
                            },
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.add, size: 28, color: Color(0xFFE2E2EB)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Calculated per person
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D1F26),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Stack(
                      children: [
                        // Gradient overlay
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const AppColors.primaryLight.withValues(alpha: 0.05),
                                  const AppColors.primary.withValues(alpha: 0.05),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'CALCULATED PER PERSON',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryLight,
                                  letterSpacing: 2.0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatCHF(_perPerson),
                                style: const TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -2.0,
                                ),
                              ),
                              if (_remainder > 0) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'Remaining: ${_formatCHF(_remainder)} (Rounding adjustment)',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF8C909F),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          // Right: Guest cards
          Expanded(
            flex: 7,
            child: ListView.builder(
              padding: const EdgeInsets.only(right: 8),
              itemCount: _guestCount + (_remainder > 0 ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _guestCount) {
                  // Rounding adjustment card
                  return _buildRoundingCard();
                }
                final isPaid = _paidGuests.contains(index);
                return _buildGuestCard(index, isPaid);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestCard(int index, bool isPaid) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isPaid
            ? const Color(0xFF22C55E).withValues(alpha: 0.05)
            : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: isPaid
            ? const Border(left: BorderSide(color: Color(0xFF22C55E), width: 4))
            : null,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPaid
                  ? const Color(0xFF22C55E).withValues(alpha: 0.2)
                  : AppColors.surfaceContainerHigh,
            ),
            child: Center(
              child: isPaid
                  ? const Icon(Icons.check, color: Color(0xFF22C55E))
                  : Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryLight,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 24),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guest ${(index + 1).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                        : const Color(0xFF1D1F26),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isPaid ? 'Paid Cash' : 'Unpaid',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isPaid ? FontWeight.w700 : FontWeight.w500,
                      color: isPaid
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFC3C6D7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Amount + action
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatCHF(_perPerson),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  decorationColor: isPaid ? AppColors.textDim : null,
                ),
              ),
              if (!isPaid)
                GestureDetector(
                  onTap: () => setState(() => _paidGuests.add(index)),
                  child: const Text(
                    'Settle Card',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryLight,
                    ),
                  ),
                )
              else
                const Text(
                  'Receipt #8821',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8C909F)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoundingCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Opacity(
        opacity: 0.4,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1D1F26),
              ),
              child: const Icon(Icons.info, color: Color(0xFF8C909F)),
            ),
            const SizedBox(width: 24),
            const Text(
              'Rounding Adjustment',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8C909F),
              ),
            ),
            const Spacer(),
            Text(
              _formatCHF(_remainder),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF8C909F),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- By Item (placeholder) --
  Widget _buildByItemContent() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.list_alt, size: 48, color: AppColors.textDim),
          SizedBox(height: 16),
          Text(
            'Item-based splitting',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          SizedBox(height: 8),
          Text(
            'Drag items to assign them to individual guests',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  // -- Custom (placeholder) --
  Widget _buildCustomContent() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit, size: 48, color: AppColors.textDim),
          SizedBox(height: 16),
          Text(
            'Custom amount splitting',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          SizedBox(height: 8),
          Text(
            'Enter custom amounts for each guest',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Footer
  // -------------------------------------------------------------------------

  Widget _buildFooter() {
    return Container(
      height: 128,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1F26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Print All
          GestureDetector(
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.print, color: AppColors.textPrimary),
                  SizedBox(width: 12),
                  Text(
                    'Print All Drafts',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Reset Split
          GestureDetector(
            onTap: () => setState(() => _paidGuests.clear()),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.undo, color: AppColors.textPrimary),
                  SizedBox(width: 12),
                  Text(
                    'Reset Split',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Settle All
          GestureDetector(
            onTap: () => context.go('/order-center'),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 48),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryLight, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Text(
                    'Settle All Bills',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 16),
                  Icon(Icons.payments, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
