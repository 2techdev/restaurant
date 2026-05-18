/// USB / Bluetooth barcode scanner integration.
///
/// Scanners universally emulate a USB keyboard: they "type" the barcode
/// digits as fast keystrokes and finish with Enter. We capture those
/// keystrokes at the app shell level via [Focus] + [KeyboardListener],
/// guard against accidental hits while a real TextField is focused, and
/// fire a product lookup when the buffer terminates.
///
/// Detection heuristic — a sequence counts as a scan when ALL hold:
///   * 8+ alphanumeric characters
///   * Less than 200 ms between any two consecutive keys (humans can't
///     type that fast even on a mechanical keyboard)
///   * Terminated by Enter / Tab
///
/// Misses on this heuristic just fall through to whatever widget owns
/// focus — there's no risk of swallowing legitimate input.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence key for the "enabled" toggle (the user can disable the
/// listener from Settings if a flaky scanner is double-firing).
const _kPrefsKey = 'hardware.barcode_scanner_enabled.v1';

/// Async-loaded enabled flag — defaults to ON. Settings UI flips this.
final barcodeScannerEnabledProvider =
    StateNotifierProvider<_BarcodeEnabledNotifier, bool>((ref) {
  return _BarcodeEnabledNotifier();
});

class _BarcodeEnabledNotifier extends StateNotifier<bool> {
  _BarcodeEnabledNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kPrefsKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrefsKey, value);
  }
}

/// Last scan event — UI elements (cart, product grid) can listen to act
/// on the scan. Holds the raw barcode string until consumed.
final lastBarcodeScanProvider = StateProvider<String?>((ref) => null);

/// Wrap your shell tree with this. It installs a top-level keyboard
/// listener that captures the rapid keystroke burst from the scanner
/// and publishes the result to [lastBarcodeScanProvider].
class BarcodeScannerShell extends ConsumerStatefulWidget {
  const BarcodeScannerShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<BarcodeScannerShell> createState() =>
      _BarcodeScannerShellState();
}

class _BarcodeScannerShellState extends ConsumerState<BarcodeScannerShell> {
  final FocusNode _node = FocusNode(debugLabel: 'BarcodeScannerShell');
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKey;

  static const _maxGapMs = 200;
  static const _minScanLen = 8;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _commit() {
    final code = _buffer.toString();
    _buffer.clear();
    _lastKey = null;
    if (code.length < _minScanLen) return;
    ref.read(lastBarcodeScanProvider.notifier).state = code;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!ref.read(barcodeScannerEnabledProvider)) {
      return KeyEventResult.ignored;
    }
    // If another widget (TextField, search box) already owns primary
    // focus, don't swallow its keys — let the user type normally.
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary != _node && primary.context != null) {
      // A TextField is focused — bail.
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final now = DateTime.now();
    if (_lastKey != null &&
        now.difference(_lastKey!).inMilliseconds > _maxGapMs) {
      // Too slow — a real human typing. Reset the buffer.
      _buffer.clear();
    }
    _lastKey = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _commit();
      return KeyEventResult.handled;
    }
    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _buffer.write(char);
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      onKeyEvent: _onKey,
      autofocus: true,
      child: widget.child,
    );
  }
}
