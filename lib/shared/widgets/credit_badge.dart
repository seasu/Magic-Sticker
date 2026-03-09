import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../features/billing/providers/credit_provider.dart';

/// AppBar 右上角的點數顯示徽章
///
/// 用法：直接放在 AppBar actions 或 Row 中
/// ```dart
/// Row(children: [ ..., const CreditBadge() ])
/// ```
class CreditBadge extends ConsumerWidget {
  const CreditBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(creditProvider);

    final bool isLow = credits <= 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: isLow ? null : AppColors.gradient,
        color: isLow ? const Color(0xFFF2F2F7) : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLow ? Icons.bolt_outlined : Icons.bolt_rounded,
            size: 14,
            color: isLow ? AppColors.textSecondary : Colors.white,
          ),
          const SizedBox(width: 3),
          Text(
            '$credits',
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isLow ? AppColors.textSecondary : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
