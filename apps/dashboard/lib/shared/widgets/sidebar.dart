import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/providers/theme_provider.dart';

class _NavItem {
  final IconData icon;
  final IconData iconSelected;
  final String label;
  final String route;

  const _NavItem({
    required this.icon,
    required this.iconSelected,
    required this.label,
    required this.route,
  });
}

const _navItems = [
  _NavItem(
    icon: Icons.dashboard_outlined,
    iconSelected: Icons.dashboard,
    label: 'Dashboard',
    route: '/',
  ),
  _NavItem(
    icon: Icons.receipt_long_outlined,
    iconSelected: Icons.receipt_long,
    label: 'Bestellungen',
    route: '/orders',
  ),
  _NavItem(
    icon: Icons.restaurant_menu_outlined,
    iconSelected: Icons.restaurant_menu,
    label: 'Speisekarte',
    route: '/menu',
  ),
  _NavItem(
    icon: Icons.bar_chart_outlined,
    iconSelected: Icons.bar_chart,
    label: 'Berichte',
    route: '/reports',
  ),
  _NavItem(
    icon: Icons.settings_outlined,
    iconSelected: Icons.settings,
    label: 'Einstellungen',
    route: '/settings',
  ),
];

class Sidebar extends ConsumerWidget {
  final String currentRoute;
  final VoidCallback? onClose;

  const Sidebar({super.key, required this.currentRoute, this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final bg = isDark ? AppColors.sidebarBgDark : AppColors.sidebarBg;

    return Container(
      color: bg,
      child: SafeArea(
        child: Column(
          children: [
            // Logo
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.restaurant, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'GastroCore',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (onClose != null) ...[
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.sidebarText),
                      onPressed: onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),
            const Divider(color: Color(0xFF374151), height: 1),
            const SizedBox(height: 8),

            // Nav items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: _navItems.map((item) {
                  final isActive = currentRoute == item.route ||
                      (item.route != '/' && currentRoute.startsWith(item.route));
                  return _NavTile(
                    item: item,
                    isActive: isActive,
                    onTap: () {
                      if (onClose != null) onClose!();
                      context.go(item.route);
                    },
                  );
                }).toList(),
              ),
            ),

            const Divider(color: Color(0xFF374151), height: 1),

            // Bottom: theme toggle + user
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Theme toggle
                  _SidebarButton(
                    icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    label: isDark ? 'Light Mode' : 'Dark Mode',
                    onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                  ),
                  const SizedBox(height: 4),

                  // User tile
                  if (user != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primary.withAlpha(51),
                            child: Text(
                              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  user.role,
                                  style: const TextStyle(
                                    color: AppColors.sidebarText,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, color: AppColors.sidebarText, size: 18),
                            onPressed: () => ref.read(authProvider.notifier).logout(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Abmelden',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTile({required this.item, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.sidebarActive : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? item.iconSelected : item.icon,
                size: 20,
                color: isActive ? Colors.white : AppColors.sidebarText,
              ),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.sidebarText,
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.sidebarText),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(color: AppColors.sidebarText, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
