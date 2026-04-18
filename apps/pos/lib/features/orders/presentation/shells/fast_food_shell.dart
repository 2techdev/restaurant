/// Fast-food shell — placeholder.
///
/// The fine-dining layout is the Sprint 0/1 deliverable. The fast-food
/// variant (single product grid, no Gang panel, no cover banner, quick-pay
/// CTA) is scheduled for v2. We keep the file + route wired so the PosMode
/// switch compiles and operators can see the mode flip without a crash.
library;

import 'package:flutter/material.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/core/theme/app_tokens.dart';

class FastFoodShell extends StatelessWidget {
  const FastFoodShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: const Center(
        child: Padding(
          padding: AppInsets.all16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.fastfood_rounded,
                size: 64,
                color: AppColors.textDim,
              ),
              SizedBox(height: AppTokens.space16),
              Text(
                'Fast Food modu — yakında',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: AppTokens.space8),
              Text(
                'Şu an sadece Fine Dining modu desteklenmektedir. '
                'Ayarlar ekranından modu değiştirebilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
