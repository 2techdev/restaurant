/// Staff Management tab for the Back Office screen.
///
/// Displays staff member cards with role badges, PIN management, and
/// active/inactive toggle. Full CRUD via [authRepositoryProvider].
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/di/providers.dart';
import 'package:gastrocore_pos/core/utils/id_generator.dart';
import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/auth/domain/entities/user_entity.dart';
import 'package:gastrocore_pos/shared/widgets/pos_text_field.dart';
import 'package:gastrocore_pos/shared/widgets/pos_button.dart';

// ---------------------------------------------------------------------------
// Role helpers
// ---------------------------------------------------------------------------

const _roleLabels = {
  UserRole.admin: 'Admin',
  UserRole.manager: 'Manager',
  UserRole.waiter: 'Garson',
  UserRole.cashier: 'Kasiyer',
  UserRole.kitchen: 'Mutfak',
};

Color _roleColor(UserRole role) {
  return switch (role) {
    UserRole.admin => AppColors.red,
    UserRole.manager => AppColors.orange,
    UserRole.waiter => AppColors.primary,
    UserRole.cashier => AppColors.green,
    UserRole.kitchen => AppColors.yellow,
  };
}

Color _roleDimColor(UserRole role) {
  return switch (role) {
    UserRole.admin => AppColors.redDim,
    UserRole.manager => AppColors.orangeDim,
    UserRole.waiter => AppColors.accentDim,
    UserRole.cashier => AppColors.greenDim,
    UserRole.kitchen => AppColors.yellowDim,
  };
}

String _hashPin(String pin) {
  return sha256.convert(utf8.encode(pin)).toString();
}

// ---------------------------------------------------------------------------
// StaffManagementTab
// ---------------------------------------------------------------------------

class StaffManagementTab extends ConsumerStatefulWidget {
  const StaffManagementTab({super.key});

  @override
  ConsumerState<StaffManagementTab> createState() =>
      _StaffManagementTabState();
}

