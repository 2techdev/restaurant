/// KDS Main Screen — full-screen ticket grid for kitchen display.
///
/// Renders incoming order tickets sorted oldest-first.
/// Color coding: new/pending = green, in-progress = yellow, late >N min = red.
/// Tap a ticket to bump (mark ready). Long-press to recall (un-bump).
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:gastrocore_pos/core/printing/models/print_models.dart';
import 'package:gastrocore_pos/core/printing/providers/print_use_case_provider.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/gang/domain/entities/gang_template_entity.dart';
import 'package:gastrocore_pos/features/gang/presentation/providers/gang_provider.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:gastrocore_pos/features/kds_app/data/kds_ws_client.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/providers/kds_providers.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/providers/kds_realtime_provider.dart';
import 'package:gastrocore_pos/features/kds_app/router/kds_router.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';
import 'package:gastrocore_pos/features/stations/domain/entities/station_entity.dart';
import 'package:gastrocore_pos/features/stations/presentation/providers/station_provider.dart';

// ---------------------------------------------------------------------------
// Urgency helpers — green → amber → red timer coding
//
// Two independent signals roll up into a single urgency tier:
//   1. Age: elapsed time since the ticket was sent to the kitchen.
//   2. Status: whether the kitchen has picked the ticket up (preparing).
//
// Tiers (amber wins over green; red wins over amber):
//   fresh        age <  kTicketWatchThresholdMin AND status == pending
//   inProgress   age <  kTicketWatchThresholdMin AND status == preparing
//   watch        age >= kTicketWatchThresholdMin AND age < lateThresholdMin
//                (regardless of status — pending for this long is a signal)
//   late         age >= lateThresholdMin
//
// The watch tier (5 min by default) is the Sprint 3.4 addition: previously
// a pending ticket stayed green until the late threshold, which let slow
// orders hide in the grid. Five minutes is the point at which a ticket
// sitting un-acknowledged is a real problem worth flagging amber.
// ---------------------------------------------------------------------------

/// Age at which a ticket flips from fresh (green) to watch (amber).
const int kTicketWatchThresholdMin = 5;

@visibleForTesting
enum TicketUrgency { fresh, inProgress, watch, late }

@visibleForTesting
TicketUrgency getTicketUrgency(
  KitchenTicketEntity ticket,
  int lateThresholdMin, {
  DateTime? now,
}) {
  final elapsed = (now ?? DateTime.now()).difference(ticket.sentAt);
  if (elapsed.inMinutes >= lateThresholdMin) return TicketUrgency.late;
  if (elapsed.inMinutes >= kTicketWatchThresholdMin) return TicketUrgency.watch;
  if (ticket.status == KitchenTicketStatus.preparing) {
    return TicketUrgency.inProgress;
  }
  return TicketUrgency.fresh;
}

// Green (#69F6B8) = fresh  •  Amber (#FBBF24) = cooking / watch  •  Red (#FF6F7E) = overdue
Color _urgencyBorderColor(TicketUrgency u) => switch (u) {
      TicketUrgency.fresh => AppColors.green,          // #69F6B8
      TicketUrgency.inProgress => const Color(0xFFFBBF24),
      TicketUrgency.watch => const Color(0xFFFBBF24),
      TicketUrgency.late => AppColors.red,             // #FF6F7E
    };

Color _urgencyBadgeColor(TicketUrgency u) => switch (u) {
      TicketUrgency.fresh => AppColors.greenDim,       // 10% tint of #69F6B8
      TicketUrgency.inProgress => const Color(0x1AFBBF24),
      TicketUrgency.watch => const Color(0x1AFBBF24),
      TicketUrgency.late => AppColors.redDim,          // 10% tint of #FF6F7E
    };

String _urgencyLabel(TicketUrgency u) => switch (u) {
      TicketUrgency.fresh => 'NEW',
      TicketUrgency.inProgress => 'COOKING',
      TicketUrgency.watch => 'WAITING',
      TicketUrgency.late => 'LATE',
    };

