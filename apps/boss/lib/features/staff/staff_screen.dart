/// Staff live status — clocked-in list with table count + avg ticket time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_ui/gastrocore_ui.dart';

import 'staff_models.dart';
import 'staff_providers.dart';

class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(activeStaffProvider);
    return staff.when(
      data: (list) => _StaffBody(members: list),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => GastrocoreErrorWidget(
        message: 'Personel listesi alınamadı: $e',
        onRetry: () => ref.invalidate(activeStaffProvider),
      ),
    );
  }
}

class _StaffBody extends StatelessWidget {
  final List<ActiveStaffMember> members;
  const _StaffBody({required this.members});

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'Vardiyada kimse yok',
        subtitle: 'Personel giriş yaptığında burada görünür.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: members.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i == 0) {
          return _SummaryHeader(members: members);
        }
        return _StaffTile(member: members[i - 1]);
      },
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final List<ActiveStaffMember> members;
  const _SummaryHeader({required this.members});

  @override
  Widget build(BuildContext context) {
    final tables = members.fold<int>(0, (s, m) => s + m.openTableCount);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _Stat(label: 'Vardiyada', value: '${members.length}'),
          const SizedBox(width: 16),
          _Stat(label: 'Açık masa', value: '$tables'),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _StaffTile extends StatelessWidget {
  final ActiveStaffMember member;
  const _StaffTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.accentDim,
            child: Text(
              _initials(member.name),
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${member.roleLabel} · ${_fmtDuration(member.shiftDuration)} vardiyada',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${member.openTableCount} masa',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '⌀ ${_fmtMinutes(member.averageTicketTime)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}d';
    return '${h}s ${m.toString().padLeft(2, '0')}d';
  }

  static String _fmtMinutes(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
