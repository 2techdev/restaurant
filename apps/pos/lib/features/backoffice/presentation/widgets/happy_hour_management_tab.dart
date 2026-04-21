/// Happy Hour Management tab for the Back Office screen.
///
/// Lists every [HappyHourRule] persisted through [SettingsRepository], and
/// offers add / edit / delete / toggle-active actions. Rules are stored in
/// a single SharedPreferences blob so the POS grid's `addItem` hot path
/// can read them synchronously without hitting the database.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/pricing/domain/happy_hour_rule.dart';
import 'package:gastrocore_pos/features/pricing/providers/happy_hour_provider.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';

// ---------------------------------------------------------------------------
// Weekday helpers
// ---------------------------------------------------------------------------

const _weekdayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _weekdayLong = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];

// ---------------------------------------------------------------------------
// HappyHourManagementTab
// ---------------------------------------------------------------------------

class HappyHourManagementTab extends ConsumerWidget {
  const HappyHourManagementTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(happyHourRulesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'Happy Hour Kurallari',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Belirli gun ve saatlerde otomatik indirim uygulayan kurallar. '
                'Kurallar POS ekraninda siparis eklerken otomatik olarak '
                'degerlendirilir.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textDim,
                  height: 1.5,
                ),
              ),
            ),

            Expanded(
              child: rules.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: rules.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _RuleCard(rule: rules[i]),
                    ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: PosGradientButton(
                label: '+ Yeni Kural Ekle',
                onPressed: () => _openEditor(context, ref),
              ),
            ),
          ],
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded,
              size: 42, color: AppColors.textDim),
          SizedBox(height: 12),
          Text(
            'Henuz kural tanimlanmamis',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '"+ Yeni Kural Ekle" butonuna basarak baslayin.',
            style: TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rule card
// ---------------------------------------------------------------------------

class _RuleCard extends ConsumerWidget {
  const _RuleCard({required this.rule});

  final HappyHourRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(happyHourRulesProvider.notifier);
    final daysLabel = _formatDays(rule.daysOfWeek);
    final timeLabel =
        '${_formatTime(rule.startTime)} - ${_formatTime(rule.endTime)}';
    final target = rule.productNameContains ?? rule.categoryId ?? 'Tum urunler';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: rule.active
              ? AppColors.green.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Discount pill
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.orangeDim,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '-${rule.discountPercent}%',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.orange,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rule.name.isEmpty ? '(isimsiz kural)' : rule.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!rule.active)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PASIF',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDim,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$target · $timeLabel · $daysLabel',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                    height: 1.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Actions
          IconButton(
            onPressed: () => notifier.toggleActive(rule.id),
            tooltip: rule.active ? 'Pasiflestir' : 'Aktiflestir',
            icon: Icon(
              rule.active
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_outlined,
              color: rule.active ? AppColors.green : AppColors.textDim,
              size: 28,
            ),
          ),
          IconButton(
            onPressed: () => _openEditor(context, ref, existing: rule),
            tooltip: 'Duzenle',
            icon: const Icon(
              Icons.edit_rounded,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ),
          IconButton(
            onPressed: () => _confirmDelete(context, ref, rule),
            tooltip: 'Sil',
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.red,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  HappyHourRule rule,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: const Text('Kurali Sil'),
      content: Text('"${rule.name}" kurali kalici olarak silinecek.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Vazgec'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Sil'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(happyHourRulesProvider.notifier).remove(rule.id);
  }
}

// ---------------------------------------------------------------------------
// Editor dialog
// ---------------------------------------------------------------------------

Future<void> _openEditor(
  BuildContext context,
  WidgetRef ref, {
  HappyHourRule? existing,
}) async {
  final saved = await showDialog<HappyHourRule>(
    context: context,
    builder: (ctx) => _HappyHourEditorDialog(existing: existing),
  );
  if (saved != null) {
    await ref.read(happyHourRulesProvider.notifier).upsert(saved);
  }
}

class _HappyHourEditorDialog extends StatefulWidget {
  const _HappyHourEditorDialog({this.existing});

  final HappyHourRule? existing;

  @override
  State<_HappyHourEditorDialog> createState() => _HappyHourEditorDialogState();
}

class _HappyHourEditorDialogState extends State<_HappyHourEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _productMatch;
  late final TextEditingController _category;
  late int _discount;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late Set<int> _days; // ISO weekdays 1..7
  late bool _active;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _productMatch =
        TextEditingController(text: e?.productNameContains ?? '');
    _category = TextEditingController(text: e?.categoryId ?? '');
    _discount = e?.discountPercent ?? 10;
    _start = e?.startTime ?? const TimeOfDay(hour: 17, minute: 0);
    _end = e?.endTime ?? const TimeOfDay(hour: 19, minute: 0);
    _days = e?.daysOfWeek.toSet() ?? {1, 2, 3, 4, 5};
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _productMatch.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kural adi bos olamaz.')),
      );
      return;
    }
    if (_discount < 1 || _discount > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indirim orani 1-100 arasinda olmali.')),
      );
      return;
    }
    final rule = HappyHourRule(
      id: widget.existing?.id ?? IdGenerator.generateId(),
      name: name,
      categoryId:
          _category.text.trim().isEmpty ? null : _category.text.trim(),
      productNameContains: _productMatch.text.trim().isEmpty
          ? null
          : _productMatch.text.trim(),
      discountPercent: _discount,
      startTime: _start,
      endTime: _end,
      daysOfWeek: (_days.toList()..sort()),
      active: _active,
    );
    Navigator.of(context).pop(rule);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null
                    ? 'Yeni Happy Hour Kurali'
                    : 'Kurali Duzenle',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),

              // Name
              PosTextField(
                controller: _name,
                label: 'Kural adi',
                hint: 'Ornek: Happy Hour Bira',
              ),
              const SizedBox(height: 12),

              // Product name contains
              PosTextField(
                controller: _productMatch,
                label: 'Urun adi iceriyor (opsiyonel)',
                hint: 'Ornek: bira',
              ),
              const SizedBox(height: 12),

              // Category
              PosTextField(
                controller: _category,
                label: 'Kategori ID (opsiyonel)',
                hint: 'Ornek: beverages',
              ),
              const SizedBox(height: 16),

              // Discount slider
              Text(
                'Indirim orani: %$_discount',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              Slider(
                min: 1,
                max: 100,
                divisions: 99,
                value: _discount.toDouble(),
                activeColor: AppColors.orange,
                onChanged: (v) => setState(() => _discount = v.round()),
              ),

              // Time range
              Row(
                children: [
                  Expanded(
                    child: _TimeBox(
                      label: 'Baslangic',
                      value: _formatTime(_start),
                      onTap: () => _pickTime(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeBox(
                      label: 'Bitis',
                      value: _formatTime(_end),
                      onTap: () => _pickTime(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Weekday picker
              const Text(
                'Gunler',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: List.generate(7, (i) {
                  final iso = i + 1; // Mon=1 .. Sun=7
                  final selected = _days.contains(iso);
                  return FilterChip(
                    label: Text(_weekdayShort[i]),
                    tooltip: _weekdayLong[i],
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _days.add(iso);
                        } else {
                          _days.remove(iso);
                        }
                      });
                    },
                    selectedColor: AppColors.primary.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    backgroundColor: AppColors.surfaceContainer,
                    shape: const StadiumBorder(),
                  );
                }),
              ),
              const SizedBox(height: 16),

              // Active toggle
              SwitchListTile.adaptive(
                title: const Text(
                  'Kural aktif',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: const Text(
                  'Pasif kurallar POS ekraninda indirim uygulamaz.',
                  style: TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                activeThumbColor: AppColors.green,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: const Text('Vazgec'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PosGradientButton(
                      label: 'Kaydet',
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDim,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.access_time_rounded,
                    size: 16,
                    color: AppColors.textDim,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _formatDays(List<int> days) {
  if (days.isEmpty) return 'Her gun';
  if (days.length == 7) return 'Her gun';
  // Compact Mon-Fri style labelling when the set is a contiguous range.
  final sorted = [...days]..sort();
  if (sorted.length >= 2 &&
      sorted.first == sorted.first &&
      sorted.last - sorted.first == sorted.length - 1) {
    return '${_weekdayShort[sorted.first - 1]}-${_weekdayShort[sorted.last - 1]}';
  }
  return sorted.map((d) => _weekdayShort[d - 1]).join(', ');
}
