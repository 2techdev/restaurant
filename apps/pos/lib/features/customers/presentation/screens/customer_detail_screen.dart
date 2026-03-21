import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/utils/money.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/loyalty_transaction_entity.dart';
import 'package:gastrocore_pos/features/customers/presentation/providers/customer_provider.dart';
import 'package:gastrocore_pos/features/customers/presentation/screens/customer_form_screen.dart';
import 'package:gastrocore_pos/features/customers/presentation/screens/loyalty_screen.dart';
import 'package:gastrocore_pos/features/customers/presentation/widgets/loyalty_badge.dart';
import 'package:gastrocore_pos/shared/widgets/pos_loading.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerByIdProvider(customerId));
    final txAsync = ref.watch(loyaltyTransactionsProvider(customerId));

    return customerAsync.when(
      data: (customer) {
        if (customer == null) {
          return Scaffold(
            backgroundColor: AppColors.surfaceDim,
            body: const Center(
              child: Text('Kunde nicht gefunden',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          );
        }
        return _buildScaffold(context, ref, customer, txAsync);
      },
      loading: () => const Scaffold(
        backgroundColor: AppColors.surfaceDim,
        body: PosLoading(),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.surfaceDim,
        body: Center(
          child: Text('Fehler: $e',
              style: const TextStyle(color: AppColors.red)),
        ),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    WidgetRef ref,
    CustomerEntity customer,
    AsyncValue<List<LoyaltyTransactionEntity>> txAsync,
  ) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(context, ref, customer),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfile(customer),
                  const SizedBox(height: 20),
                  _buildStatsRow(customer),
                  const SizedBox(height: 20),
                  _buildLoyaltyCard(context, customer),
                  const SizedBox(height: 20),
                  _buildContactInfo(customer),
                  if (customer.notes != null &&
                      customer.notes!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildNotes(customer),
                  ],
                  const SizedBox(height: 20),
                  _buildTransactionHistory(txAsync),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
      BuildContext context, WidgetRef ref, CustomerEntity customer) {
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
          Expanded(
            child: Text(
              customer.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Edit button
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CustomerFormScreen(customer: customer),
              )),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_rounded,
                        size: 14, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text('Bearbeiten',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile(CustomerEntity customer) {
    return Row(
      children: [
        _buildAvatar(customer),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  LoyaltyBadge(tier: customer.tier),
                ],
              ),
              if (customer.hasBirthdayThisWeek) ...[
                const SizedBox(height: 4),
                Row(
                  children: const [
                    Icon(Icons.cake_rounded,
                        size: 14, color: AppColors.purple),
                    SizedBox(width: 4),
                    Text(
                      'Geburtstag diese Woche!',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.purple,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Kunde seit ${DateFormat('MMM yyyy').format(customer.createdAt)}',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(CustomerEntity customer) {
    final initials = customer.name
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    final tierColor = _tierColor(customer.tier);
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: tierColor.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: tierColor, width: 2),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: tierColor,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(CustomerEntity customer) {
    return Row(
      children: [
        _StatCard(
          label: 'Bestellungen',
          value: '${customer.totalOrders}',
          icon: Icons.receipt_long_rounded,
          color: AppColors.primary,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Umsatz',
          value: Money.format(customer.totalSpent),
          icon: Icons.payments_rounded,
          color: AppColors.green,
        ),
        const SizedBox(width: 12),
        _StatCard(
          label: 'Punkte',
          value: '${customer.loyaltyPoints}',
          icon: Icons.stars_rounded,
          color: AppColors.yellow,
        ),
      ],
    );
  }

  Widget _buildLoyaltyCard(
      BuildContext context, CustomerEntity customer) {
    final discountCents = customer.redeemableDiscountCents;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.yellowDim,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.stars_rounded,
                color: AppColors.yellow, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${customer.loyaltyPoints} Punkte',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '= ${Money.format(discountCents)} Rabatt verfügbar',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LoyaltyScreen(customerId: customer.id),
            )),
            icon: const Icon(Icons.open_in_new_rounded, size: 14),
            label: const Text('Verwalten'),
            style: TextButton.styleFrom(foregroundColor: AppColors.yellow),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo(CustomerEntity customer) {
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
            'Kontaktinformationen',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (customer.phone != null) ...[
            _ContactRow(
                icon: Icons.phone_rounded,
                label: 'Telefon',
                value: customer.phone!),
            const SizedBox(height: 8),
          ],
          if (customer.email != null) ...[
            _ContactRow(
                icon: Icons.email_rounded,
                label: 'E-Mail',
                value: customer.email!),
            const SizedBox(height: 8),
          ],
          if (customer.address != null) ...[
            _ContactRow(
                icon: Icons.location_on_rounded,
                label: 'Adresse',
                value: customer.address!),
            const SizedBox(height: 8),
          ],
          if (customer.birthday != null)
            _ContactRow(
                icon: Icons.cake_rounded,
                label: 'Geburtstag',
                value: customer.birthday!),
        ],
      ),
    );
  }

  Widget _buildNotes(CustomerEntity customer) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sticky_note_2_rounded,
                  size: 14, color: AppColors.yellow),
              SizedBox(width: 6),
              Text(
                'Notizen',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            customer.notes!,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory(
      AsyncValue<List<LoyaltyTransactionEntity>> txAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Letzte Transaktionen',
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
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Keine Transaktionen',
                      style: TextStyle(color: AppColors.textDim)),
                ),
              );
            }
            return Column(
              children: transactions
                  .take(10)
                  .map((tx) => _TransactionRow(tx: tx))
                  .toList(),
            );
          },
          loading: () => const SizedBox(
            height: 60,
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

  Color _tierColor(CustomerTier tier) {
    return switch (tier) {
      CustomerTier.bronze => const Color(0xFFCD7F32),
      CustomerTier.silver => const Color(0xFFC0C0C0),
      CustomerTier.gold => AppColors.yellow,
    };
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ContactRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textDim)),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final LoyaltyTransactionEntity tx;

  const _TransactionRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isEarn = tx.isEarning;
    final color = isEarn ? AppColors.green : AppColors.red;
    final sign = isEarn ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isEarn ? Icons.add_rounded : Icons.remove_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description ?? _typeName(tx.type),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
                Text(
                  DateFormat('dd.MM.yyyy HH:mm').format(tx.createdAt),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          Text(
            '$sign${tx.points} Pts',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
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
