/// Kitchen Display Screen (KDS) — live data from Drift DB.
///
/// Replaces the previous hardcoded demo data with reactive streams via
/// [activeKitchenTicketsProvider]. Tickets appear automatically when the
/// POS sends an order to kitchen; tapping READY bumps the ticket to 'served'.
library;

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/kitchen/domain/entities/kitchen_ticket_entity.dart';
import 'package:gastrocore_pos/features/kitchen/presentation/providers/kitchen_provider.dart';

// ---------------------------------------------------------------------------
// Urgency
// ---------------------------------------------------------------------------

enum _Urgency { normal, warning, critical }

_Urgency _getUrgency(KitchenTicketEntity ticket) {
  final elapsed = DateTime.now().difference(ticket.sentAt);
  if (elapsed.inMinutes >= 20) return _Urgency.critical;
  if (elapsed.inMinutes >= 10) return _Urgency.warning;
  return _Urgency.normal;
}

Color _urgencyColor(_Urgency urgency) {
  return switch (urgency) {
    _Urgency.normal => const Color(0xFF4ADE80),
    _Urgency.warning => const Color(0xFFFB923C),
    _Urgency.critical => const Color(0xFFEF4444),
  };
}

String _urgencyLabel(_Urgency urgency) {
  return switch (urgency) {
    _Urgency.normal => 'On Time',
    _Urgency.warning => 'Warning',
    _Urgency.critical => 'Delayed',
  };
}

String _formatElapsed(KitchenTicketEntity ticket) {
  final elapsed = DateTime.now().difference(ticket.sentAt);
  final mins = elapsed.inMinutes.toString().padLeft(2, '0');
  final secs = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$mins:$secs';
}

// ---------------------------------------------------------------------------
// Allergy / VIP detection — fine-dining critical safety
// ---------------------------------------------------------------------------

bool _isAlertNote(String? notes) {
  if (notes == null || notes.isEmpty) return false;
  final n = notes.toLowerCase();
  return n.contains('allerg') ||
      n.contains('alerji') ||
      n.contains('vip') ||
      n.contains('nut') ||
      n.contains('gluten') ||
      n.contains('lactose') ||
      n.contains('laktoz') ||
      n.contains('kosher') ||
      n.contains('halal') ||
      n.contains('vegan');
}

