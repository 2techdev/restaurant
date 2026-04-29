/// Golden baseline: payment method card.
///
/// Renders the three primary payment tiles (cash / card / twint) at
/// 1920x1200 so icon alignment, radius, and label typography regressions
/// surface as a pixel diff.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  testWidgets('golden :: payment method cards', (tester) async {
    await pumpGolden(
      tester,
      child: const _PaymentMethodMock(),
    );
    await matchScreenGolden(tester, 'payment_method_card');
  });
}

class _PaymentMethodMock extends StatelessWidget {
  const _PaymentMethodMock();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 960,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16, left: 8),
              child: Text(
                'Ödeme yöntemi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Row(
              children: const [
                Expanded(
                  child: _MethodTile(
                    icon: Icons.payments_rounded,
                    label: 'Nakit',
                    selected: true,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _MethodTile(
                    icon: Icons.credit_card_rounded,
                    label: 'Kart',
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _MethodTile(
                    icon: Icons.qr_code_2_rounded,
                    label: 'TWINT',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? const Color(0xFF3b82f6)
        : const Color(0xFF282C35);
    final bg = selected
        ? const Color(0xFF1E293B)
        : const Color(0xFF1A1D24);
    return Container(
      height: 120,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: selected ? 2 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 36, color: Colors.white),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