String _formatElapsed(KitchenTicketEntity ticket) {
  final elapsed = DateTime.now().difference(ticket.sentAt);
  final m = elapsed.inMinutes.toString().padLeft(2, '0');
  final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ---------------------------------------------------------------------------
// Allergy / VIP detection — fine-dining critical safety
// ---------------------------------------------------------------------------

/// VIP marker — higher-urgency service guidance that benefits from a distinct
/// (gold) banner vs. allergy red.
bool _isVipNote(String? notes) {
  if (notes == null || notes.isEmpty) return false;
  return notes.toLowerCase().contains('vip');
}

/// Dietary / allergy alert — kitchen-safety critical, always red.
bool _isAllergyNote(String? notes) {
  if (notes == null || notes.isEmpty) return false;
  final n = notes.toLowerCase();
  return n.contains('allerg') || // allergy/allergen/allergie/allergique
      n.contains('alerji') ||    // TR
      n.contains('nut') ||       // nut/peanut/hazelnut
      n.contains('gluten') ||
      n.contains('lactose') ||
      n.contains('laktoz') ||    // TR
      n.contains('kosher') ||
      n.contains('halal') ||
      n.contains('vegan');
}

/// Any kitchen-critical alert (allergy OR VIP).
bool _isAlertNote(String? notes) => _isAllergyNote(notes) || _isVipNote(notes);

/// Alert category for banner color selection.
enum _AlertKind { none, allergy, vip }

/// Returns the first alert-bearing note text on the ticket, or null.
String? _ticketAlertText(KitchenTicketEntity ticket) {
  for (final item in ticket.items) {
    if (_isAlertNote(item.notes)) return item.notes;
  }
  return null;
}

/// Returns the first (note, kind) pair in [items] whose note is an alert.
/// Allergy wins over VIP when both are present in the same group — safety
/// trumps service priority.
({String text, _AlertKind kind})? _groupAlert(
    Iterable<KitchenTicketItemEntity> items) {
  String? vipFallback;
  for (final item in items) {
    if (_isAllergyNote(item.notes)) {
      return (text: item.notes!, kind: _AlertKind.allergy);
    }
    if (_isVipNote(item.notes)) {
      vipFallback ??= item.notes;
    }
  }
  if (vipFallback != null) {
    return (text: vipFallback, kind: _AlertKind.vip);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Beep WAV generator — no audio asset file required
// ---------------------------------------------------------------------------

Uint8List _generateBeepWav({
  double frequency = 880.0,
  int sampleRate = 22050,
  int durationMs = 180,
}) {
  final numSamples = (sampleRate * durationMs / 1000).round();
  final data = ByteData(44 + numSamples * 2);

  // RIFF header: "RIFF"
  data.setUint8(0, 0x52); data.setUint8(1, 0x49);
  data.setUint8(2, 0x46); data.setUint8(3, 0x46);
  data.setUint32(4, 36 + numSamples * 2, Endian.little);
  data.setUint8(8, 0x57); data.setUint8(9, 0x41);
  data.setUint8(10, 0x56); data.setUint8(11, 0x45);

  // fmt chunk
  data.setUint8(12, 0x66); data.setUint8(13, 0x6D);
  data.setUint8(14, 0x74); data.setUint8(15, 0x20);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);   // PCM
  data.setUint16(22, 1, Endian.little);   // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);

  // data chunk
  data.setUint8(36, 0x64); data.setUint8(37, 0x61);
  data.setUint8(38, 0x74); data.setUint8(39, 0x61);
  data.setUint32(40, numSamples * 2, Endian.little);

  // PCM samples with 20ms linear fade-in/out envelope
  const fadeSamples = 22050 * 20 ~/ 1000;
  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    double sample = math.sin(2 * math.pi * frequency * t);
    double env = 1.0;
    if (i < fadeSamples) env = i / fadeSamples;
    if (i > numSamples - fadeSamples) env = (numSamples - i) / fadeSamples;
    final value = (sample * env * 28000).round().clamp(-32768, 32767);
    data.setInt16(44 + i * 2, value, Endian.little);
  }
  return data.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class KdsMainScreen extends ConsumerStatefulWidget {
  const KdsMainScreen({super.key});

  @override
  ConsumerState<KdsMainScreen> createState() => _KdsMainScreenState();
}

class _KdsMainScreenState extends ConsumerState<KdsMainScreen> {
  late final Timer _clockTimer;
  Set<String> _previousTicketIds = {};

  // Physical bump-bar keyboard: Space / Enter bumps the oldest ticket.
  late final FocusNode _keyFocus;

  // Audio
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _beepFilePath;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _keyFocus = FocusNode();
    _loadPrefs();
    _initBeepFile();
    // Instantiate the WS client so it starts connecting on screen mount.
    // The provider is tied to this widget's ref — the connection is torn down
    // automatically when the screen is disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(kdsWsClientProvider);
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _keyFocus.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final threshold = prefs.getInt('kds_late_threshold') ?? 10;
    final largeFont = prefs.getBool('kds_large_font') ?? false;
    final soundAlerts = prefs.getBool('kds_sound_alerts') ?? true;
    if (mounted) {
      ref.read(kdsLateThresholdProvider.notifier).state = threshold;
      ref.read(kdsLargeFontProvider.notifier).state = largeFont;
      ref.read(kdsSoundAlertsProvider.notifier).state = soundAlerts;
    }
  }

  /// Write a synthesised 880 Hz beep WAV to the temp dir once.
  Future<void> _initBeepFile() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kds_alert.wav');
      if (!file.existsSync()) {
        await file.writeAsBytes(_generateBeepWav());
      }
      _beepFilePath = file.path;
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Bump / Recall
  // -------------------------------------------------------------------------

  Future<void> _bumpTicket(String id) async {
    HapticFeedback.lightImpact();
    await ref.read(kitchenRepositoryProvider).completeTicket(id);
  }

  Future<void> _recallTicket(String id) async {
    HapticFeedback.mediumImpact();
    final repo = ref.read(kitchenRepositoryProvider);
    await repo.recallTicket(id);
  }

  /// FIRE a Gang — waiter releases the course so the kitchen starts preparing.
  /// Changes that Gang's items on the card from HOLD (dim) to active.
  ///
  /// Also pushes a scoped kitchen ticket to the ESC/POS printer in parallel
  /// (fire-and-forget) so there's a paper paper-trail at the pass for this
  /// specific course. Runs via `unawaited` — a missing/offline printer must
  /// never block the cook line.
  Future<void> _fireGang(
    KitchenTicketEntity ticket,
    GangTemplateEntity gang,
    List<KitchenTicketItemEntity> items,
    String gangLabel,
  ) async {
    HapticFeedback.mediumImpact();
    await ref.read(gangRepositoryProvider).fireGang(ticket.ticketId, gang.id);
    unawaited(_printGangFire(ticket, gang, items, gangLabel));
  }

  /// Best-effort scoped print for a single fired Gang. Mirrors the fallback
  /// print path in OrderProvider._printKitchenTicket, but narrows the item
  /// set to the gang being fired and stamps the ESC/POS courseLabel with the
  /// restaurant's configured Gang label (falls back to "Gang N").
  Future<void> _printGangFire(
    KitchenTicketEntity ticket,
    GangTemplateEntity gang,
    List<KitchenTicketItemEntity> items,
    String gangLabel,
  ) async {
    if (items.isEmpty) return;
    try {
      final useCase = ref.read(printKitchenTicketUseCaseProvider);
      await useCase(buildGangFirePayload(ticket, gang, items,
          gangLabel: gangLabel));
    } catch (_) {
      // Printer offline / misconfigured — KDS screen still has the gang.
    }
  }

  /// Advance a Gang one step forward in the lifecycle (tap on chip).
  ///   fired / inPrep → ready   (cook signals course is plated)
  ///   ready          → served  (waiter bumps the course off the card)
  Future<void> _advanceGang(
    String ticketId,
    String gangTemplateId,
    GangOrderStatus current,
  ) async {
    final repo = ref.read(gangRepositoryProvider);
    switch (current) {
      case GangOrderStatus.fired:
      case GangOrderStatus.inPrep:
        HapticFeedback.lightImpact();
        await repo.markGangReady(ticketId, gangTemplateId);
      case GangOrderStatus.ready:
        HapticFeedback.lightImpact();
        await repo.markGangServed(ticketId, gangTemplateId);
      case GangOrderStatus.pending:
      case GangOrderStatus.served:
        break; // no forward action
    }
  }

  /// Recall a Gang one step back (long-press on chip). Lets the cook fix an
  /// accidental mark-ready / bump without having to re-fire from pending.
  Future<void> _recallGang(
    String ticketId,
    String gangTemplateId,
    GangOrderStatus current,
  ) async {
    final repo = ref.read(gangRepositoryProvider);
    GangOrderStatus? target;
    switch (current) {
      case GangOrderStatus.fired:
      case GangOrderStatus.inPrep:
        target = GangOrderStatus.pending;
      case GangOrderStatus.ready:
        target = GangOrderStatus.fired;
      case GangOrderStatus.served:
        target = GangOrderStatus.ready;
      case GangOrderStatus.pending:
        target = null;
    }
    if (target == null) return;
    HapticFeedback.mediumImpact();
    await repo.recallGang(
      ticketId: ticketId,
      gangTemplateId: gangTemplateId,
      toStatus: target,
    );
  }

  // -------------------------------------------------------------------------
  // New-ticket detection + sound alert
  // -------------------------------------------------------------------------

  void _detectNewTickets(List<KitchenTicketEntity> tickets) {
    final currentIds = tickets.map((t) => t.id).toSet();
    final newIds = currentIds.difference(_previousTicketIds);
    if (newIds.isNotEmpty && _previousTicketIds.isNotEmpty) {
      _onNewTicket();
    }
    _previousTicketIds = currentIds;
  }

  void _onNewTicket() {
    HapticFeedback.vibrate();
    if (ref.read(kdsSoundAlertsProvider)) {
      _playBeep();
    }
  }

  Future<void> _playBeep() async {
    if (_beepFilePath == null) return;
    try {
      await _audioPlayer.play(DeviceFileSource(_beepFilePath!));
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(activeKitchenTicketsProvider);
    final completedAsync = ref.watch(completedTodayProvider);
    final stationFilter = ref.watch(kdsStationFilterProvider);
    final largeFont = ref.watch(kdsLargeFontProvider);
    final lateThreshold = ref.watch(kdsLateThresholdProvider);
    final gangMap = ref.watch(gangTemplateMapProvider);
    // Settings drive Gang UI policy: gangsEnabled, maxGangs cap, and the
    // per-ordinal display labels (gangLabels). Defaults keep the screen
    // usable even while the repo is still loading.
    final settings = ref.watch(restaurantSettingsProvider).valueOrNull ??
        const RestaurantSettings();

    // Surface server-pushed ticket notifications. The Drift stream is the
    // source of truth for the grid, so we only need to beep + flash a snack
    // here — no DB writes.
    ref.listen<KdsEvent?>(kdsLatestEventProvider, (prev, next) {
      if (next == null || next == prev) return;
      if (next.type == 'new_ticket') {
        _onNewTicket();
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'New ticket pushed from server'
              '${next.orderNumber != null ? ' (#${next.orderNumber})' : ''}',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return KeyboardListener(
      focusNode: _keyFocus,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.enter) {
            final tickets = ticketsAsync.valueOrNull ?? const [];
            if (tickets.isNotEmpty) _bumpTicket(tickets.first.id);
          }
        }
      },
      child: ticketsAsync.when(
        data: (allTickets) {
          _detectNewTickets(allTickets);
          final tickets = stationFilter == null
              ? allTickets
              : allTickets
                  .where((t) => t.printerGroup == stationFilter)
                  .toList();
          final completed = completedAsync.valueOrNull ?? 0;
          return _buildScaffold(
            tickets,
            completed,
            largeFont: largeFont,
            lateThreshold: lateThreshold,
            gangMap: gangMap,
            settings: settings,
          );
        },
        loading: () => _buildScaffold(const [], 0,
            largeFont: false,
            lateThreshold: 10,
            gangMap: const {},
            settings: settings),
        error: (e, _) => _buildScaffold(const [], 0,
            largeFont: false,
            lateThreshold: 10,
            gangMap: const {},
            settings: settings,
            error: e.toString()),
      ),
    );
  }

  Widget _buildScaffold(
    List<KitchenTicketEntity> tickets,
    int completed, {
    required bool largeFont,
    required int lateThreshold,
    required Map<String, GangTemplateEntity> gangMap,
    required RestaurantSettings settings,
    bool loading = false,
    String? error,
  }) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim, // #0B0E14
      body: Column(
        children: [
          _buildTopBar(tickets, completed),
          _buildStationChipBar(tickets),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? _buildError(error)
                    : _buildGrid(tickets,
                        largeFont: largeFont,
                        lateThreshold: lateThreshold,
                        gangMap: gangMap,
                        settings: settings),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar(List<KitchenTicketEntity> tickets, int completed) {
    final pending =
        tickets.where((t) => t.status == KitchenTicketStatus.pending).length;
    final cooking =
        tickets.where((t) => t.status == KitchenTicketStatus.preparing).length;

    return Container(
      height: 72,
      color: AppColors.surface, // #151720
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Logo mark
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF528DFF)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.restaurant,
              size: 18,
              color: Color(0xFF001944),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'KDS',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 32),
          _statChip('PENDING', '$pending', AppColors.textPrimary),
          const SizedBox(width: 16),
          _statChip('COOKING', '$cooking', const Color(0xFFFBBF24)),
          const SizedBox(width: 16),
          _statChip('DONE TODAY', '$completed', AppColors.green), // #69F6B8
          const Spacer(),
          _buildLiveIndicator(),
          const SizedBox(width: 12),
          _topBarIcon(Icons.settings_outlined, 'Settings',
              () => context.go(KdsRoutes.settings)),
          const SizedBox(width: 8),
          _topBarIcon(Icons.logout, 'Logout', () => context.go(KdsRoutes.login)),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color valueColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 2.0,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _topBarIcon(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Station chip bar
  //
  // Sprint 3.2: replaces the old separate-route station-filter screen with an
  // inline chip row. "All" chip clears the filter; a station chip sets the
  // filter to that station's code (matching [KitchenTicket.printerGroup]).
  // Counts shown on each chip are computed from the UNFILTERED active-ticket
  // stream so the numbers stay honest even while a filter is active.
  // -------------------------------------------------------------------------

  Widget _buildStationChipBar(List<KitchenTicketEntity> _) {
    final stationsAsync = ref.watch(stationsProvider);
    final allTicketsAsync = ref.watch(activeKitchenTicketsProvider);
    final filter = ref.watch(kdsStationFilterProvider);

    final all = allTicketsAsync.valueOrNull ?? const <KitchenTicketEntity>[];
    final countByCode = <String, int>{};
    for (final t in all) {
      countByCode[t.printerGroup] = (countByCode[t.printerGroup] ?? 0) + 1;
    }

    final stations = stationsAsync.valueOrNull ?? const <StationEntity>[];
    final sorted = [...stations]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    void select(String? code) =>
        ref.read(kdsStationFilterProvider.notifier).state = code;

    return Container(
      height: 52,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _stationChip(
            label: 'All',
            icon: Icons.grid_view_rounded,
            count: all.length,
            selected: filter == null,
            onTap: () => select(null),
          ),
          for (final s in sorted)
            _stationChip(
              label: s.name,
              icon: s.iconData,
              accent: s.accentColor,
              count: countByCode[s.code] ?? 0,
              selected: filter == s.code,
              onTap: () => select(s.code),
            ),
        ],
      ),
    );
  }

  Widget _stationChip({
    required String label,
    required IconData icon,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    Color? accent,
  }) {
    final accentColor = accent ?? AppColors.primary;
    final tint = selected ? accentColor : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected
                  ? accentColor.withValues(alpha: 0.15)
                  : AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? accentColor.withValues(alpha: 0.6)
                    : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: tint),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? tint : AppColors.textPrimary,
                    letterSpacing: 0.4,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? accentColor.withValues(alpha: 0.25)
                          : AppColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: selected ? tint : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Station pill shown on the ticket card header. Resolves the station's
  /// name + accent color from [stationByCodeProvider]; falls back to the raw
  /// code in uppercase when no row matches (e.g. a ticket routed before the
  /// station row was created).
  Widget _buildStationBadge(String code) {
    final byCode = ref.watch(stationByCodeProvider);
    final station = byCode[code];
    final accent = station?.accentColor ?? AppColors.textSecondary;
    final label = (station?.name ?? code).toUpperCase();
    final icon = station?.iconData ?? Icons.restaurant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  /// LIVE indicator — small coloured dot + label showing the WebSocket state.
  ///   connected    → green + "LIVE"
  ///   connecting   → amber + "LINK…"
  ///   disconnected → red + "OFFLINE"
  Widget _buildLiveIndicator() {
    final wsState = ref.watch(kdsWsStateProvider);
    final (Color color, String label, String tooltip) = switch (wsState) {
      KdsWsState.connected => (
        AppColors.green,
        'LIVE',
        'Real-time hub connected',
      ),
      KdsWsState.connecting => (
        const Color(0xFFFBBF24),
        'LINK',
        'Connecting to real-time hub…',
      ),
      KdsWsState.disconnected => (
        AppColors.red,
        'OFFLINE',
        'Real-time hub offline — falling back to LAN sync',
      ),
    };
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Ticket grid
  // -------------------------------------------------------------------------

  Widget _buildGrid(
    List<KitchenTicketEntity> tickets, {
    required bool largeFont,
    required int lateThreshold,
    required Map<String, GangTemplateEntity> gangMap,
    required RestaurantSettings settings,
  }) {
    if (tickets.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 72,
              color: AppColors.green, // #69F6B8 — all-clear is green
            ),
            SizedBox(height: 20),
            Text(
              'All clear — no active tickets',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minCardWidth = largeFont ? 340.0 : 280.0;
          final cols =
              (constraints.maxWidth / minCardWidth).floor().clamp(1, 6);
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: largeFont ? 0.65 : 0.72,
            ),
            itemCount: tickets.length,
            itemBuilder: (context, i) => _buildTicketCard(
              tickets[i],
              largeFont: largeFont,
              lateThreshold: lateThreshold,
              gangMap: gangMap,
              settings: settings,
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Ticket card
  // -------------------------------------------------------------------------

  Widget _buildTicketCard(
    KitchenTicketEntity ticket, {
    required bool largeFont,
    required int lateThreshold,
    required Map<String, GangTemplateEntity> gangMap,
    required RestaurantSettings settings,
  }) {
    final urgency = getTicketUrgency(ticket, lateThreshold);
    final borderColor = _urgencyBorderColor(urgency);
    final badgeColor = _urgencyBadgeColor(urgency);
    final titleSize = largeFont ? 34.0 : 26.0;
    final itemSize = largeFont ? 17.0 : 14.0;
    final modSize = largeFont ? 14.0 : 12.0;

    return GestureDetector(
      onTap: () => _bumpTicket(ticket.id),
      onLongPress: () => _recallTicket(ticket.id),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow, // #191B22
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 16,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Urgency top-strip (green / yellow / red)
            Container(height: 5, color: borderColor),

            // Allergy / VIP alert banner — kitchen safety first
            if (_ticketAlertText(ticket) != null)
              _buildAlertBanner(_ticketAlertText(ticket)!, largeFont: largeFont),

            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              color: AppColors.surfaceContainerHigh.withValues(alpha: 0.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.tableName ?? '#${ticket.orderNumber}',
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: -1.5,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Order ${ticket.orderNumber}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStationBadge(ticket.printerGroup),
                          ],
                        ),
                        if (ticket.waiterName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Server: ${ticket.waiterName}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textDim,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Timer text inherits urgency color: green→yellow→red
                      Text(
                        _formatElapsed(ticket),
                        style: TextStyle(
                          fontSize: largeFont ? 24 : 20,
                          fontWeight: FontWeight.w800,
                          color: borderColor,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _urgencyLabel(urgency),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: borderColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Items list — grouped by Gang, with per-Gang hold/fire/ready state.
            // Consumer scopes gang-state rebuilds to this section so the whole
            // grid doesn't re-render when a single card's state flips.
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  final statesAsync =
                      ref.watch(orderGangStatesProvider(ticket.ticketId));
                  final gangStates = statesAsync.valueOrNull ??
                      const <String, OrderGangStateEntity>{};
                  return _buildGangGroupedItems(
                    ticket,
                    gangMap: gangMap,
                    gangStates: gangStates,
                    largeFont: largeFont,
                    itemSize: itemSize,
                    modSize: modSize,
                    settings: settings,
                  );
                },
              ),
            ),

            // BUMP button — green (#69F6B8) for ready/sent state
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                width: double.infinity,
                height: largeFont ? 64 : 52,
                decoration: BoxDecoration(
                  color: AppColors.green, // #69F6B8
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 20,
                      color: AppColors.onGreen, // #003322
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'BUMP',
                      style: TextStyle(
                        fontSize: largeFont ? 20 : 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.onGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Gang-grouped items list
  // -------------------------------------------------------------------------

  /// Wraps the top-level [buildGangGroupedItemsList] and threads the state's
  /// fire / advance / recall callbacks into the view.
  Widget _buildGangGroupedItems(
    KitchenTicketEntity ticket, {
    required Map<String, GangTemplateEntity> gangMap,
    required Map<String, OrderGangStateEntity> gangStates,
    required bool largeFont,
    required double itemSize,
    required double modSize,
    required RestaurantSettings settings,
  }) {
    return buildGangGroupedItemsList(
      ticket,
      gangMap: gangMap,
      gangStates: gangStates,
      largeFont: largeFont,
      itemSize: itemSize,
      modSize: modSize,
      settings: settings,
      onFire: _fireGang,
      onAdvance: _advanceGang,
      onRecall: _recallGang,
    );
  }

  Widget _buildAlertBanner(String text, {required bool largeFont}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: largeFont ? 10 : 8,
      ),
      color: AppColors.red,
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: largeFont ? 22 : 18, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: largeFont ? 14 : 12,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Error
  // -------------------------------------------------------------------------

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 52, color: AppColors.red),
          const SizedBox(height: 12),
          Text(
            'KDS Error: $message',
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Footer
  // -------------------------------------------------------------------------

  Widget _buildFooter() {
    return Container(
      height: 40,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _footerDot(AppColors.green, 'Live sync active'), // #69F6B8
          const SizedBox(width: 24),
          _footerDot(AppColors.primary, // #90ABFF
              'Tap chip = advance gang  •  Long-press chip = recall  •  Tap card = bump ticket'),
          const Spacer(),
          const Text(
            'GASTROCORE KDS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textDim,
              letterSpacing: 2.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerDot(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Gang-grouped items list — testable top-level builder
// ---------------------------------------------------------------------------

/// Callback invoked when the cook taps a pending Gang's FIRE button.
typedef OnFireGang = void Function(
  KitchenTicketEntity ticket,
  GangTemplateEntity gang,
  List<KitchenTicketItemEntity> items,
  String gangLabel,
);

/// Callback invoked when the cook taps a non-pending Gang chip to advance
/// lifecycle: fired/inPrep → ready → served.
typedef OnAdvanceGang = void Function(
  String ticketId,
  String gangTemplateId,
  GangOrderStatus current,
);

/// Callback invoked on long-press to recall a Gang one step in the lifecycle.
typedef OnRecallGang = void Function(
  String ticketId,
  String gangTemplateId,
  GangOrderStatus current,
);

/// Builds the per-ticket Gang-grouped items list.
///
/// Policy is restaurant-configurable via [RestaurantSettings]:
///   - `gangsEnabled == false` → flat list ordered by arrival; no headers,
///     no FIRE buttons. Used by bar / fast-casual flows that don't serve
///     courses. Ticket-level bump still works.
///   - `gangsEnabled == true`  → items grouped by Gang sortOrder, capped at
///     `settings.maxGangs` (1..5). Beyond-cap gangs fall into "Andere".
///
/// Extracted to top-level with callback parameters so widget tests can mount
/// the view directly without spinning up the whole KDS screen.
@visibleForTesting
Widget buildGangGroupedItemsList(
  KitchenTicketEntity ticket, {
  required Map<String, GangTemplateEntity> gangMap,
  required Map<String, OrderGangStateEntity> gangStates,
  required bool largeFont,
  required double itemSize,
  required double modSize,
  required RestaurantSettings settings,
  required OnFireGang onFire,
  required OnAdvanceGang onAdvance,
  required OnRecallGang onRecall,
}) {
  final items = ticket.items;

  // Restaurant turned Gang grouping off → flat arrival-order list.
  if (!settings.gangsEnabled) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      children: [
        for (final item in items)
          _buildItemRowTop(
            item,
            largeFont: largeFont,
            itemSize: itemSize,
            modSize: modSize,
            gangStatus: null,
          ),
      ],
    );
  }

  // Only render gangs within the configured cap. Anything beyond
  // settings.maxGangs is treated as ungrouped so the card stays focused.
  final int cap = settings.maxGangs;
  bool isRenderableGang(String? gangId) {
    if (gangId == null) return false;
    final g = gangMap[gangId];
    return g != null && g.sortOrder <= cap;
  }

  final hasGangs =
      gangMap.isNotEmpty && items.any((i) => isRenderableGang(i.gangId));

  final widgets = <Widget>[];

  if (!hasGangs) {
    // No gang data — flat list (legacy / simple mode)
    for (final item in items) {
      widgets.add(_buildItemRowTop(
        item,
        largeFont: largeFont,
        itemSize: itemSize,
        modSize: modSize,
        gangStatus: null,
      ));
    }
  } else {
    // Group items by gangId (null bucket = ungrouped / out-of-cap)
    final grouped = <String?, List<KitchenTicketItemEntity>>{};
    for (final item in items) {
      final key = isRenderableGang(item.gangId) ? item.gangId : null;
      grouped.putIfAbsent(key, () => []).add(item);
    }

    // Sort groups: known gangs by sortOrder, then null (ungrouped) last
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1;
        if (b == null) return -1;
        final orderA = gangMap[a]?.sortOrder ?? 99;
        final orderB = gangMap[b]?.sortOrder ?? 99;
        return orderA.compareTo(orderB);
      });

    for (final key in sortedKeys) {
      final groupItems = grouped[key]!;
      final gang = key != null ? gangMap[key] : null;
      final state = key != null ? gangStates[key] : null;
      final status = state?.status ?? GangOrderStatus.pending;

      // Resolve the display label once — used for both the header text
      // and the ESC/POS courseLabel stamp.
      final String gangLabel = gang != null
          ? settings.gangLabelFor(gang.sortOrder)
          : 'Andere';

      widgets.add(_buildGangHeaderTop(
        gang,
        label: gangLabel,
        status: status,
        firedAt: state?.firedAt,
        largeFont: largeFont,
        onFire: (gang != null && status == GangOrderStatus.pending)
            ? () => onFire(ticket, gang, groupItems, gangLabel)
            : null,
        onAdvance: (gang != null &&
                (status == GangOrderStatus.fired ||
                    status == GangOrderStatus.inPrep ||
                    status == GangOrderStatus.ready))
            ? () => onAdvance(ticket.ticketId, gang.id, status)
            : null,
        onRecall: (gang != null && status != GangOrderStatus.pending)
            ? () => onRecall(ticket.ticketId, gang.id, status)
            : null,
      ));

      // Per-gang alert banner — red for allergy, gold for VIP.
      final groupAlert = _groupAlert(groupItems);
      if (groupAlert != null) {
        widgets.add(_buildGangAlertBannerTop(
          text: groupAlert.text,
          kind: groupAlert.kind,
          largeFont: largeFont,
        ));
      }

      // Items in this group — dimmed when Gang is still on HOLD
      for (final item in groupItems) {
        widgets.add(_buildItemRowTop(
          item,
          largeFont: largeFont,
          itemSize: itemSize,
          modSize: modSize,
          gangStatus: gang != null ? status : null,
        ));
      }

      widgets.add(const SizedBox(height: 4));
    }
  }

  return ListView(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
    children: widgets,
  );
}

// ---------------------------------------------------------------------------
// Internal top-level widget builders (moved out of State so the view is
// reachable from widget tests; same visuals as before).
// ---------------------------------------------------------------------------

Widget _buildGangHeaderTop(
  GangTemplateEntity? gang, {
  required String label,
  required GangOrderStatus status,
  required DateTime? firedAt,
  required bool largeFont,
  VoidCallback? onFire,
  VoidCallback? onAdvance,
  VoidCallback? onRecall,
}) {
  final baseColor = gang?.flutterColor ?? AppColors.textSecondary;
  final Color headerColor = switch (status) {
    GangOrderStatus.pending => AppColors.textDim,
    GangOrderStatus.fired => baseColor,
    GangOrderStatus.inPrep => baseColor,
    GangOrderStatus.ready => AppColors.green,
    GangOrderStatus.served => AppColors.textDim,
  };

  final bool showTimer = firedAt != null &&
      (status == GangOrderStatus.fired || status == GangOrderStatus.inPrep);

  return Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 4),
    child: Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: headerColor,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: largeFont ? 11 : 9,
            fontWeight: FontWeight.w800,
            color: headerColor,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: headerColor.withValues(alpha: 0.25),
          ),
        ),
        if (showTimer) ...[
          const SizedBox(width: 8),
          _buildGangFiredTimerTop(firedAt, largeFont: largeFont),
        ],
        const SizedBox(width: 8),
        _buildGangStatusTrailingTop(
          status: status,
          baseColor: baseColor,
          largeFont: largeFont,
          onFire: onFire,
          onAdvance: onAdvance,
          onRecall: onRecall,
        ),
      ],
    ),
  );
}

Widget _buildGangFiredTimerTop(DateTime firedAt, {required bool largeFont}) {
  final elapsed = DateTime.now().difference(firedAt);
  final minutes = elapsed.inMinutes;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

  final Color color;
  if (minutes >= 10) {
    color = AppColors.red;
  } else if (minutes >= 5) {
    color = const Color(0xFFFBBF24);
  } else {
    color = AppColors.textPrimary;
  }

  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: largeFont ? 6 : 4,
      vertical: largeFont ? 2 : 1,
    ),
    child: Text(
      '$mm:$ss',
      style: TextStyle(
        fontSize: largeFont ? 11 : 9,
        fontWeight: FontWeight.w900,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0.5,
      ),
    ),
  );
}

Widget _buildGangStatusTrailingTop({
  required GangOrderStatus status,
  required Color baseColor,
  required bool largeFont,
  VoidCallback? onFire,
  VoidCallback? onAdvance,
  VoidCallback? onRecall,
}) {
  if (status == GangOrderStatus.pending && onFire != null) {
    return GestureDetector(
      onTap: onFire,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: largeFont ? 10 : 8,
          vertical: largeFont ? 5 : 3,
        ),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department,
              size: largeFont ? 14 : 12,
              color: AppColors.onGreen,
            ),
            const SizedBox(width: 4),
            Text(
              'FIRE',
              style: TextStyle(
                fontSize: largeFont ? 11 : 9,
                fontWeight: FontWeight.w900,
                color: AppColors.onGreen,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  final (String label, Color bg, Color fg) = switch (status) {
    GangOrderStatus.pending => (
      'HOLD',
      AppColors.surfaceContainerHigh,
      AppColors.textDim,
    ),
    GangOrderStatus.fired => (
      'FIRED',
      baseColor.withValues(alpha: 0.18),
      baseColor,
    ),
    GangOrderStatus.inPrep => (
      'IN PREP',
      baseColor.withValues(alpha: 0.18),
      baseColor,
    ),
    GangOrderStatus.ready => (
      'READY',
      AppColors.greenDim,
      AppColors.green,
    ),
    GangOrderStatus.served => (
      'SERVED',
      AppColors.surfaceContainerHigh,
      AppColors.textDim,
    ),
  };

  IconData? hintIcon;
  if (status == GangOrderStatus.fired ||
      status == GangOrderStatus.inPrep ||
      status == GangOrderStatus.ready) {
    hintIcon = Icons.check_rounded;
  } else if (status == GangOrderStatus.served) {
    hintIcon = Icons.undo_rounded;
  }

  Widget chip = Container(
    padding: EdgeInsets.symmetric(
      horizontal: largeFont ? 8 : 6,
      vertical: largeFont ? 4 : 2,
    ),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hintIcon != null) ...[
          Icon(hintIcon, size: largeFont ? 12 : 10, color: fg),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: largeFont ? 10 : 8,
            fontWeight: FontWeight.w900,
            color: fg,
            letterSpacing: 1.5,
          ),
        ),
      ],
    ),
  );

  if (onAdvance == null && onRecall == null) return chip;

  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onAdvance,
    onLongPress: onRecall,
    child: chip,
  );
}

