import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/utils/money.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/loyalty_transaction_entity.dart';
import 'package:gastrocore_pos/features/customers/presentation/providers/customer_provider.dart';
import 'package:gastrocore_pos/features/customers/presentation/widgets/loyalty_badge.dart';


class LoyaltyScreen extends ConsumerWidget {
  final String customerId;

  const LoyaltyScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerByIdProvider(customerId));
    final txAsync = ref.watch(loyaltyTransactionsProvider(customerId));

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: customerAsync.when(
        data: (customer) {
          if (customer == null) return const SizedBox.shrink();
          return Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPointsSummary(context, ref, customer),
                      const SizedBox(height: 20),
                      _buildTierProgress(customer),
                      const SizedBox(height: 20),
                      _buildActions(context, ref, customer),
                      const SizedBox(height: 20),
                      _buildRules(),
                      const SizedBox(height: 20),
                      _buildHistory(txAsync),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('$e',
              style: const TextStyle(color: AppColors.red)),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 64,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Treuepunkte',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsSummary(
      BuildContext context, WidgetRef ref, CustomerEntity customer) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.yellow.withValues(alpha: 0.2),
            AppColors.orange.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.yellow.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verfügbare Punkte',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${customer.loyaltyPoints}',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: AppColors.yellow,
                    ),
                  ),
                  Text(
                    '= ${Money(customer.redeemableDiscountCents).format('CHF')} Rabatt',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
              LoyaltyBadge(tier: customer.tier, large: true),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _PointStat(
                label: 'Gesammelt',
                value: '${customer.totalOrders * 10 + customer.loyaltyPoints}',
                icon: Icons.trending_up_rounded,
                color: AppColors.green,
              ),
              _PointStat(
                label: 'Eingelöst',
                value: '-',
                icon: Icons.redeem_rounded,
                color: AppColors.orange,
              ),
              _PointStat(
                label: 'Gesamt Umsatz',
                value: Money(customer.totalSpent).format('CHF'),
                icon: Icons.receipt_rounded,
                color: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTierProgress(CustomerEntity customer) {
    final spentChf = customer.totalSpent ~/ 100;
    double progress;
    String nextTier;
    int remaining;

    switch (customer.tier) {
      case CustomerTier.bronze:
        progress = (spentChf / 200).clamp(0.0, 1.0);
        nextTier = 'Silber';
        remaining = (200 - spentChf).clamp(0, 200);
      case CustomerTier.silver:
        progress = ((spentChf - 200) / 300).clamp(0.0, 1.0);
        nextTier = 'Gold';
        remaining = (500 - spentChf).clamp(0, 300);
      case CustomerTier.gold:
        progress = 1.0;
        nextTier = 'Gold';
        remaining = 0;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Treue-Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              LoyaltyBadge(tier: customer.tier),
              const Spacer(),
              if (customer.tier != CustomerTier.gold)
                Text(
                  'Noch CHF $remaining bis $nextTier',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                )
              else
                const Text(
                  'Höchster Status erreicht!',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.yellow),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.bgInput,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.yellow),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Bronze',
                  style: TextStyle(
                      fontSize: 10, color: Color(0xFFCD7F32))),
              const Text('Silber',
                  style: TextStyle(
                      fontSize: 10, color: Color(0xFFC0C0C0))),
              const Text('Gold',
                  style:
                      TextStyle(fontSize: 10, color: AppColors.yellow)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
      BuildContext context, WidgetRef ref, CustomerEntity customer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Aktionen',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'Punkte einlösen',
                sublabel: '100 Pts = CHF 1.00',
                icon: Icons.redeem_rounded,
                color: AppColors.orange,
                enabled: customer.loyaltyPoints >= 100,
                onTap: () => _redeemDialog(context, ref, customer),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton(
                label: 'Punkte anpassen',
                sublabel: 'Manager-Aktion',
                icon: Icons.tune_rounded,
                color: AppColors.primary,
                onTap: () => _adjustDialog(context, ref, customer),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRules() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Programm-Regeln',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RuleRow(
            icon: Icons.add_circle_rounded,
            color: AppColors.green,
            text: '1 CHF ausgeben = 1 Punkt sammeln',
          ),
          const SizedBox(height: 8),
          _RuleRow(
            icon: Icons.remove_circle_rounded,
            color: AppColors.orange,
            text: '100 Punkte = CHF 1.00 Rabatt',
          ),
          const SizedBox(height: 8),
          _RuleRow(
            icon: Icons.star_rounded,
            color: const Color(0xFFC0C0C0),
            text: 'Silber: ab CHF 200 Umsatz',
          ),
          const SizedBox(height: 8),
          _RuleRow(
            icon: Icons.star_rounded,
            color: AppColors.yellow,
            text: 'Gold: ab CHF 500 Umsatz',
          ),
        ],
      ),
    );
  }

  Widget _buildHistory(
      AsyncValue<List<LoyaltyTransactionEntity>> txAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transaktionshistorie',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        txAsync.when(
          data: (transactions) {
            if (transactions.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Keine Transaktionen vorhanden',
                      style: TextStyle(color: AppColors.textDim)),
                ),
              );
            }
            return Column(
              children: transactions
                  .map((tx) => _HistoryRow(tx: tx))
                  .toList(),
            );
          },
          loading: () => const SizedBox(
            height: 80,
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Future<void> _redeemDialog(
      BuildContext context, WidgetRef ref, CustomerEntity customer) async {
    final maxRedeemable = customer.loyaltyPoints;
    final ctrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: const Text('Punkte einlösen',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verfügbar: $maxRedeemable Punkte',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Anzahl Punkte',
                hintStyle: const TextStyle(color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                suffixText: 'Pts',
                suffixStyle: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Einlösen'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final points = int.tryParse(ctrl.text) ?? 0;
      if (points > 0 && points <= maxRedeemable) {
        await ref.read(customerNotifierProvider.notifier).redeemPoints(
              customer.id,
              points: points,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$points Punkte eingelöst — ${Money(points).format('CHF')} Rabatt',
              ),
              backgroundColor: AppColors.green,
            ),
          );
        }
      }
    }
  }

  Future<void> _adjustDialog(
      BuildContext context, WidgetRef ref, CustomerEntity customer) async {
    final ctrl = TextEditingController();
    final descCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: const Text('Punkte anpassen',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: '+50 oder -20',
                hintStyle: const TextStyle(color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Grund (z.B. Kulanz, Fehler)',
                hintStyle: const TextStyle(color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surfaceDim,
            ),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final delta = int.tryParse(ctrl.text) ?? 0;
      if (delta != 0) {
        await ref.read(customerNotifierProvider.notifier).adjustPoints(
              customer.id,
              delta: delta,
              description: descCtrl.text.trim().isEmpty
                  ? 'Manuelle Anpassung'
                  : descCtrl.text.trim(),
            );
      }
    }
  }
}

