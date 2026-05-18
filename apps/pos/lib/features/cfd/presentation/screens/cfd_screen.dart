/// Customer-Facing Display (CFD) screen.
///
/// Designed for a secondary tablet wall-mounted toward the customer
/// (or a customer-side iPad on the counter). Renders the live cart
/// from [currentTicketProvider] in big customer-friendly type —
/// matches what the cashier sees but with no operator chrome.
///
/// Pilot deployment: open this route on a second device that hits the
/// same LAN-synced Drift database, OR run on a single tablet with two
/// displays via the OS display extension. The screen subscribes to the
/// same Riverpod state as the cashier, so any cart change repaints
/// instantly.
///
/// Layout:
///   ┌─────────────────────────────────────────────────────┐
///   │  GastroCore POS                          [logo]     │
///   ├─────────────────────────────────────────────────────┤
///   │                                                     │
///   │   2 × Margherita Pizza             CHF 25.00        │
///   │   1 × Sparkling Water               CHF 4.50        │
///   │   1 × Tiramisu                       CHF 8.00       │
///   │                                                     │
///   ├─────────────────────────────────────────────────────┤
///   │   ZWISCHENSUMME                     CHF 37.50      │
///   │   SERVICE 10%                        CHF 3.75      │
///   │   TOTAL                             CHF 41.25      │
///   ├─────────────────────────────────────────────────────┤
///   │   Vielen Dank für Ihren Besuch!                    │
///   └─────────────────────────────────────────────────────┘
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/orders/domain/entities/order_item_entity.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/domain/service_charge.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

class CfdScreen extends ConsumerWidget {
  const CfdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final settings =
        ref.watch(restaurantSettingsProvider).valueOrNull;
    final restaurantName = settings?.name.isNotEmpty == true
        ? settings!.name
        : 'GastroCore';

    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: SafeArea(
        child: Column(
          children: [
            _Header(restaurantName: restaurantName),
            Expanded(
              child: ticket == null || ticket.items.isEmpty
                  ? const _Welcome()
                  : _CartView(ticket: ticket, settings: settings),
            ),
            _Footer(),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.restaurantName});
  final String restaurantName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Color(0xFF1E2530), width: 1)),
      ),
      child: Row(
        children: [
          Text(
            restaurantName.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0,
            ),
          ),
          const Spacer(),
          const Icon(Icons.qr_code_2, color: Color(0xFF6E7785), size: 28),
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.restaurant_menu,
              size: 96, color: Color(0xFF6E7785)),
          SizedBox(height: 24),
          Text(
            'Willkommen · Bienvenue · Welcome',
            style: TextStyle(
              color: Color(0xFF9DA6B5),
              fontSize: 26,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartView extends StatelessWidget {
  const _CartView({required this.ticket, required this.settings});
  final TicketEntity ticket;
  final RestaurantSettings? settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
                horizontal: 40, vertical: 24),
            itemCount: ticket.items.length,
            itemBuilder: (context, i) => _CartLine(item: ticket.items[i]),
          ),
        ),
        _Totals(ticket: ticket, settings: settings),
      ],
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({required this.item});
  final OrderItemEntity item;

  @override
  Widget build(BuildContext context) {
    final qty = item.quantity % 1 == 0
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              '$qty×',
              style: const TextStyle(
                color: Color(0xFF9DA6B5),
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.productName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            _chf(item.subtotal),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.ticket, required this.settings});
  final TicketEntity ticket;
  final RestaurantSettings? settings;

  @override
  Widget build(BuildContext context) {
    final liveFee = computeServiceFeeAmount(
      subtotalCents: ticket.subtotal,
      settings: settings,
    );
    final serviceFee = ticket.serviceFeeAmount > 0
        ? ticket.serviceFeeAmount
        : liveFee;
    final total = ticket.total +
        (ticket.serviceFeeAmount == 0 ? liveFee : 0);

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      decoration: const BoxDecoration(
        color: Color(0xFF1A2030),
        border: Border(
            top: BorderSide(color: Color(0xFF2A3245), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ticket.subtotal > 0)
            _row('Zwischensumme', ticket.subtotal, dim: true),
          if (serviceFee > 0)
            _row(
              'Service${settings != null ? ' ${_pct(settings!.serviceChargePercent)}%' : ''}',
              serviceFee,
              dim: true,
            ),
          if (ticket.taxAmount > 0)
            _row('MWST inkl.', ticket.taxAmount, dim: true),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const Spacer(),
              Text(
                _chf(total),
                style: const TextStyle(
                  color: Color(0xFF4CD9A0),
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, int cents, {bool dim = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: dim ? const Color(0xFF9DA6B5) : Colors.white,
              fontSize: 22,
            ),
          ),
          const Spacer(),
          Text(
            _chf(cents),
            style: TextStyle(
              color: dim ? const Color(0xFFB5BFCE) : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
            top: BorderSide(color: Color(0xFF1E2530), width: 1)),
      ),
      child: const Text(
        'Vielen Dank · Merci · Thank you · Teşekkürler · Grazie',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF6E7785),
          fontSize: 14,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

String _chf(int cents) {
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  return 'CHF $whole.$frac';
}

String _pct(double pct) {
  return pct.truncateToDouble() == pct
      ? pct.toStringAsFixed(0)
      : pct.toStringAsFixed(1);
}
