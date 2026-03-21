/// KDS Settings Screen — station name, alert threshold, display options.
///
/// All settings are persisted via [SharedPreferences] and applied on the
/// next navigation to [KdsMainScreen].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/providers/kds_providers.dart';
import 'package:gastrocore_pos/features/kds_app/router/kds_router.dart';

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

  int _lateThreshold = 10;
  bool _largeFont = false;
  bool _soundAlerts = true;
  bool _immersive = true;

  bool _saving = false;

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
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _stationNameCtrl.text =
          prefs.getString('kds_station_name') ?? 'Station 01';
      _lateThreshold = prefs.getInt('kds_late_threshold') ?? 10;
      _largeFont = prefs.getBool('kds_large_font') ?? false;
      _soundAlerts = prefs.getBool('kds_sound_alerts') ?? true;
      _immersive = prefs.getBool('kds_immersive') ?? true;
      _syncUrlCtrl.text =
          prefs.getString('sync_server_url') ?? 'http://localhost:8080';
      _pinCtrl.text = prefs.getString('kds_station_pin') ?? '1234';
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
            activeColor: AppColors.primary,
          ),
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
