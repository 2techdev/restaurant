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

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/gang/domain/entities/gang_template_entity.dart';
import 'package:gastrocore_pos/features/gang/presentation/providers/gang_provider.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';
import 'package:gastrocore_pos/features/kds_app/presentation/providers/kds_providers.dart';
import 'package:gastrocore_pos/features/kds_app/router/kds_router.dart';

// ---------------------------------------------------------------------------
// Urgency helpers — green → yellow → red timer coding
// ---------------------------------------------------------------------------

enum _Urgency { fresh, inProgress, late }

_Urgency _getUrgency(KitchenTicketEntity ticket, int lateThresholdMin) {
  final elapsed = DateTime.now().difference(ticket.sentAt);
  if (elapsed.inMinutes >= lateThresholdMin) return _Urgency.late;
  if (ticket.status == KitchenTicketStatus.preparing) return _Urgency.inProgress;
  return _Urgency.fresh;
}

// Green (#69F6B8) = ready/sent/fresh  •  Yellow = cooking  •  Red (#FF6F7E) = overdue
Color _urgencyBorderColor(_Urgency u) => switch (u) {
      _Urgency.fresh => AppColors.green,           // #69F6B8
      _Urgency.inProgress => const Color(0xFFFBBF24), // amber
      _Urgency.late => AppColors.red,              // #FF6F7E
    };

Color _urgencyBadgeColor(_Urgency u) => switch (u) {
      _Urgency.fresh => AppColors.greenDim,        // 10% tint of #69F6B8
      _Urgency.inProgress => const Color(0x1AFBBF24),
      _Urgency.late => AppColors.redDim,           // 10% tint of #FF6F7E
    };

