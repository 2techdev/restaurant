/// **Legacy placeholder.**
///
/// The original Kinetic-redesign PaymentScreen referenced helper methods
/// (`_buildSidebar`, `_buildPaymentInterface`, `_clearLoyalty`,
/// `_pickVoucher`, `_submit`, …) that never landed on main, so the file
/// has been broken for a while. The router was updated to point at
/// `OrderPaymentScreen` (the v2 implementation in
/// `features/orders/presentation/screens/payment_screen.dart`) so the
/// app still has a payment surface.
///
/// Keeping this file as a thin shell lets stale `import …/screens/
/// payment_screen.dart` references resolve without dragging the
/// half-finished UI back into the build graph.
library;

import 'package:flutter/material.dart';

class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Use OrderPaymentScreen from features/orders/.../payment_screen.dart',
        ),
      ),
    );
  }
}
