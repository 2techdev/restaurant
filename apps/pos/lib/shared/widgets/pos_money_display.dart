/// Money display widgets following the Stitch "Precision POS Framework".
///
/// Provides two monetary display variants:
///
/// - [PosMoneyDisplay] — Standard inline money display with currency code
///   and tabular figures. Uses the project's [Money] value object for
///   formatting.
///
/// - [PosHeroMoney] — Large hero-sized money display for totals, shift
///   summaries, and payment confirmation screens.
///
/// Both use tabular figures ([FontFeature.tabularFigures]) to ensure
/// columns of numbers align perfectly in lists and tables.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/utils/money.dart';

// ---------------------------------------------------------------------------
// PosMoneyDisplay
// ---------------------------------------------------------------------------

/// A standard inline money display widget.
///
/// Formats an amount in cents using the [Money] value object, producing
/// output like "CHF 28.50" with tabular figures for perfect column
/// alignment.
///
/// ```dart
/// PosMoneyDisplay(
///   amountCents: 2850,
///   currencyCode: 'CHF',
///   fontSize: 16,
///   fontWeight: FontWeight.w800,
/// )
/// ```
class PosMoneyDisplay extends StatelessWidget {
  const PosMoneyDisplay({
    super.key,
    required this.amountCents,
    this.currencyCode = 'CHF',
    this.fontSize = 16,
    this.fontWeight = FontWeight.w800,
    this.color,
    this.showCurrency = true,
  });

  /// Amount in the smallest currency unit (cents / Rappen).
  final int amountCents;

  /// ISO 4217 currency code. Defaults to 'CHF'.
  final String currencyCode;

  /// Font size. Defaults to 16.
  final double fontSize;

  /// Font weight. Defaults to w800 (extra-bold).
  final FontWeight fontWeight;

  /// Text color. Defaults to [AppColors.textPrimary].
  final Color? color;

  /// Whether to show the currency code prefix. Defaults to true.
  final bool showCurrency;

  @override
  Widget build(BuildContext context) {
    final money = Money(amountCents);
    final displayText =
        showCurrency ? money.format(currencyCode) : money.formatCompact();
    final textColor = color ?? AppColors.textPrimary;

    return Text(
      displayText,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: textColor,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: -0.3,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ---------------------------------------------------------------------------
// PosHeroMoney
// ---------------------------------------------------------------------------

/// A large hero-sized money display for totals, shift summaries, and
/// payment confirmation screens.
///
/// Uses 28–32px extra-bold text with the currency code prefix in a
/// slightly smaller weight. Defaults to green color to convey
/// positive value.
///
/// ```dart
/// PosHeroMoney(
///   amountCents: 245000,
///   currencyCode: 'CHF',
///   color: AppColors.green,
/// )
/// ```
class PosHeroMoney extends StatelessWidget {
  const PosHeroMoney({
    super.key,
    required this.amountCents,
    this.currencyCode = 'CHF',
    this.color,
    this.fontSize = 32,
  });

  /// Amount in the smallest currency unit (cents / Rappen).
  final int amountCents;

  /// ISO 4217 currency code. Defaults to 'CHF'.
  final String currencyCode;

  /// Text color. Defaults to [AppColors.green].
  final Color? color;

  /// Font size for the amount portion. Defaults to 32.
  /// The currency prefix is rendered at 60% of this size.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final money = Money(amountCents);
    final textColor = color ?? AppColors.green;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // Currency prefix
        Text(
          currencyCode,
          style: TextStyle(
            fontSize: fontSize * 0.55,
            fontWeight: FontWeight.w600,
            color: textColor.withValues(alpha: 0.7),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 6),

        // Amount
        Text(
          money.formatCompact(),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: textColor,
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: -0.5,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