class _PointStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _PointStat(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: color.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color)),
              Text(sublabel,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _RuleRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final LoyaltyTransactionEntity tx;

  const _HistoryRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isEarn = tx.isEarning;
    final color = isEarn ? AppColors.green : AppColors.orange;
    final sign = isEarn ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _typeIcon(tx.type),
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description ?? _typeName(tx.type),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                Text(
                  DateFormat('dd.MM.yyyy • HH:mm').format(tx.createdAt),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          Text(
            '$sign${tx.points} Pts',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(LoyaltyTransactionType type) {
    return switch (type) {
      LoyaltyTransactionType.earn => Icons.add_circle_rounded,
      LoyaltyTransactionType.redeem => Icons.redeem_rounded,
      LoyaltyTransactionType.adjust => Icons.tune_rounded,
      LoyaltyTransactionType.expire => Icons.timer_off_rounded,
    };
  }

  String _typeName(LoyaltyTransactionType type) {
    return switch (type) {
      LoyaltyTransactionType.earn => 'Punkte gesammelt',
      LoyaltyTransactionType.redeem => 'Punkte eingelöst',
      LoyaltyTransactionType.adjust => 'Manuelle Anpassung',
      LoyaltyTransactionType.expire => 'Punkte abgelaufen',
    };
  }
}