class _StaffManagementTabState extends ConsumerState<StaffManagementTab> {
  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersListProvider);

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
            // Header
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'Personel Yonetimi',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            // Staff list
            Expanded(
              child: usersAsync.when(
                data: _buildStaffList,
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
                error: (e, _) => Center(
                  child: Text(
                    'Hata: $e',
                    style:
                        const TextStyle(color: AppColors.red, fontSize: 13),
                  ),
                ),
              ),
            ),

            // Add staff button
            Padding(
              padding: const EdgeInsets.all(16),
              child: PosGradientButton(
                label: 'Personel Ekle',
                icon: Icons.person_add_rounded,
                height: 44,
                onPressed: _showStaffDialog,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffList(List<UserEntity> users) {
    if (users.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 48, color: AppColors.textDim),
            SizedBox(height: 16),
            Text(
              'Henuz personel yok',
              style: TextStyle(color: AppColors.textDim, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: users.length,
      itemBuilder: (context, index) => _buildStaffCard(users[index]),
    );
  }

  Widget _buildStaffCard(UserEntity user) {
    final roleColor = _roleColor(user.role);
    final roleDim = _roleDimColor(user.role);
    final initials = user.name.isNotEmpty
        ? user.name
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
            .join()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: roleDim,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: roleColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Name + role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleDim,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _roleLabels[user.role] ?? user.role.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: roleColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // PIN status
          GestureDetector(
            onTap: () => _showChangePinDialog(user),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 14, color: AppColors.textDim),
                  SizedBox(width: 6),
                  Text(
                    'PIN Degistir',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Active/Inactive badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: user.isActive ? AppColors.greenDim : AppColors.redDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              user.isActive ? 'Aktif' : 'Pasif',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: user.isActive ? AppColors.green : AppColors.red,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Edit
          _iconButton(
            Icons.edit_rounded,
            onTap: () => _showStaffDialog(existing: user),
          ),
          const SizedBox(width: 4),

          // Delete
          _iconButton(
            Icons.delete_outline_rounded,
            color: AppColors.red,
            onTap: () => _deleteUser(user),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(
    IconData icon, {
    Color color = AppColors.textDim,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  // =========================================================================
  // Staff dialog (Add/Edit)
  // =========================================================================

  Future<void> _showStaffDialog({UserEntity? existing}) async {
    final nameController =
        TextEditingController(text: existing?.name ?? '');
    final pinController = TextEditingController();
    UserRole selectedRole = existing?.role ?? UserRole.waiter;
    bool isActive = existing?.isActive ?? true;

    final result = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppColors.surfaceContainerHighest,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing != null
                          ? 'Personel Duzenle'
                          : 'Personel Ekle',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Name
                    PosTextField(
                      label: 'Ad Soyad',
                      hint: 'ornegin: Mehmet Kaya',
                      controller: nameController,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),

                    // Role
                    const Text(
                      'Rol',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.bgInput,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<UserRole>(
                          value: selectedRole,
                          dropdownColor: AppColors.surfaceContainerHighest,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textDim,
                          ),
                          items: UserRole.values.map((r) {
                            return DropdownMenuItem(
                              value: r,
                              child: Text(
                                  _roleLabels[r] ?? r.name),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => selectedRole = v);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // PIN
                    PosTextField(
                      label: existing != null
                          ? 'Yeni PIN (bos birakirsan degismez)'
                          : 'PIN (4-6 hane)',
                      hint: '\u2022\u2022\u2022\u2022',
                      controller: pinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),

                    // Active toggle
                    Row(
                      children: [
                        const Text(
                          'Aktif',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        Switch(
                          value: isActive,
                          activeThumbColor: AppColors.green,
                          inactiveTrackColor: AppColors.surfaceContainerHigh,
                          onChanged: (v) =>
                              setDialogState(() => isActive = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: PosGhostButton(
                            label: 'Iptal',
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PosGradientButton(
                            label: 'Kaydet',
                            height: 44,
                            onPressed: () => Navigator.pop(ctx, true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final repo = ref.read(authRepositoryProvider);
      final tenantId = ref.read(tenantIdProvider);
      final now = DateTime.now();

      if (existing != null) {
        final pinHash = pinController.text.isNotEmpty
            ? _hashPin(pinController.text)
            : existing.pinHash;

        await repo.updateUser(existing.copyWith(
          name: nameController.text.trim(),
          role: selectedRole,
          pinHash: pinHash,
          isActive: isActive,
          updatedAt: now,
        ));
      } else {
        if (pinController.text.length < 4) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppColors.red,
                content: Text('PIN en az 4 haneli olmalidir'),
              ),
            );
          }
          nameController.dispose();
          pinController.dispose();
          return;
        }

        final newUser = UserEntity(
          id: IdGenerator.generateId(),
          tenantId: tenantId,
          name: nameController.text.trim(),
          pinHash: _hashPin(pinController.text),
          role: selectedRole,
          isActive: isActive,
          createdAt: now,
          updatedAt: now,
        );
        await repo.createUser(newUser);
      }

      ref.invalidate(usersListProvider);
    }

    nameController.dispose();
    pinController.dispose();
  }

  // =========================================================================
  // Change PIN dialog
  // =========================================================================

  Future<void> _showChangePinDialog(UserEntity user) async {
    final pinController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PIN Degistir',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                PosTextField(
                  label: 'Yeni PIN (4-6 hane)',
                  hint: '\u2022\u2022\u2022\u2022',
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: PosGhostButton(
                        label: 'Iptal',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PosGradientButton(
                        label: 'Kaydet',
                        height: 44,
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true && pinController.text.length >= 4) {
      final repo = ref.read(authRepositoryProvider);
      await repo.updateUser(user.copyWith(
        pinHash: _hashPin(pinController.text),
        updatedAt: DateTime.now(),
      ));
      ref.invalidate(usersListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.green,
            content: Text('PIN basariyla degistirildi'),
          ),
        );
      }
    } else if (result == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.red,
            content: Text('PIN en az 4 haneli olmalidir'),
          ),
        );
      }
    }

    pinController.dispose();
  }

  // =========================================================================
  // Delete user
  // =========================================================================

  Future<void> _deleteUser(UserEntity user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.bgOverlay,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Personel Sil',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '"${user.name}" personelini silmek istediginize emin misiniz?',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: PosGhostButton(
                        label: 'Iptal',
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PosSolidButton(
                        label: 'Sil',
                        color: AppColors.red,
                        height: 44,
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final repo = ref.read(authRepositoryProvider);
      await repo.deleteUser(user.id);
      ref.invalidate(usersListProvider);
    }
  }
}
