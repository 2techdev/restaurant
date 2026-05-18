/// Bridges [lastBarcodeScanProvider] to the POS cart.
///
/// Drop one of these into the POS shell — when a scan lands, it looks
/// the barcode up in [productsProvider], adds a matching product to the
/// current ticket, and shows a SnackBar (success or "barkod bulunamadı").
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/features/hardware/barcode/barcode_scanner.dart';
import 'package:gastrocore_pos/features/menu/domain/entities/product_entity.dart';
import 'package:gastrocore_pos/features/menu/presentation/providers/menu_provider.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

class BarcodeScanListener extends ConsumerWidget {
  const BarcodeScanListener({super.key, required this.child});
  final Widget child;

  String _t(BuildContext context, String tr, String de, String en, String fr,
      String it) {
    final lang = Localizations.localeOf(context).languageCode;
    switch (lang) {
      case 'de':
        return de;
      case 'en':
        return en;
      case 'fr':
        return fr;
      case 'it':
        return it;
      default:
        return tr;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(lastBarcodeScanProvider, (_, next) async {
      if (next == null || next.isEmpty) return;
      // Drain so a repeat of the same code re-fires.
      Future.microtask(() {
        ref.read(lastBarcodeScanProvider.notifier).state = null;
      });

      final products =
          ref.read(productsProvider).valueOrNull ?? const <ProductEntity>[];
      ProductEntity? match;
      for (final p in products) {
        if ((p.barcode ?? '').trim() == next.trim()) {
          match = p;
          break;
        }
      }
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (match == null) {
        messenger?.showSnackBar(SnackBar(
          content: Text(_t(
            context,
            'Barkod bulunamadı: $next',
            'Barcode nicht gefunden: $next',
            'Barcode not found: $next',
            'Code-barres introuvable : $next',
            'Codice a barre non trovato: $next',
          )),
          duration: const Duration(seconds: 2),
        ));
        return;
      }
      if (!match.isAvailable) {
        messenger?.showSnackBar(SnackBar(
          content: Text(_t(
            context,
            '${match.name} bugün stokta yok',
            '${match.name} heute nicht verfügbar',
            '${match.name} sold out today',
            '${match.name} en rupture aujourd’hui',
            '${match.name} esaurito oggi',
          )),
          duration: const Duration(seconds: 2),
        ));
        return;
      }
      final ticket = ref.read(currentTicketProvider);
      if (ticket == null) {
        messenger?.showSnackBar(SnackBar(
          content: Text(_t(
            context,
            'Önce bir adisyon açın',
            'Zuerst einen Beleg öffnen',
            'Open a ticket first',
            'Ouvrez d’abord un ticket',
            'Apri prima un ticket',
          )),
          duration: const Duration(seconds: 2),
        ));
        return;
      }
      await ref.read(currentTicketProvider.notifier).addItem(match);
      messenger?.showSnackBar(SnackBar(
        content: Text('+ ${match.name}'),
        duration: const Duration(milliseconds: 900),
      ));
    });
    return child;
  }
}
