/// Switches between [FineDiningShell] and [FastFoodShell] based on the
/// active [PosMode]. Acts as the single entry point wired into the router.
///
/// Kept deliberately thin — all layout logic lives in the shell widgets.
/// Reads [posModeProvider] reactively so mode changes from Settings swap
/// the UI without re-navigating.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/pos_mode/pos_mode.dart';
import 'package:gastrocore_pos/features/orders/presentation/shells/fast_food_shell.dart';
import 'package:gastrocore_pos/features/orders/presentation/shells/fine_dining_shell.dart';

class PosShellRouter extends ConsumerWidget {
  const PosShellRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(posModeProvider);
    return switch (mode) {
      PosMode.fineDining => const FineDiningShell(),
      PosMode.fastFood => const FastFoodShell(),
      PosMode.quickService => const FastFoodShell(),
    };
  }
}
