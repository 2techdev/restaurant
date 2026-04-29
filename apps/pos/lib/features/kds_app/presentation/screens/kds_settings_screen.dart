/// KDS Settings Screen — station name, alert threshold, display options.
///
/// All settings are persisted via [SharedPreferences] and applied on the
/// next navigation to [KdsMainScreen].
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/config/app_endpoints.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/providers/kds_providers.dart';
import 'package:gastrocore_pos/features/kds_app/router/kds_router.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class KdsSettingsScreen extends ConsumerStatefulWidget {
  const KdsSettingsScreen({super.key});

  @override
  ConsumerState<KdsSettingsScreen> createState() => _KdsSettingsScreenState();
}

class _KdsSettingsScreenState extends ConsumerState<KdsSettingsScreen> {
  final _stationNameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _syncUrlCtrl = TextEditingController();
  final _kitchenPrinterIpCtrl = TextEditingController();
  final _kitchenPrinterPortCtrl = TextEditingController();

  int _lateThreshold = 10;
  bool _largeFont = false;
  bool _soundAlerts = true;
  bool _immersive = true;

  bool _saving = false;
  bool _testingPrinter = false;
  String? _printerTestResult;
  bool _printerTestOk = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _stationNameCtrl.dispose();
    _pinCtrl.dispose();
    _syncUrlCtrl.dispose();
    _kitchenPrinterIpCtrl.dispose();
    _kitchenPrinterPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final printer =
        ref.read(printerSettingsProvider).valueOrNull;
    setState(() {
      _stationNameCtrl.text =
          prefs.getString('kds_station_name') ?? 'Station 01';
      _lateThreshold = prefs.getInt('kds_late_threshold') ?? 10;
      _largeFont = prefs.getBool('kds_large_font') ?? false;
      _soundAlerts = prefs.getBool('kds_sound_alerts') ?? true;
      _immersive = prefs.getBool('kds_immersive') ?? true;
      _syncUrlCtrl.text =
          prefs.getString('sync_server_url') ?? AppEndpoints.apiBaseUrl;
      _pinCtrl.text = prefs.getString('kds_station_pin') ?? '1234';
      _kitchenPrinterIpCtrl.text = printer?.kitchenPrinterIp ?? '';
      _kitchenPrinterPortCtrl.text =
          (printer?.kitchenPrinterPort ?? 9100).toString();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('kds_station_name', _stationNameCtrl.text.trim());
    await prefs.setInt('kds_late_threshold', _lateThreshold);
    await prefs.setBool('kds_large_font', _largeFont);
    await prefs.setBool('kds_sound_alerts', _soundAlerts);
    await prefs.setBool('kds_immersive', _immersive);
    await prefs.setString('sync_server_url', _syncUrlCtrl.text.trim());

    final pin = _pinCtrl.text.trim();
    if (pin.length == 4 && int.tryParse(pin) != null) {
      await prefs.setString('kds_station_pin', pin);
    }

    // Persist kitchen printer settings via the shared PrinterSettings repo.
    final ip = _kitchenPrinterIpCtrl.text.trim();
    final port = int.tryParse(_kitchenPrinterPortCtrl.text.trim()) ?? 9100;
    await ref.read(printerSettingsProvider.notifier).update(
          (s) => s.copyWith(kitchenPrinterIp: ip, kitchenPrinterPort: port),
        );

    // Apply providers immediately.
    ref.read(kdsLateThresholdProvider.notifier).state = _lateThreshold;
    ref.read(kdsLargeFontProvider.notifier).state = _largeFont;

    // Apply immersive mode setting.
    if (_immersive) {
      await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    setState(() => _saving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          backgroundColor: AppColors.green,
          duration: Duration(seconds: 2),
        ),
      );
      context.go(KdsRoutes.main);
    }
  }

