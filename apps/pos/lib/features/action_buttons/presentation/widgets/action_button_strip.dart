/// A horizontal strip of user-defined function buttons.
///
/// Mirrors the visual style of `FavoritesBar` so the two strips feel like
/// one family when stacked together. The strip is completely hidden when
/// no buttons are configured for the given position, rather than showing an
/// empty band.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gastrocore_pos/core/theme/app_tokens.dart';
import 'package:gastrocore_pos/core/theme/kinetic_theme.dart';
import 'package:gastrocore_pos/features/action_buttons/domain/entities/action_button_entity.dart';
import 'package:gastrocore_pos/features/action_buttons/presentation/action_button_dispatcher.dart';
import 'package:gastrocore_pos/features/action_buttons/presentation/providers/action_button_provider.dart';

class ActionButtonStrip extends ConsumerWidget {
  const ActionButtonStrip({
    super.key,
    this.position = ActionButtonPosition.ticketScreen,
    this.label = 'FUNKTION',
  });

  final ActionButtonPosition position;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buttonsAsync =
        ref.watch(actionButtonsByPositionProvider(position));
    final buttons = buttonsAsync.valueOrNull ?? const <ActionButtonEntity>[];

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 64,
      color: GcColors.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space16,
        vertical: AppTokens.space8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'WorkSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: GcColors.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.space12),
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: AppTokens.space8),
            Expanded(
              child: _ActionTile(
                button: buttons[i],
                onTap: () => ActionButtonDispatcher.dispatch(
                  button: buttons[i],
                  context: context,
                  ref: ref,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.button, required this.onTap});

  final ActionButtonEntity button;
  final VoidCallback onTap;

  static const Map<String, IconData> _iconMap = <String, IconData>{
    'percent': Icons.percent,
    'card_giftcard': Icons.card_giftcard,
    'sticky_note_2': Icons.sticky_note_2,
    'receipt_long': Icons.receipt_long,
    'restaurant_menu': Icons.restaurant_menu,
    'local_offer': Icons.local_offer,
    'money_off': Icons.money_off,
    'delete_sweep': Icons.delete_sweep,
    'star': Icons.star,
    'bolt': Icons.bolt,
  };

  Color _defaultColor(ActionButtonType type) {
    return switch (type) {
      ActionButtonType.percentDiscount => GcColors.catOrange,
      ActionButtonType.fixedDiscount => GcColors.catOrange,
      ActionButtonType.markGift => GcColors.catRed,
      ActionButtonType.addNote => GcColors.catCyan,
      ActionButtonType.setCourse => const Color(0xFFBF5AF2),
      ActionButtonType.printBill => GcColors.catGreen,
      ActionButtonType.voidItem => GcColors.catRed,
      ActionButtonType.customScript => GcColors.catTeal,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bg = button.color ?? _defaultColor(button.actionType);
    final icon = button.iconName == null ? null : _iconMap[button.iconName];

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white24,
        highlightColor: Colors.white10,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: kInsetHighlight, width: 2),
            ),
          ),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.space12),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    button.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'WorkSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
