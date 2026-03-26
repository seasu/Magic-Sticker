import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../models/credit_history_entry.dart';
import '../providers/credit_provider.dart';

const _kPageBg = Color(0xFFF2F2F7);

class CreditHistoryScreen extends ConsumerWidget {
  const CreditHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(creditHistoryProvider);

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        title: Text(
          '點數紀錄',
          style: TextStyle(
            fontFamily: 'OpenHuninn',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: _kPageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            '載入失敗，請稍後再試',
            style: TextStyle(
              fontFamily: 'OpenHuninn',
              color: AppColors.textSecondary,
            ),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 72,
                    color: AppColors.divider,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '還沒有點數紀錄',
                    style: TextStyle(
                      fontFamily: 'OpenHuninn',
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '消耗點數生成貼圖後，\n紀錄將自動顯示於此',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'OpenHuninn',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          // ── 按日期分組 ───────────────────────────────────────────────
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(const Duration(days: 1));

          String _dayLabel(DateTime dt) {
            final d = DateTime(dt.year, dt.month, dt.day);
            if (d == today) return '今天';
            if (d == yesterday) return '昨天';
            return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
          }

          final groups = <({String label, List<CreditHistoryEntry> items})>[];
          for (final e in entries) {
            final label = _dayLabel(e.createdAt);
            if (groups.isEmpty || groups.last.label != label) {
              groups.add((label: label, items: [e]));
            } else {
              groups.last.items.add(e);
            }
          }

          // ── 拍平成 widget 列表 ────────────────────────────────────────
          final widgets = <Widget>[];
          for (var gi = 0; gi < groups.length; gi++) {
            final g = groups[gi];
            widgets.add(
              Padding(
                padding: EdgeInsets.only(
                  left: 4,
                  top: gi == 0 ? 8 : 16,
                  bottom: 8,
                ),
                child: Text(
                  g.label,
                  style: const TextStyle(
                    fontFamily: 'OpenHuninn',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            );
            for (final entry in g.items) {
              widgets.add(_HistoryCard(entry: entry));
              widgets.add(const SizedBox(height: 8));
            }
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(creditHistoryProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: widgets,
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

String _formatDate(DateTime dt) {
  final hh  = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$hh:$min';
}

class _HistoryCard extends StatelessWidget {
  final CreditHistoryEntry entry;
  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isPositive = entry.amount > 0;
    final isRefund   = entry.type == CreditHistoryType.refund;
    final amountColor = isPositive ? AppColors.like : AppColors.nope;
    final amountText  = isPositive ? '+${entry.amount}' : '${entry.amount}';

    // ── 圖示設定 ──────────────────────────────────────────────────────
    final IconData icon;
    final Widget iconWidget;

    switch (entry.type) {
      case CreditHistoryType.earned:
        icon = Icons.add_circle_rounded;
        iconWidget = Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.like.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.like, size: 22),
        );
      case CreditHistoryType.spent:
        icon = Icons.auto_awesome_rounded;
        iconWidget = Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: ShaderMask(
            shaderCallback: (rect) => AppColors.gradient.createShader(rect),
            blendMode: BlendMode.srcATop,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.gradient,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        );
      case CreditHistoryType.refund:
        icon = Icons.replay_rounded;
        const refundColor = Color(0xFFFF9500);
        iconWidget = Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: refundColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(icon, color: refundColor, size: 22),
        );
    }

    // ── Pill badge ────────────────────────────────────────────────────
    final pillBg = isPositive
        ? AppColors.like.withValues(alpha: 0.12)
        : AppColors.nope.withValues(alpha: 0.10);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.reasonLabel,
                    style: const TextStyle(
                      fontFamily: 'OpenHuninn',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatDate(entry.createdAt),
                    style: const TextStyle(
                      fontFamily: 'OpenHuninn',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                amountText,
                style: TextStyle(
                  fontFamily: 'OpenHuninn',
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: amountColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
