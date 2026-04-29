library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/features/payments/data/repositories/voucher_repository.dart';
import 'package:gastrocore_pos/features/payments/domain/entities/voucher_entity.dart';

Future<VoucherEntity?> showVoucherDialog(BuildContext context) {
  return showDialog<VoucherEntity>(
    context: context,
    builder: (ctx) => const _VoucherDialog(),
  );
}

class _VoucherDialog extends StatefulWidget {
  const _VoucherDialog();

  @override
  State<_VoucherDialog> createState() => _VoucherDialogState();
}

class _VoucherDialogState extends State<_VoucherDialog> {
  final TextEditingController _controller = TextEditingController();
  final VoucherRepository _repo = const StubVoucherRepository();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Kod boş olamaz');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final voucher = await _repo.validate(code);
    if (!mounted) return;
    if (voucher == null) {
      setState(() {
        _loading = false;
        _error = 'Geçersiz kod';
      });
      return;
    }
    Navigator.of(context).pop(voucher);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF191B22),
      title: const Text(
        'Hediye Çeki',
        style: TextStyle(color: Color(0xFFE2E2EB), fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('voucher_code_field'),
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Color(0xFFE2E2EB), fontSize: 18),
            decoration: InputDecoration(
              hintText: 'GS-XXXX',
              hintStyle: const TextStyle(color: Color(0xFFC3C6D7)),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        TextButton(
          key: const Key('voucher_apply_btn'),
          onPressed: _loading ? null : _submit,
          child: Text(_loading ? '...' : 'Uygula'),
        ),
      ],
    );
  }
}