Widget _buildGangAlertBannerTop({
  required String text,
  required _AlertKind kind,
  required bool largeFont,
}) {
  final (Color bg, Color fg, IconData icon, String tag) = switch (kind) {
    _AlertKind.allergy => (
      AppColors.red,
      Colors.white,
      Icons.warning_amber_rounded,
      'ALLERGY',
    ),
    _AlertKind.vip => (
      const Color(0xFFE0B24A),
      const Color(0xFF2A1A00),
      Icons.star_rounded,
      'VIP',
    ),
    _AlertKind.none => (
      AppColors.red,
      Colors.white,
      Icons.warning_amber_rounded,
      'ALERT',
    ),
  };

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: largeFont ? 10 : 8,
        vertical: largeFont ? 6 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: largeFont ? 18 : 14, color: fg),
          const SizedBox(width: 6),
          Text(
            tag,
            style: TextStyle(
              fontSize: largeFont ? 11 : 9,
              fontWeight: FontWeight.w900,
              color: fg,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: largeFont ? 13 : 11,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: 0.6,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildItemRowTop(
  KitchenTicketItemEntity item, {
  required bool largeFont,
  required double itemSize,
  required double modSize,
  required GangOrderStatus? gangStatus,
}) {
  final mods = item.modifiersText
          ?.split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList() ??
      const [];

  final bool isHeld = gangStatus == GangOrderStatus.pending;
  final Color primaryText =
      isHeld ? AppColors.textDim : AppColors.textPrimary;
  final Color secondaryText =
      isHeld ? AppColors.textDim : AppColors.textSecondary;

  Widget row = Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: largeFont ? 30 : 24,
          height: largeFont ? 30 : 24,
          decoration: BoxDecoration(
            color: AppColors.accentDim,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              item.quantity == item.quantity.roundToDouble()
                  ? item.quantity.toInt().toString()
                  : item.quantity.toString(),
              style: TextStyle(
                fontSize: largeFont ? 16 : 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: TextStyle(
                  fontSize: itemSize,
                  fontWeight: FontWeight.w700,
                  color: primaryText,
                  height: 1.3,
                ),
              ),
              ...mods.map(
                (mod) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '\u2022 $mod',
                    style: TextStyle(fontSize: modSize, color: secondaryText),
                  ),
                ),
              ),
              if (item.notes != null && item.notes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _isAlertNote(item.notes)
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '\u26A0 ${item.notes}',
                            style: TextStyle(
                              fontSize: modSize + 1,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        )
                      : Text(
                          '\u26A0 ${item.notes}',
                          style: TextStyle(
                            fontSize: modSize,
                            color: isHeld
                                ? AppColors.textDim
                                : AppColors.orange,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  return isHeld ? Opacity(opacity: 0.55, child: row) : row;
}

// ---------------------------------------------------------------------------
// Gang-fire ESC/POS payload builder
// ---------------------------------------------------------------------------

/// Builds the ESC/POS payload for a gang-fire print.
///
/// Top-level so the payload shape is unit-testable without spinning up
/// Riverpod or a PrinterService. The courseLabel stamps the gang label
/// (e.g. "Gang 1") onto the Bestellbon so the pass can match paper to the
/// cook's card at a glance.
@visibleForTesting
KitchenTicketData buildGangFirePayload(
  KitchenTicketEntity ticket,
  GangTemplateEntity gang,
  List<KitchenTicketItemEntity> items, {
  String? gangLabel,
}) {
  return KitchenTicketData(
    tableNo: ticket.tableName ?? '#${ticket.orderNumber}',
    orderNo: ticket.orderNumber,
    waiterName: ticket.waiterName,
    courseLabel: gangLabel ?? 'Gang ${gang.sortOrder}',
    printerGroup: ticket.printerGroup,
    dateTime: DateTime.now(),
    items: items
        .map((i) => KitchenItem(
              name: i.productName,
              quantity: i.quantity,
              modifiers: i.modifiersText
                      ?.split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList() ??
                  const [],
              notes: i.notes,
            ))
        .toList(),
  );
}
