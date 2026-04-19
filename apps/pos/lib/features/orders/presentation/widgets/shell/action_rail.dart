/// Right-column action rail — pilot-grade commands on the active ticket.
///
/// Lightspeed/SambaPOS-inspired vertical stack of icon+label buttons. Each
/// is a ≥48dp touch target so waiters do not mis-fire during service.
/// Pilot surface: İPTAL (void), YAZDIR (print bill), İKRAM (on-the-house),
/// BÖL (split), KİLİT (lock station), ÖDE (payment).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gastrocore_pos/core/router/app_router.dart';
import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/permission.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/orders/domain/entities/ticket_entity.dart';
import 'package:gastrocore_pos/features/orders/presentation/providers/order_provider.dart';

class ActionRail extends ConsumerWidget {
  const ActionRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(currentTicketProvider);
    final hasTicket = ticket != null && ticket.items.isNotEmpty;
    final payEnabled = hasTicket &&
        ticket.status != TicketStatus.completed &&
        ticket.status != TicketStatus.voided &&
        ticket.status != TicketStatus.cancelled;

    // Role gate: İPTAL (storno) requires Şef+ (manager or admin).
    final canStorno = ref.watch(canProvider(Permission.storno));

    return Container(
      width: AppTokens.actionRailWidth,
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space12),
      child: Column(
        children: [
          _RailButton(
            icon: Icons.warning_amber_rounded,
            label: 'İPTAL',
            enabled: hasTicket && canStorno,
            gatedReason: canStorno ? null : kPermissionRequiredTooltip,
            tone: _Tone.danger,
            onTap: () => _onCancel(context, ref, ticket!),
          ),
          _RailButton(
            icon: Icons.print_rounded,
            label: 'YAZDIR',
            enabled: hasTicket,
            onTap: () => _onPrintBill(context, ticket!),
          ),
          _RailButton(
            icon: Icons.card_giftcard_rounded,
            label: 'İKRAM',
            enabled: hasTicket,
            onTap: () => _onIkram(context, ref, ticket!),
          ),
          _RailButton(
            icon: Icons.call_split_rounded,
            label: 'BÖL',
            enabled: hasTicket,
            onTap: () async {
              final saved = await ref
                  .read(currentTicketProvider.notifier)
                  .saveCurrentTicket();
              if (saved == null || !context.mounted) return;
              context.push(AppRoutes.splitBillFor(saved.id));
            },
          ),
          _RailButton(
            icon: Icons.lock_rounded,
            label: 'KİLİT',
            onTap: () => _onLock(context),
          ),
          const Spacer(),
          _RailButton(
            icon: Icons.payments_rounded,
            label: 'ÖDE',
            enabled: payEnabled,
            tone: _Tone.primary,
            onTap: () async {
              if (ticket == null) return;
              final saved = await ref
                  .read(currentTicketProvider.notifier)
                  .saveCurrentTicket();
              if (saved == null || !context.mounted) return;
              context.push(AppRoutes.paymentFor(saved.id));
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // İPTAL — confirm then void the whole ticket. Single-line removal is
  // handled from the order panel's line menu.
  // -------------------------------------------------------------------------

  Future<void> _onCancel(
    BuildContext context,
    WidgetRef ref,
    TicketEntity ticket,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StornoReasonDialog(itemCount: ticket.items.length),
    );
    if (reason == null || reason.trim().isEmpty) return;

    final userId = ref.read(currentUserProvider)?.id ?? 'unknown';
    await ref
        .read(currentTicketProvider.notifier)
        .voidTicket(reason: reason.trim(), userId: userId);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sipariş iptal edildi.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // YAZDIR — stub interim-bill preview. Real ESC/POS wiring tracked
  // separately; pilot-grade confirmation ack lets staff continue the flow.
  // -------------------------------------------------------------------------

  Future<void> _onPrintBill(BuildContext context, TicketEntity ticket) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adisyon / Fiş'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ticket.tableId != null
                    ? 'Masa #${ticket.tableId}'
                    : 'Sipariş ${ticket.orderNumber}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final item in ticket.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text('${item.quantity.toStringAsFixed(0)}× '),
                      Expanded(child: Text(item.productName)),
                      Text('CHF ${(item.subtotal / 100).toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Toplam',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'CHF ${(ticket.total / 100).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Kapat'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.print_rounded, size: 18),
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Adisyon yazıcıya gönderildi.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            label: const Text('Yazdır'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // İKRAM — let the waiter pick a line and flip it to on-the-house.
  // -------------------------------------------------------------------------

  Future<void> _onIkram(
    BuildContext context,
    WidgetRef ref,
    TicketEntity ticket,
  ) async {
    final itemId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'İkram edilecek kalem',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: ticket.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = ticket.items[i];
                    final isAlready = item.subtotal == 0 ||
                        (item.notes ?? '').startsWith('[İKRAM]');
                    return ListTile(
                      enabled: !isAlready,
                      leading: Text(
                        '${item.quantity.toStringAsFixed(0)}×',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      title: Text(item.productName),
                      subtitle: isAlready ? const Text('(zaten İKRAM)') : null,
                      trailing: Text(
                        'CHF ${(item.subtotal / 100).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onTap: () => Navigator.of(ctx).pop(item.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (itemId == null) return;
    ref.read(currentTicketProvider.notifier).markOnTheHouse(itemId);
    if (!context.mounted) return;
    final item = ticket.items.firstWhere(
      (it) => it.id == itemId,
      orElse: () => ticket.items.first,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.productName} ikram edildi.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // KİLİT — send the station back to the PIN screen without discarding
  // in-memory state. The login screen handles re-auth.
  // -------------------------------------------------------------------------

  void _onLock(BuildContext context) {
    context.go(AppRoutes.login);
  }
}

enum _Tone { normal, primary, danger }

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.tone = _Tone.normal,
    this.gatedReason,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final _Tone tone;

  /// When non-null, shown as a tooltip explaining why the button is disabled
  /// (typically "Yetki gerekli" for role-gated controls).
  final String? gatedReason;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled
        ? AppColors.textDim
        : switch (tone) {
            _Tone.primary => Colors.white,
            _Tone.danger => AppColors.red,
            _Tone.normal => AppColors.textPrimary,
          };
    final bg = tone == _Tone.primary
        ? AppColors.primaryContainer
        : Colors.transparent;

    final button = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 4,
      ),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (gatedReason != null) {
      return Tooltip(message: gatedReason!, child: button);
    }
    return button;
  }
}

// ---------------------------------------------------------------------------
// Storno reason dialog
// ---------------------------------------------------------------------------

/// Required-reason prompt shown before an İPTAL goes through.
///
/// Auditors need a meaningful reason attached to every cancellation. The
/// waiter picks one of the preset causes or selects "Diğer" and types a
/// free-text note. OK stays disabled until a non-empty reason is available.
class _StornoReasonDialog extends StatefulWidget {
  final int itemCount;

  const _StornoReasonDialog({required this.itemCount});

  @override
  State<_StornoReasonDialog> createState() => _StornoReasonDialogState();
}

class _StornoReasonDialogState extends State<_StornoReasonDialog> {
  static const List<String> _presets = [
    'Müşteri iptal etti',
    'Yanlış sipariş',
    'Mutfak hatası',
    'Diğer',
  ];

  String? _selectedPreset;
  final TextEditingController _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  /// Effective reason: preset label, or the custom text when "Diğer".
  String get _effectiveReason {
    if (_selectedPreset == null) return '';
    if (_selectedPreset == 'Diğer') return _customController.text.trim();
    return _selectedPreset!;
  }

  bool get _canSubmit => _effectiveReason.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isOther = _selectedPreset == 'Diğer';
    return AlertDialog(
      title: const Text('Siparişi iptal et?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.itemCount} kalem silinecek. Bu işlem geri alınamaz.',
            ),
            const SizedBox(height: 12),
            const Text(
              'İptal nedeni (zorunlu)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedPreset,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              hint: const Text('Neden seçin'),
              items: _presets
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedPreset = v),
            ),
            if (isOther) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customController,
                autofocus: true,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          onPressed: _canSubmit
              ? () => Navigator.of(context).pop(_effectiveReason)
              : null,
          child: const Text('İptal et'),
        ),
      ],
    );
  }
}
