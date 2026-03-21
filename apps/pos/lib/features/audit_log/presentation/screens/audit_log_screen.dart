/// Audit Log screen — admin / manager only.
///
/// Shows a filterable, paginated list of all auditable events.
/// Tapping an entry opens a detail sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_action.dart';
import 'package:gastrocore_pos/features/audit_log/domain/entities/audit_log_entry_entity.dart';
import 'package:gastrocore_pos/features/audit_log/presentation/providers/audit_log_provider.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  final _dateFormat = DateFormat('dd.MM.yyyy');
  final _tsFormat = DateFormat('dd.MM.yyyy HH:mm:ss');

  @override
  void initState() {
    super.initState();
    // Listen to export state changes to show feedback.
    ref.listenManual(auditLogExportProvider, (_, next) {
      if (!mounted) return;
      switch (next) {
        case AuditExportSuccess(:final filePath):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.green,
              duration: const Duration(seconds: 5),
              content: Text(
                'CSV exported: $filePath',
                style: const TextStyle(
                    color: Color(0xFF003A11), fontWeight: FontWeight.w600),
              ),
            ),
          );
          ref.read(auditLogExportProvider.notifier).reset();
        case AuditExportError(:final message):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.red,
              content: Text(message,
                  style: const TextStyle(color: Colors.white)),
            ),
          );
          ref.read(auditLogExportProvider.notifier).reset();
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(auditLogFilterProvider);
    final entriesAsync = ref.watch(auditLogEntriesProvider);
    final exportState = ref.watch(auditLogExportProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _TopBar(
            onBack: () => Navigator.of(context).maybePop(),
            onExport: exportState is AuditExportBusy
                ? null
                : () => ref.read(auditLogExportProvider.notifier).exportCsv(),
            isExporting: exportState is AuditExportBusy,
          ),
          _FilterBar(filter: filter, dateFormat: _dateFormat),
          Expanded(
            child: entriesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Error loading audit log: $e',
                  style: const TextStyle(color: AppColors.red),
                ),
              ),
              data: (entries) => entries.isEmpty
                  ? const _EmptyState()
                  : _EntryList(entries: entries, tsFormat: _tsFormat),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.onExport,
    required this.isExporting,
  });
  final VoidCallback onBack;
  final VoidCallback? onExport;
  final bool isExporting;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: AppColors.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textSecondary),
            onPressed: onBack,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.history_rounded, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          const Text(
            'Audit Log',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          // CSV export button
          GestureDetector(
            onTap: onExport,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: onExport == null ? 0.5 : 1.0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.download_rounded,
                              size: 14, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text(
                            'Export CSV',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------

class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar({required this.filter, required this.dateFormat});
  final AuditLogFilter filter;
  final DateFormat dateFormat;

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  final _userController = TextEditingController();

  @override
  void dispose() {
    _userController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(auditLogFilterProvider.notifier);
    final filter = widget.filter;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // From date
          _DateChip(
            label: filter.from != null
                ? 'From: ${widget.dateFormat.format(filter.from!)}'
                : 'From date',
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: filter.from ?? DateTime.now().subtract(const Duration(days: 7)),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: _darkDatePickerTheme,
              );
              if (picked != null) notifier.setFrom(picked);
            },
            active: filter.from != null,
            onClear: filter.from != null ? () => notifier.setFrom(null) : null,
          ),
          // To date
          _DateChip(
            label: filter.to != null
                ? 'To: ${widget.dateFormat.format(filter.to!)}'
                : 'To date',
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: filter.to ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: _darkDatePickerTheme,
              );
              if (picked != null) {
                notifier.setTo(picked.add(const Duration(hours: 23, minutes: 59, seconds: 59)));
              }
            },
            active: filter.to != null,
            onClear: filter.to != null ? () => notifier.setTo(null) : null,
          ),
          // Action dropdown
          _ActionDropdown(
            value: filter.action,
            onChanged: notifier.setAction,
          ),
          // Reset
          if (filter.from != null || filter.to != null || filter.action != null || (filter.userId != null && filter.userId!.isNotEmpty))
            TextButton.icon(
              onPressed: () {
                notifier.reset();
                _userController.clear();
              },
              icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.orange),
              label: const Text('Clear filters', style: TextStyle(color: AppColors.orange, fontSize: 13)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            ),
        ],
      ),
    );
  }

  Widget _darkDatePickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          surface: AppColors.surfaceContainer,
        ),
      ),
      child: child!,
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.onTap,
    required this.active,
    this.onClear,
  });
  final String label;
  final VoidCallback onTap;
  final bool active;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.accentDim : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: active ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded, size: 14, color: AppColors.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionDropdown extends StatelessWidget {
  const _ActionDropdown({required this.value, required this.onChanged});
  final AuditAction? value;
  final ValueChanged<AuditAction?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: value != null ? AppColors.accentDim : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value != null ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AuditAction?>(
          value: value,
          hint: const Text('All actions', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          dropdownColor: AppColors.surfaceContainer,
          iconEnabledColor: value != null ? AppColors.primary : AppColors.textSecondary,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: [
            const DropdownMenuItem<AuditAction?>(
              value: null,
              child: Text('All actions', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ...AuditAction.values.map(
              (a) => DropdownMenuItem<AuditAction?>(
                value: a,
                child: Text(a.label),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry list
// ---------------------------------------------------------------------------

class _EntryList extends StatelessWidget {
  const _EntryList({required this.entries, required this.tsFormat});
  final List<AuditLogEntryEntity> entries;
  final DateFormat tsFormat;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (ctx, i) => _EntryTile(entry: entries[i], tsFormat: tsFormat),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.tsFormat});
  final AuditLogEntryEntity entry;
  final DateFormat tsFormat;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            _ActionBadge(action: entry.action),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.action.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.entityType} · ${entry.entityId.length > 12 ? entry.entityId.substring(0, 12) : entry.entityId}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  entry.userName.isEmpty ? entry.userId : entry.userName,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  tsFormat.format(entry.timestamp),
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textDim, size: 18),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => _DetailSheet(entry: entry, tsFormat: tsFormat),
    );
  }
}

class _ActionBadge extends StatelessWidget {
  const _ActionBadge({required this.action});
  final AuditAction action;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (action) {
      AuditAction.orderCancelled || AuditAction.orderVoided || AuditAction.paymentRefunded =>
        (AppColors.red, Icons.cancel_rounded),
      AuditAction.paymentReceived =>
        (AppColors.green, Icons.payments_rounded),
      AuditAction.discountApplied =>
        (AppColors.orange, Icons.discount_rounded),
      AuditAction.shiftOpened || AuditAction.shiftClosed =>
        (AppColors.purple, Icons.access_time_rounded),
      AuditAction.userLoggedIn || AuditAction.userLoggedOut =>
        (AppColors.primary, Icons.person_rounded),
      AuditAction.managerOverride =>
        (AppColors.yellow, Icons.admin_panel_settings_rounded),
      AuditAction.cashDrawerOpened =>
        (AppColors.orange, Icons.point_of_sale_rounded),
      _ => (AppColors.primary, Icons.edit_rounded),
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail bottom sheet
// ---------------------------------------------------------------------------

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.entry, required this.tsFormat});
  final AuditLogEntryEntity entry;
  final DateFormat tsFormat;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            entry.action.label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tsFormat.format(entry.timestamp),
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          _DetailRow('User', '${entry.userName} (${entry.userId})'),
          if (entry.managerId != null && entry.managerId!.isNotEmpty)
            _DetailRow(
              'Authorised By',
              '${entry.managerName ?? ''} (${entry.managerId})',
            ),
          _DetailRow('Entity', '${entry.entityType} / ${entry.entityId}'),
          _DetailRow('Device', entry.deviceId),
          if (entry.reason != null && entry.reason!.isNotEmpty)
            _DetailRow('Reason', entry.reason!),
          if (entry.ipAddress != null && entry.ipAddress!.isNotEmpty)
            _DetailRow('IP Address', entry.ipAddress!),
          if (entry.oldValueJson != null && entry.oldValueJson!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Before', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            _JsonBox(entry.oldValueJson!),
          ],
          if (entry.newValueJson != null && entry.newValueJson!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('After', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            _JsonBox(entry.newValueJson!),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _JsonBox extends StatelessWidget {
  const _JsonBox(this.json);
  final String json;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDim,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        json,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 48, color: AppColors.textDim),
          SizedBox(height: 12),
          Text(
            'No audit log entries found.',
            style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            'Adjust filters or wait for events to be recorded.',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}
