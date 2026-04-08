import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app.dart';
import '../../../core/models/emotion_category.dart';
import '../../../core/models/sticker_shape.dart';
import '../../../core/models/sticker_style.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../billing/providers/pro_purchase_provider.dart';
import '../../../shared/widgets/pro_unlock_sheet.dart';

/// 朋友點擊分享連結後進入的挑戰預覽頁。
///
/// 從 Firestore `challenges/{code}` 讀取挑戰資訊，顯示風格與情緒後
/// 讓使用者直接在此頁選照片，進入生成流程（獨立挑戰流程，不跳回首頁）。
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
        installed: true,
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

  Future<void> _pickPhoto(ImageSource source) async {
    final data = _challenge!;
    final isProChallenge =
        data['templateType'] == 'pro_custom' || data['customStyleDesc'] != null;

    if (isProChallenge) {
      final isPro = ref.read(isProUnlockedProvider).valueOrNull ?? false;
      if (!isPro) {
        ProUnlockSheet.show(context);
        return;
      }
    }

    HapticFeedback.mediumImpact();
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 95);
    if (picked == null || !mounted) return;

    if (source == ImageSource.camera) {
      final shouldSave = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _SavePhotoDialog(imagePath: picked.path),
      );
      if (!mounted) return;
      if (shouldSave == true) {
        try {
          if (!await Gal.hasAccess()) await Gal.requestAccess();
          await Gal.putImage(picked.path);
        } catch (_) {}
      }
    }

    final styleIndex = (data['presetStyleIndex'] as num?)?.toInt() ?? 0;
    final rawIds = data['presetCategoryIds'];
    final categoryIds = rawIds == null ? null : List<String>.from(rawIds as List);

    if (!mounted) return;
    context.push(
      '/editor',
      extra: EditorArgs(
        imagePath: picked.path,
        styleIndex: styleIndex,
        stickerShape: StickerShape.square,
        categoryIds: categoryIds ?? kDefaultCategoryIds,
        customStyleDesc: data['customStyleDesc'] as String?,
        customEmotionDesc: data['customEmotionDesc'] as String?,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '朋友的挑戰',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF5864)),
              )
            : _error != null
                ? _ErrorView(
                    message: _error!,
                    onBack: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/');
                      }
                    },
                  )
                : _ChallengeContent(
                    code: widget.code,
                    challenge: _challenge!,
                    onPickPhoto: _pickPhoto,
                    isProChallenge: _challenge!['templateType'] == 'pro_custom' ||
                        _challenge!['customStyleDesc'] != null,
                    isPro: ref.watch(isProUnlockedProvider).valueOrNull ?? false,
                  ),
      ),
    );
  }
}

// ── _ChallengeContent ─────────────────────────────────────────────────────────

class _ChallengeContent extends StatelessWidget {
  final String code;
  final Map<String, dynamic> challenge;
  final void Function(ImageSource) onPickPhoto;
  final bool isProChallenge;
  final bool isPro;

  const _ChallengeContent({
    required this.code,
    required this.challenge,
    required this.onPickPhoto,
    required this.isProChallenge,
    required this.isPro,
  });

  @override
  Widget build(BuildContext context) {
    // 計算風格資訊
    final styleIndex = (challenge['presetStyleIndex'] as num?)?.toInt() ?? 0;
    final customStyleDesc = challenge['customStyleDesc'] as String?;
    final style = StickerStyle.values[styleIndex.clamp(0, StickerStyle.values.length - 1)];
    final styleName = customStyleDesc ?? style.label;
    final styleEmoji = customStyleDesc != null ? '✨' : style.emoji;

    // 計算情緒資訊
    final customEmotionDesc = challenge['customEmotionDesc'] as String?;
    final rawIds = challenge['presetCategoryIds'];
    final categoryIds = rawIds == null ? null : List<String>.from(rawIds as List);
    final emotionSummary = customEmotionDesc ??
        (categoryIds != null ? '${categoryIds.length} 種情緒' : '預設 8 種情緒');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 邀請頭部 ──
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.gradient,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Text(
                  '✨ 朋友挑戰邀請',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '朋友邀你試試同款貼圖！',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            '選張照片，立刻生成同款 LINE 貼圖',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // ── 風格卡片 ──
          _InfoCard(
            emoji: styleEmoji,
            label: '風格',
            value: styleName,
            showProBadge: isProChallenge,
          ),
          const SizedBox(height: 12),

          // ── 情緒卡片 ──
          _InfoCard(
            emoji: '🎭',
            label: '情緒',
            value: emotionSummary,
            showProBadge: isProChallenge,
          ),
          const SizedBox(height: 20),

          // ── 挑戰碼（次要顯示）──
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '挑戰碼　',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  code.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // ── 選照片按鈕（Pro 鎖定時替換）──
          if (isProChallenge && !isPro)
            _ProLockedButtons(
              onUnlock: () => ProUnlockSheet.show(context),
            )
          else ...[
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
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () => onPickPhoto(ImageSource.gallery),
                child: const Text(
                  '從相簿選取照片',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF5864),
                side: const BorderSide(color: Color(0xFFFF5864)),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => onPickPhoto(ImageSource.camera),
              child: const Text(
                '拍照',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── _InfoCard ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final bool showProBadge;

  const _InfoCard({
    required this.emoji,
    required this.label,
    required this.value,
    this.showProBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Pro badge（右上角）
        if (showProBadge)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFAA00),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '✦ PRO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── _ProLockedButtons ─────────────────────────────────────────────────────────

/// Pro 挑戰且用戶尚未解鎖 Pro 時，取代底部選照片按鈕的鎖定提示區。
class _ProLockedButtons extends StatelessWidget {
  final VoidCallback onUnlock;

  const _ProLockedButtons({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          '🔒 此挑戰需要 Pro 方案才能參加',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.gradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              onUnlock();
            },
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: const Text(
              '解鎖 Pro，立即參加',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
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
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF5864),
                side: const BorderSide(color: Color(0xFFFF5864)),
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

// ── _SavePhotoDialog ──────────────────────────────────────────────────────────

class _SavePhotoDialog extends StatelessWidget {
  final String imagePath;

  const _SavePhotoDialog({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Image.file(
              File(imagePath),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              children: [
                const Text(
                  '要把這張照片存到相簿嗎？',
                  style: TextStyle(
                    fontFamily: 'OpenHuninn',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  '下次可直接從相簿選取，不用重拍',
                  style: TextStyle(
                    fontFamily: 'OpenHuninn',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.gradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        '存到相簿',
                        style: TextStyle(
                          fontFamily: 'OpenHuninn',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    '不用，直接繼續',
                    style: TextStyle(
                      fontFamily: 'OpenHuninn',
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