  /// Live connectivity check — opens a raw TCP socket to the configured
  /// kitchen printer and sends a minimal ESC/POS test page. Surfaces any
  /// network error inline so the operator can correct the IP / port before
  /// saving. Same payload as the POS settings test print so results match.
  Future<void> _testKitchenPrinter() async {
    final ip = _kitchenPrinterIpCtrl.text.trim();
    final port =
        int.tryParse(_kitchenPrinterPortCtrl.text.trim()) ?? 9100;
    if (ip.isEmpty) {
      setState(() {
        _printerTestResult = 'Enter an IP address first.';
        _printerTestOk = false;
      });
      return;
    }

    setState(() {
      _testingPrinter = true;
      _printerTestResult = 'Connecting to $ip:$port…';
      _printerTestOk = false;
    });

    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      socket.add([
        0x1B, 0x40, // ESC @ — initialize
        0x1B, 0x61, 0x01, // center align
        ...('GastroCore KDS\n').codeUnits,
        ...('--- Kitchen Test Print ---\n').codeUnits,
        ...('If you see this, the KDS can\n').codeUnits,
        ...('reach the kitchen printer.\n').codeUnits,
        0x1B, 0x64, 0x03, // feed 3 lines
        0x1D, 0x56, 0x42, 0x00, // partial cut
      ]);
      await socket.flush();
      await socket.close();
      if (mounted) {
        setState(() {
          _printerTestResult = 'Test page sent to $ip:$port.';
          _printerTestOk = true;
          _testingPrinter = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _printerTestResult = 'Connection failed: $e';
          _printerTestOk = false;
          _testingPrinter = false;
        });
      }
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1D27),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
          onPressed: () => context.go(KdsRoutes.main),
        ),
        title: const Text(
          'KDS Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'SAVE',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        letterSpacing: 1.0,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Station Info ─────────────────────────────────────────────────
          _sectionHeader('Station'),
          const SizedBox(height: 12),
          _inputField(
            label: 'Station Name',
            hint: 'e.g. Grill Station, Bar',
            controller: _stationNameCtrl,
          ),
          const SizedBox(height: 12),
          _inputField(
            label: 'Station PIN (4 digits)',
            hint: '1234',
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          _linkTile(
            icon: Icons.tune,
            label: 'Manage Kitchen Stations',
            subtitle: 'Add / rename / reorder cold, hot, dessert, bar…',
            onTap: () => context.go(KdsRoutes.stationManage),
          ),

          const SizedBox(height: 28),

          // ── Sync ─────────────────────────────────────────────────────────
          _sectionHeader('Sync Server'),
          const SizedBox(height: 12),
          _inputField(
            label: 'WebSocket / HTTP URL',
            hint: 'http://192.168.1.10:8080',
            controller: _syncUrlCtrl,
            keyboardType: TextInputType.url,
          ),

          const SizedBox(height: 28),

          // ── Kitchen Printer ──────────────────────────────────────────────
          _sectionHeader('Kitchen Printer'),
          const SizedBox(height: 12),
          _inputField(
            label: 'Printer IP Address',
            hint: '192.168.1.25',
            controller: _kitchenPrinterIpCtrl,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          _inputField(
            label: 'TCP Port',
            hint: '9100',
            controller: _kitchenPrinterPortCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 5,
          ),
          const SizedBox(height: 12),
          _printerTestBlock(),

          const SizedBox(height: 28),

          // ── Display ──────────────────────────────────────────────────────
          _sectionHeader('Display'),
          const SizedBox(height: 12),
          _settingTile(
            icon: Icons.text_increase,
            label: 'Large Font Mode',
            subtitle: 'Increases text size for easier kitchen reading',
            value: _largeFont,
            onChanged: (v) => setState(() => _largeFont = v),
          ),
          const SizedBox(height: 8),
          _settingTile(
            icon: Icons.fullscreen,
            label: 'Immersive Full-Screen',
            subtitle: 'Hides system bars — ideal for wall-mounted displays',
            value: _immersive,
            onChanged: (v) => setState(() => _immersive = v),
          ),

          const SizedBox(height: 28),

          // ── Alerts ───────────────────────────────────────────────────────
          _sectionHeader('Alerts'),
          const SizedBox(height: 12),
          _settingTile(
            icon: Icons.volume_up,
            label: 'Sound Alerts',
            subtitle: 'Audible beep when a new ticket arrives',
            value: _soundAlerts,
            onChanged: (v) => setState(() => _soundAlerts = v),
          ),
          const SizedBox(height: 12),
          _thresholdSlider(),

          const SizedBox(height: 40),

          // ── Save button ──────────────────────────────────────────────────
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: const Color(0xFF001944),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              _saving ? 'Saving…' : 'Save & Return to KDS',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Widget _sectionHeader(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppColors.textSecondary,
        letterSpacing: 2.0,
      ),
    );
  }

  Widget _inputField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppColors.textDim, fontSize: 14),
            filled: true,
            fillColor: AppColors.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                  color: AppColors.borderFocused, width: 1.5),
            ),
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _linkTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _printerTestBlock() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _testingPrinter ? null : _testKitchenPrinter,
              icon: _testingPrinter
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print_outlined, size: 18),
              label: Text(
                _testingPrinter ? 'Testing…' : 'Send Test Page',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: const Color(0xFF001944),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          if (_printerTestResult != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _printerTestOk
                    ? AppColors.greenDim
                    : AppColors.redDim,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    _printerTestOk
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: _printerTestOk
                        ? AppColors.green
                        : AppColors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _printerTestResult!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _printerTestOk
                            ? AppColors.green
                            : AppColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thresholdSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer, size: 22, color: AppColors.textSecondary),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Late Ticket Threshold',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_lateThreshold min',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.only(left: 36),
            child: Text(
              'Tickets older than this are highlighted red',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          Slider(
            value: _lateThreshold.toDouble(),
            min: 5,
            max: 30,
            divisions: 5,
            activeColor: AppColors.orange,
            inactiveColor: AppColors.surfaceContainerHigh,
            onChanged: (v) =>
                setState(() => _lateThreshold = v.round()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('5 min',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textDim)),
                Text('30 min',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