String? _ticketAlertText(KitchenTicketEntity ticket) {
  for (final item in ticket.items) {
    if (_isAlertNote(item.notes)) return item.notes;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Kitchen Display Screen
// ---------------------------------------------------------------------------

class KitchenDisplayScreen extends ConsumerStatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  ConsumerState<KitchenDisplayScreen> createState() =>
      _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends ConsumerState<KitchenDisplayScreen> {
  late final Timer _refreshTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Track previous ticket IDs for new-ticket audible alert detection.
  Set<String> _previousTicketIds = {};

  @override
  void initState() {
    super.initState();
    // 1-second tick forces timer widgets to repaint without DB round-trips.
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Release audio player resources when playback completes.
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Bump
  // -------------------------------------------------------------------------

  Future<void> _bumpTicket(String kitchenTicketId) async {
    HapticFeedback.lightImpact();
    await ref.read(kitchenRepositoryProvider).completeTicket(kitchenTicketId);
    // Stream auto-removes the ticket — no setState needed.
  }

  /// Recall a ticket that was bumped by mistake — reverts to preparing so
  /// it reappears on the board. Wired to long-press for safety (discoverable
  /// but not accidental-tap-prone).
  Future<void> _recallTicket(String kitchenTicketId) async {
    HapticFeedback.mediumImpact();
    await ref.read(kitchenRepositoryProvider).recallTicket(kitchenTicketId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ticket recalled'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // New-ticket detection (for audible alert hook)
  // -------------------------------------------------------------------------

  void _detectNewTickets(List<KitchenTicketEntity> tickets) {
    final currentIds = tickets.map((t) => t.id).toSet();
    final newIds = currentIds.difference(_previousTicketIds);
    if (newIds.isNotEmpty && _previousTicketIds.isNotEmpty) {
      // New ticket arrived after initial load — play alert.
      _playNewTicketAlert();
    }
    _previousTicketIds = currentIds;
  }

  Future<void> _playNewTicketAlert() async {
    try {
      // Three short beeps: play the system notification tone three times with
      // a short gap between each burst.
      for (int i = 0; i < 3; i++) {
        await _audioPlayer.play(AssetSource('audio/kds_new_ticket.wav'));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } catch (_) {
      // Audio unavailable on this device — fail silently.
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(activeKitchenTicketsProvider);
    final completedAsync = ref.watch(completedTodayProvider);

    return ticketsAsync.when(
      data: (tickets) {
        _detectNewTickets(tickets);
        final completed = completedAsync.valueOrNull ?? 0;
        return _buildScaffold(tickets, completed);
      },
      loading: () => _buildScaffold(const [], 0, loading: true),
      error: (e, _) => _buildScaffold(const [], 0, error: e.toString()),
    );
  }

  Widget _buildScaffold(
    List<KitchenTicketEntity> tickets,
    int completed, {
    bool loading = false,
    String? error,
  }) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(tickets, completed),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                          ? _buildError(error)
                          : _buildTicketGrid(tickets),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sidebar
  // -------------------------------------------------------------------------

  Widget _buildSidebar() {
    return Container(
      width: 240,
      color: const Color(0xFF1A1D27),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFAFC6FF), Color(0xFF528DFF)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.restaurant,
                    size: 20,
                    color: Color(0xFF001944),
                  ),
                ),
                const SizedBox(width: 12),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFAFC6FF), Color(0xFF528DFF)],
                  ).createShader(bounds),
                  child: const Text(
                    'GastroCore',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildNavItem(Icons.shopping_cart, 'Order', false),
          _buildNavItem(Icons.receipt_long, 'Records', false),
          _buildNavItem(Icons.grid_view, 'Tables', false),
          _buildNavItem(Icons.restaurant_menu, 'Menu', false),
          _buildNavItem(Icons.terminal, 'KDS', true),
          const Spacer(),
          Container(
            height: 1,
            color: const Color(0xFF424753).withValues(alpha: 0.1),
          ),
          _buildNavItem(Icons.help, 'Support', false),
          GestureDetector(
            onTap: () => context.go('/order-center'),
            child: _buildNavItemWidget(Icons.logout, 'Logout', false),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (label == 'Order') context.go('/order-center');
      },
      child: _buildNavItemWidget(icon, label, isActive),
    );
  }

  Widget _buildNavItemWidget(IconData icon, String label, bool isActive) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF222633) : Colors.transparent,
        border: isActive
            ? const Border(
                left: BorderSide(color: Color(0xFF528DFF), width: 4))
            : null,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color:
                isActive ? AppColors.textPrimary : AppColors.textSecondary,
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color:
                  isActive ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top Bar
  // -------------------------------------------------------------------------

  Widget _buildTopBar(List<KitchenTicketEntity> tickets, int completed) {
    final pending =
        tickets.where((t) => t.status == KitchenTicketStatus.pending).length;
    final preparing =
        tickets.where((t) => t.status == KitchenTicketStatus.preparing).length;

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      color: const Color(0xFF1A1D27),
      child: Row(
        children: [
          const Text(
            'Kitchen Display',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 32),
          _buildStatColumn('PENDING', '$pending', AppColors.textPrimary),
          _buildDivider(),
          _buildStatColumn(
            'PREPARING',
            preparing.toString().padLeft(2, '0'),
            const Color(0xFF528DFF),
          ),
          _buildDivider(),
          _buildStatColumn(
            'READY',
            '$completed',
            const Color(0xFF4ADE80),
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1F26),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF22C55E),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'STATION 01 ACTIVE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1D1F26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.notifications,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1D1F26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.settings,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
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
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 32,
      color: const Color(0xFF424753).withValues(alpha: 0.2),
    );
  }

  // -------------------------------------------------------------------------
  // Ticket Grid
  // -------------------------------------------------------------------------

  Widget _buildTicketGrid(List<KitchenTicketEntity> tickets) {
    if (tickets.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Color(0xFF4ADE80),
            ),
            SizedBox(height: 16),
            Text(
              'All tickets completed!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = (constraints.maxWidth / 320).floor().clamp(1, 4);
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 24,
              crossAxisSpacing: 24,
              childAspectRatio: 0.72,
            ),
            itemCount: tickets.length,
            itemBuilder: (context, i) => _buildTicketCard(tickets[i]),
          );
        },
      ),
    );
  }

  Widget _buildTicketCard(KitchenTicketEntity ticket) {
    final urgency = _getUrgency(ticket);
    final urgColor = _urgencyColor(urgency);

    return GestureDetector(
      onLongPress: () => _recallTicket(ticket.id),
      child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1D1F26),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Urgency border
          Container(height: 6, color: urgColor),
          // Allergy / VIP banner — fine-dining kitchen safety
          if (_ticketAlertText(ticket) != null)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFEF4444),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _ticketAlertText(ticket)!.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
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
            ),
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            color: const Color(0xFF282A30).withValues(alpha: 0.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.tableName ?? '#${ticket.orderNumber}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -2.0,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (ticket.waiterName != null)
                        Text(
                          'Server: ${ticket.waiterName}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 1.0,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatElapsed(ticket),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: urgColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _urgencyLabel(urgency),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Items list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              itemCount: ticket.items.length,
              itemBuilder: (context, i) {
                final item = ticket.items[i];
                final mods = item.modifiersText
                        ?.split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList() ??
                    const [];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2F3D),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 1),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.3,
                              ),
                            ),
                            ...mods.map((mod) => Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '\u2022 $mod',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFC3C6D7),
                                    ),
                                  ),
                                )),
                            if (item.notes != null && item.notes!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: _isAlertNote(item.notes)
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '\u26A0 ${item.notes}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        '\u26A0 ${item.notes}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFFB923C),
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
              },
            ),
          ),
          // READY bump button
          Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: () => _bumpTicket(ticket.id),
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 22,
                      color: Color(0xFF001944),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'READY',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF001944),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Error state
  // -------------------------------------------------------------------------

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(
            'KDS Error: $message',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
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
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      color: const Color(0xFF1A1D27),
      child: Row(
        children: [
          _buildFooterStat(
              const Color(0xFF22C55E), 'Tap READY = bump'),
          const SizedBox(width: 32),
          _buildFooterStat(
              const Color(0xFF3B82F6), 'Long-press card = recall'),
          const Spacer(),
          const Text(
            'GASTROCORE ENGINE V4.2.0',
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

  Widget _buildFooterStat(Color dotColor, String text) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 3.0,
          ),
        ),
      ],
    );
  }
}