String _urgencyLabel(_Urgency u) => switch (u) {
      _Urgency.fresh => 'NEW',
      _Urgency.inProgress => 'COOKING',
      _Urgency.late => 'LATE',
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

/// Returns true if the note contains an allergy, VIP, or dietary alert keyword.
/// Matches EN/DE/TR/FR variants so kitchen staff see the banner regardless of
/// waiter input language.
bool _isAlertNote(String? notes) {
  if (notes == null || notes.isEmpty) return false;
  final n = notes.toLowerCase();
  return n.contains('allerg') || // allergy/allergen/allergie/allergique
      n.contains('alerji') ||    // TR
      n.contains('vip') ||
      n.contains('nut') ||       // nut/peanut/hazelnut
      n.contains('gluten') ||
      n.contains('lactose') ||
      n.contains('laktoz') ||    // TR
      n.contains('kosher') ||
      n.contains('halal') ||
      n.contains('vegan');
}

/// Returns the first alert-bearing note text on the ticket, or null.
String? _ticketAlertText(KitchenTicketEntity ticket) {
  for (final item in ticket.items) {
    if (_isAlertNote(item.notes)) return item.notes;
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
  Future<void> _fireGang(String ticketId, String gangTemplateId) async {
    HapticFeedback.mediumImpact();
    await ref
        .read(gangRepositoryProvider)
        .fireGang(ticketId, gangTemplateId);
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
          );
        },
        loading: () => _buildScaffold(const [], 0,
            largeFont: false, lateThreshold: 10, gangMap: const {}),
        error: (e, _) => _buildScaffold(const [], 0,
            largeFont: false,
            lateThreshold: 10,
            gangMap: const {},
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
    bool loading = false,
    String? error,
  }) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim, // #0B0E14
      body: Column(
        children: [
          _buildTopBar(tickets, completed),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? _buildError(error)
                    : _buildGrid(tickets,
                        largeFont: largeFont,
                        lateThreshold: lateThreshold,
                        gangMap: gangMap),
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
    final stationFilter = ref.watch(kdsStationFilterProvider);
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
          const SizedBox(width: 4),
          if (stationFilter != null)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                stationFilter.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary, // #90ABFF for active items
                  letterSpacing: 1.5,
                ),
              ),
            ),
          const SizedBox(width: 32),
          _statChip('PENDING', '$pending', AppColors.textPrimary),
          const SizedBox(width: 16),
          _statChip('COOKING', '$cooking', const Color(0xFFFBBF24)),
          const SizedBox(width: 16),
          _statChip('DONE TODAY', '$completed', AppColors.green), // #69F6B8
          const Spacer(),
          _topBarIcon(Icons.filter_list, 'Station filter',
              () => context.go(KdsRoutes.stationFilter)),
          const SizedBox(width: 8),
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
  // Ticket grid
  // -------------------------------------------------------------------------

  Widget _buildGrid(
    List<KitchenTicketEntity> tickets, {
    required bool largeFont,
    required int lateThreshold,
    required Map<String, GangTemplateEntity> gangMap,
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
  }) {
    final urgency = _getUrgency(ticket, lateThreshold);
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
                        Text(
                          'Order ${ticket.orderNumber}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
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

  /// Builds the items list for a ticket card, grouped by Gang when available.
  ///
  /// Policy: **max 3 courses** (sortOrder ≤ 3). Items in Gangs with sortOrder
  /// beyond 3 or without a known Gang fall into an "Andere" (ungrouped) block.
  ///
  /// Per-Gang lifecycle (from [gangStates]) drives the visual treatment:
  ///   - pending (HOLD) → dim/gray group, FIRE button on header
  ///   - fired / in_prep → full gang color, "FIRED" chip
  ///   - ready           → green accent, "READY" chip
  ///   - served          → muted (items are about to leave the card)
  Widget _buildGangGroupedItems(
    KitchenTicketEntity ticket, {
    required Map<String, GangTemplateEntity> gangMap,
    required Map<String, OrderGangStateEntity> gangStates,
    required bool largeFont,
    required double itemSize,
    required double modSize,
  }) {
    final items = ticket.items;

    // Only render gangs within the 3-course cap. Anything beyond sortOrder 3
    // is treated as ungrouped so the kitchen card stays focused on the meal.
    bool isRenderableGang(String? gangId) {
      if (gangId == null) return false;
      final g = gangMap[gangId];
      return g != null && g.sortOrder <= 3;
    }

    final hasGangs = gangMap.isNotEmpty &&
        items.any((i) => isRenderableGang(i.gangId));

    final widgets = <Widget>[];

    if (!hasGangs) {
      // No gang data — flat list (legacy / simple mode)
      for (final item in items) {
        widgets.add(_buildItemRow(
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

        // Gang header row — carries status chip + optional FIRE button.
        // firedAt drives the in-group timer once the gang is firing.
        widgets.add(_buildGangHeader(
          gang,
          status: status,
          firedAt: state?.firedAt,
          largeFont: largeFont,
          onFire: (gang != null && status == GangOrderStatus.pending)
              ? () => _fireGang(ticket.ticketId, gang.id)
              : null,
        ));

        // Items in this group — dimmed when Gang is still on HOLD
        for (final item in groupItems) {
          widgets.add(_buildItemRow(
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

  /// Gang header row.
  ///
  /// Color and trailing widget vary by [status]:
  ///   - pending        → gray header + colored FIRE button (if [onFire] set)
  ///   - fired / inPrep → gang color + "FIRED" chip + MM:SS timer (5 min amber,
  ///                      10 min red — the hold-time tells the cook if this
  ///                      gang is falling behind the ticket's target pace)
  ///   - ready          → green + "READY" chip
  ///   - served         → dim + "SERVED" chip
  Widget _buildGangHeader(
    GangTemplateEntity? gang, {
    required GangOrderStatus status,
    required DateTime? firedAt,
    required bool largeFont,
    VoidCallback? onFire,
  }) {
    final baseColor = gang?.flutterColor ?? AppColors.textSecondary;
    final name = gang?.name ?? 'Andere';

    // Resolve header foreground based on lifecycle status.
    final Color headerColor = switch (status) {
      GangOrderStatus.pending => AppColors.textDim,
      GangOrderStatus.fired => baseColor,
      GangOrderStatus.inPrep => baseColor,
      GangOrderStatus.ready => AppColors.green,
      GangOrderStatus.served => AppColors.textDim,
    };

    final bool showTimer = firedAt != null &&
        (status == GangOrderStatus.fired ||
            status == GangOrderStatus.inPrep);

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
            name.toUpperCase(),
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
            _buildGangFiredTimer(firedAt, largeFont: largeFont),
          ],
          const SizedBox(width: 8),
          _buildGangStatusTrailing(
            status: status,
            baseColor: baseColor,
            largeFont: largeFont,
            onFire: onFire,
          ),
        ],
      ),
    );
  }

  /// Per-gang fired-time readout.
  ///
  /// Color thresholds surface hold-time drift to the cook at a glance:
  ///   < 5 min  → text-primary (on track)
  ///   5–9 min  → amber (watch)
  ///   ≥ 10 min → red (pushing back the course)
  ///
  /// Re-rendered by the screen's 1-second clock tick.
  Widget _buildGangFiredTimer(DateTime firedAt, {required bool largeFont}) {
    final elapsed = DateTime.now().difference(firedAt);
    final minutes = elapsed.inMinutes;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    final Color color;
    if (minutes >= 10) {
      color = AppColors.red;
    } else if (minutes >= 5) {
      color = const Color(0xFFFBBF24); // amber
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

  /// Trailing widget on the Gang header: FIRE button when pending, otherwise
  /// a status chip (FIRED / READY / SERVED).
  Widget _buildGangStatusTrailing({
    required GangOrderStatus status,
    required Color baseColor,
    required bool largeFont,
    VoidCallback? onFire,
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

    // Non-pending states → status chip only.
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

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: largeFont ? 8 : 6,
        vertical: largeFont ? 4 : 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: largeFont ? 10 : 8,
          fontWeight: FontWeight.w900,
          color: fg,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildItemRow(
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

    // Items in a pending (HOLD) gang are rendered gray so the cook sees at a
    // glance that they're not to be started yet. Alert notes (allergy/VIP)
    // still use their full red treatment — safety trumps hold styling.
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
          // Quantity badge
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
                      style: TextStyle(
                          fontSize: modSize, color: secondaryText),
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

    // Reinforce the HOLD treatment with a slight opacity fade.
    return isHeld ? Opacity(opacity: 0.55, child: row) : row;
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
              'Tap = bump  •  Long-press = recall  •  Space/Enter = bump oldest'),
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
