import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/customers/domain/entities/customer_entity.dart';
import 'package:gastrocore_pos/features/customers/presentation/providers/customer_provider.dart';
import 'package:gastrocore_pos/features/customers/presentation/screens/customer_detail_screen.dart';
import 'package:gastrocore_pos/features/customers/presentation/screens/customer_form_screen.dart';
import 'package:gastrocore_pos/features/customers/presentation/widgets/customer_card.dart';
import 'package:gastrocore_pos/shared/widgets/pos_empty_state.dart';


class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() =>
      _CustomerListScreenState();
}

class _CustomerListScreenState
    extends ConsumerState<CustomerListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(context),
          _buildSearchBar(),
          _buildTierFilter(),
          Expanded(child: _buildList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surfaceDim,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Neuer Kunde'),
        onPressed: () => _openForm(context),
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
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Kundenverwaltung',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          _buildBirthdayBadge(),
        ],
      ),
    );
  }

  Widget _buildBirthdayBadge() {
    final reminders = ref.watch(birthdayRemindersProvider);
    return reminders.when(
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.purpleDim,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cake_rounded,
                  size: 14, color: AppColors.purple),
              const SizedBox(width: 4),
              Text(
                '${list.length} Geburtstag${list.length > 1 ? 'e' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Name, Telefon oder E-Mail suchen…',
          hintStyle: const TextStyle(
              color: AppColors.textDim, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded,
              color: AppColors.textSecondary, size: 18),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    ref.read(customerSearchProvider.notifier).state = '';
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.bgInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (v) =>
            ref.read(customerSearchProvider.notifier).state = v,
      ),
    );
  }

  Widget _buildTierFilter() {
    final selected = ref.watch(customerTierFilterProvider);
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _TierChip(
              label: 'Alle',
              selected: selected == null,
              color: AppColors.textSecondary,
              onTap: () =>
                  ref.read(customerTierFilterProvider.notifier).state = null,
            ),
            const SizedBox(width: 8),
            _TierChip(
              label: 'Bronze',
              selected: selected == CustomerTier.bronze,
              color: const Color(0xFFCD7F32),
              onTap: () => ref
                  .read(customerTierFilterProvider.notifier)
                  .state = CustomerTier.bronze,
            ),
            const SizedBox(width: 8),
            _TierChip(
              label: 'Silber',
              selected: selected == CustomerTier.silver,
              color: const Color(0xFFC0C0C0),
              onTap: () => ref
                  .read(customerTierFilterProvider.notifier)
                  .state = CustomerTier.silver,
            ),
            const SizedBox(width: 8),
            _TierChip(
              label: 'Gold',
              selected: selected == CustomerTier.gold,
              color: AppColors.yellow,
              onTap: () => ref
                  .read(customerTierFilterProvider.notifier)
                  .state = CustomerTier.gold,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final customers = ref.watch(filteredCustomersProvider);
    return customers.when(
      data: (list) {
        if (list.isEmpty) {
          return const PosEmptyState(
            icon: Icons.people_outline_rounded,
            title: 'Keine Kunden gefunden',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(customersProvider),
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => CustomerCard(
              customer: list[i],
              onTap: () => _openDetail(context, list[i].id),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Fehler: $e',
            style: const TextStyle(color: AppColors.red)),
      ),
    );
  }

  void _openDetail(BuildContext context, String customerId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CustomerDetailScreen(customerId: customerId),
    ));
  }

  void _openForm(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const CustomerFormScreen(),
    ));
  }
}

class _TierChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TierChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : AppColors.bgInput,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? color : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
