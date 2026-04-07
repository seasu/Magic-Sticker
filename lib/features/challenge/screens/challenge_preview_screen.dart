import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../billing/providers/pro_purchase_provider.dart';
import '../../../shared/widgets/pro_unlock_sheet.dart';

/// 朋友點擊分享連結後進入的挑戰預覽頁。
///
/// 從 Firestore `challenges/{code}` 讀取挑戰資訊，
/// 顯示模板摘要後讓使用者一鍵進入生成流程。
class ChallengePreviewScreen extends ConsumerStatefulWidget {
  final String code;

  const ChallengePreviewScreen({super.key, required this.code});

  @override
  ConsumerState<ChallengePreviewScreen> createState() => _ChallengePreviewScreenState();
}

class _ChallengePreviewScreenState extends ConsumerState<ChallengePreviewScreen> {
  Map<String, dynamic>? _challenge;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChallenge();
  }

  Future<void> _loadChallenge() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('challenges')
          .doc(widget.code.toUpperCase())
          .get();

      if (!doc.exists) {
        setState(() {
          _error = '此挑戰碼不存在或已失效';
          _loading = false;
        });
        return;
      }

      final data = doc.data()!;

      // 過期檢查
      final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
      if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
        setState(() {
          _error = '此挑戰碼已過期（有效期 30 天）';
          _loading = false;
        });
        return;
      }

      if (!(data['isActive'] as bool? ?? false)) {
        setState(() {
          _error = '此挑戰已結束';
          _loading = false;
        });
        return;
      }

      // 記錄 Analytics
      AnalyticsService.logChallengeLinkOpened(
        code: widget.code,
        installed: true, // 已安裝才能到這頁
        resolved: true,
      );

      setState(() {
        _challenge = data;
        _loading = false;
      });
    } catch (_) {
      AnalyticsService.logChallengeLinkOpened(
        code: widget.code,
        installed: true,
        resolved: false,
      );
      setState(() {
        _error = '載入失敗，請檢查網路連線';
        _loading = false;
      });
    }
  }

  void _startGenerate() {
    final data = _challenge!;
    final isProChallenge = data['templateType'] == 'pro_custom' ||
        data['customStyleDesc'] != null;

    // Pro 挑戰：未購買 Pro 的用戶先彈出購買頁
    if (isProChallenge) {
      final isPro = ref.read(isProUnlockedProvider).valueOrNull ?? false;
      if (!isPro) {
        ProUnlockSheet.show(context);
        return;
      }
    }

    final styleIndex = (data['presetStyleIndex'] as num?)?.toInt();
    final rawIds = data['presetCategoryIds'];
    final categoryIds =
        rawIds == null ? null : List<String>.from(rawIds as List);
    final customStyleDesc = data['customStyleDesc'] as String?;
    final customEmotionDesc = data['customEmotionDesc'] as String?;

    ref.read(pendingChallengeProvider.notifier).state = ChallengeParams(
      challengeCode: widget.code,
      styleIndex: styleIndex,
      categoryIds: categoryIds,
      customStyleDesc: customStyleDesc,
      customEmotionDesc: customEmotionDesc,
      isProChallenge: isProChallenge,
    );
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          '挑戰預覽',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : _error != null
                ? _ErrorView(
                    message: _error!,
                    onBack: () => context.pop(),
                  )
                : _ChallengeContent(
                    code: widget.code,
                    challenge: _challenge!,
                    onStart: _startGenerate,
                  ),
      ),
    );
  }
}

// ── _ChallengeContent ─────────────────────────────────────────────────────────

class _ChallengeContent extends StatelessWidget {
  final String code;
  final Map<String, dynamic> challenge;
  final VoidCallback onStart;

  const _ChallengeContent({
    required this.code,
    required this.challenge,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          // 標題區
          const Text(
            '✨',
            style: TextStyle(fontSize: 64),
          ),
          const SizedBox(height: 16),
          const Text(
            '朋友邀你試試同款貼圖！',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            '用 AI 把你的照片變成 LINE 貼圖',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 36),

          // 挑戰碼展示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              children: [
                const Text(
                  '挑戰碼',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  code.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),

          // CTA 按鈕
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.gradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onStart,
              child: const Text(
                '用這款風格生成貼圖 →',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── _ErrorView ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onBack;

  const _ErrorView({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😕', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              onPressed: onBack,
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
