import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'sidebar.dart';
import '../../core/theme/app_theme.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/providers/theme_provider.dart';

const _sidebarWidth = 240.0;
const _breakpoint = 1024.0;

class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= _breakpoint;
    final currentRoute = GoRouterState.of(context).uri.path;

    if (isWide) {
      return _WideLayout(currentRoute: currentRoute, child: child);
    }
    return _NarrowLayout(currentRoute: currentRoute, child: child);
  }
}

// ---------------------------------------------------------------------------
// Wide layout: fixed sidebar + scrollable content
// ---------------------------------------------------------------------------

class _WideLayout extends ConsumerWidget {
  final Widget child;
  final String currentRoute;

  const _WideLayout({required this.child, required this.currentRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: _sidebarWidth,
            child: Sidebar(currentRoute: currentRoute),
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(isDark: isDark, ref: ref),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Narrow layout: drawer sidebar
// ---------------------------------------------------------------------------

class _NarrowLayout extends ConsumerStatefulWidget {
  final Widget child;
  final String currentRoute;

  const _NarrowLayout({required this.child, required this.currentRoute});

  @override
  ConsumerState<_NarrowLayout> createState() => _NarrowLayoutState();
}

class _NarrowLayoutState extends ConsumerState<_NarrowLayout> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      key: _scaffoldKey,
      drawer: SizedBox(
        width: _sidebarWidth,
        child: Drawer(
          shape: const RoundedRectangleBorder(),
          child: Sidebar(
            currentRoute: widget.currentRoute,
            onClose: () => _scaffoldKey.currentState?.closeDrawer(),
          ),
        ),
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('GastroCore'),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
        ],
      ),
      body: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar (wide layout)
// ---------------------------------------------------------------------------

class _TopBar extends ConsumerWidget {
  final bool isDark;
  final WidgetRef ref;

  const _TopBar({required this.isDark, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline.withAlpha(128)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Page title is provided by the child — just show breadcrumb placeholder
          Text(
            'GastroCore',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          // Theme toggle
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20,
            ),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            tooltip: isDark ? 'Light Mode' : 'Dark Mode',
          ),
          const SizedBox(width: 8),
          // User chip
          if (user != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.primary.withAlpha(51),
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(user.name, style: theme.textTheme.labelLarge),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
