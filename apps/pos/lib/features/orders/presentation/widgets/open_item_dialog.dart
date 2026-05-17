/// Open Item — ad-hoc cart line dialog.
///
/// Lets the cashier add a one-off charge to the active ticket without
/// going through the menu — e.g. "Special order — CHF 42". Useful for
/// catering, custom requests, or anything not on the menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

/// Show the Open Item dialog. Returns `true` if a line was added.
Future<bool> showOpenItemDialog(BuildContext context) async {
  final added = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _OpenItemDialog(),
  );
  return added ?? false;
}

class _OpenItemDialog extends ConsumerStatefulWidget {
  const _OpenItemDialog();

  @override
  ConsumerState<_OpenItemDialog> createState() => _OpenItemDialogState();
}

class _OpenItemDialogState extends ConsumerState<_OpenItemDialog> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String? _err;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String _t(String tr, String de, String en, String fr, String it) {
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

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final raw = _priceCtrl.text.trim().replaceAll(',', '.');
    if (name.isEmpty) {
      setState(() => _err = _t(
            'Ürün adı girin',
            'Artikelname eingeben',
            'Enter item name',
            'Saisir le nom',
            'Inserisci nome',
          ));
      return;
    }
    final priceDouble = double.tryParse(raw);
    if (priceDouble == null || priceDouble <= 0) {
      setState(() => _err = _t(
            'Geçerli tutar girin',
            'Gültigen Betrag eingeben',
            'Enter a valid amount',
            'Saisir un montant valide',
            'Inserisci un importo valido',
          ));
      return;
    }
    final cents = (priceDouble * 100).round();
    final ticket = ref.read(currentTicketProvider);
    if (ticket == null) {
      setState(() => _err = _t(
            'Önce bir adisyon açın',
            'Zuerst einen Beleg öffnen',
            'Open a ticket first',
            'Ouvrez d’abord un ticket',
            'Apri prima un ticket',
          ));
      return;
    }
    setState(() {
      _submitting = true;
      _err = null;
    });
    await ref.read(currentTicketProvider.notifier).addOpenItem(
          name: name,
          priceCents: cents,
        );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    const currency = 'CHF';
    return Dialog(
      backgroundColor: GcColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.space20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.add_circle_outline_rounded,
                      color: GcColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t(
                        'Açık Tutar',
                        'Offener Betrag',
                        'Open Item',
                        'Montant libre',
                        'Importo libero',
                      ),
                      style: GcText.headline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.space16),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _t(
                    'Ürün adı',
                    'Artikelname',
                    'Item name',
                    'Nom de l’article',
                    'Nome articolo',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppTokens.space12),
              TextField(
                controller: _priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9.,]')),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: _t(
                    'Tutar ($currency)',
                    'Betrag ($currency)',
                    'Amount ($currency)',
                    'Montant ($currency)',
                    'Importo ($currency)',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_err != null) ...[
                const SizedBox(height: AppTokens.space8),
                Text(_err!,
                    style: const TextStyle(
                        color: GcColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: AppTokens.space20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(_t('İptal', 'Abbrechen', 'Cancel',
                          'Annuler', 'Annulla')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(_t(
                        'Ekle',
                        'Hinzufügen',
                        'Add',
                        'Ajouter',
                        'Aggiungi',
                      )),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
