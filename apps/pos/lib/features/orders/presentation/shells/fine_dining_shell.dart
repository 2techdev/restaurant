/// Fine-dining shell — POS v2 1:1 port.
///
/// The shell is a thin wrapper around [PosV2Shell], which implements the
/// POS v2 reference design (see `.design/pos-v2/POS.html` + `parts.jsx`).
/// Nav rail on the left, Bestellung panel, 2-column Kategorien grid, a
/// Schnellmenü chip row above the products grid — no separate bottom bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/orders/presentation/shells/pos_v2_shell.dart';

class FineDiningShell extends ConsumerWidget {
  const FineDiningShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(body: PosV2Shell());
  }
}
