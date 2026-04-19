library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TipSelector extends StatefulWidget {
  final int tipAmount;
  final int baseAmount;
  final ValueChanged<int> onChanged;

  const TipSelector({
    super.key,
    required this.tipAmount,
    required this.baseAmount,
    required this.onChanged,
  });

  @override
  State<TipSelector> createState() => _TipSelectorState();
}

class _TipSelectorState extends State<TipSelector> {
  int? _selectedPercent;

  void _applyPercent(int percent) {
    final cents = (widget.baseAmount * percent / 100).round();
    setState(() => _selectedPercent = percent);
    widget.onChanged(cents);
  }

  Future<void> _openCustomDialog() async {
    final controller = TextEditingController(
      text: widget.tipAmount > 0
          ? (widget.tipAmount / 100).toStringAsFixed(2)
          : '',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B22),
        title: const Text(
          'Bahşiş (CHF)',
          style: TextStyle(color: Color(0xFFE2E2EB)),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: const TextStyle(color: Color(0xFFE2E2EB), fontSize: 18),
          decoration: const InputDecoration(
            hintText: '0.00',
            hintStyle: TextStyle(color: Color(0xFFC3C6D7)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text) ?? 0;
              Navigator.of(ctx).pop((value * 100).round());
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _selectedPercent = null);
      widget.onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF191B22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Bahşiş',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFC3C6D7),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _presetBtn(5),
              const SizedBox(width: 8),
              _presetBtn(10),
              const SizedBox(width: 8),
              _presetBtn(15),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _openCustomDialog,
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: _selectedPercent == null && widget.tipAmount > 0
                          ? const Color(0xFF282A30)
                          : const Color(0xFF1D1F26),
                      borderRadius: BorderRadius.circular(8),
                      border: _selectedPercent == null && widget.tipAmount > 0
                          ? Border.all(color: const Color(0xFF528DFF), width: 1.5)
                          : null,
                    ),
                    child: const Center(
                      child: Text(
                        'Özel',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE2E2EB),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (widget.tipAmount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bahşiş (MWST dışı)',
                    style: TextStyle(fontSize: 11, color: Color(0xFFC3C6D7)),
                  ),
                  Text(
                    '+CHF${(widget.tipAmount / 100).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFAFC6FF),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedPercent = null);
                      widget.onChanged(0);
                    },
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFFFFB4AB),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _presetBtn(int percent) {
    final isSelected = _selectedPercent == percent;
    return Expanded(
      child: GestureDetector(
        onTap: () => _applyPercent(percent),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF282A30)
                : const Color(0xFF1D1F26),
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: const Color(0xFF528DFF), width: 1.5)
                : null,
          ),
          child: Center(
            child: Text(
              '$percent%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isSelected
                    ? const Color(0xFF528DFF)
                    : const Color(0xFFE2E2EB),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
