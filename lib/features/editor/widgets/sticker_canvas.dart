import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../../core/models/sticker_shape.dart';
import '../../../core/models/sticker_style.dart';
import '../models/sticker_config.dart';
import '../models/sticker_font.dart';

// ─── 選取目標（公開，供 StickerEditSheet 外部控制）────────────────────────────

enum StickerEditTarget { none, image, text }

// ─── 選取框顏色常數 ───────────────────────────────────────────────────────────

const _kHandleColor = Color(0xFF29B6F6); // Blue-400

// ─── 強制勝出的 ScaleGestureRecognizer ────────────────────────────────────────
//
// 編輯模式（enableTextGestures: true）下，showModalBottomSheet isScrollControlled: true
// 會建立 DraggableScrollableSheet，其 VerticalDragGestureRecognizer 在競技場競爭時
// 會對垂直方向的單指 pan 勝出，造成畫布單指拖移無效。
// 覆寫 rejectGesture → acceptGesture 讓此 Recognizer 永遠接受，確保 canvas 優先。
// 僅用於 enableTextGestures 模式，不影響主卡片的水平滑動手勢。
class _CanvasScaleGestureRecognizer extends ScaleGestureRecognizer {
  _CanvasScaleGestureRecognizer({super.debugOwner});

  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}

/// LINE 貼圖畫布
///
/// 互動模式（enableTextGestures = false，主卡片）：
///   - 雙指捏合：縮放 AI 圖片
///   - 點圖：觸發 onTap（打開編輯 Sheet）
///
/// 選取模式（enableTextGestures = true，編輯 Sheet）：
///   - 單指點選文字 / 圖片 → 顯示選取框
///   - 選取後單指拖動：移動物件
///   - 選取後雙指捏合：縮放物件
///   - 選取後雙指旋轉：旋轉物件
///
/// 畫布比例 1:1（正方形）→ 圓形輸出 370×370 px，方形同尺寸
class StickerCanvas extends StatefulWidget {
  final Uint8List? subjectBytes;
  final Uint8List? generatedImage;
  final StickerShape stickerShape;
  final String text;
  final StickerConfig config;

  /// 初始圖片縮放值
  final double initialScale;

  /// 初始圖片位移量
  final Offset initialOffset;

  /// 初始圖片旋轉角度（弧度）
  final double initialImageAngle;

  /// 字型索引（對應 kStickerFonts）
  final int fontIndex;

  /// 字體大小倍率（0.3–3.0）
  final double fontSizeScale;

  /// 文字水平對齊（-1.5=左, 0=中, 1.5=右）
  final double textXAlign;

  /// 文字垂直對齊（-1.5=上, 0=中, 1.5=下）
  final double textYAlign;

  /// 文字旋轉角度（弧度）
  final double textAngle;

  /// 貼圖風格索引（對應 StickerStyle.values），用於未生成狀態的風格示意圖
  final int styleIndex;

  /// 情感類別 id（對應 EmotionCategory.id），用於選擇 style×emotion 示意圖
  /// 空字串時退而使用純風格示意圖（preview_{style}.png）
  final String categoryId;

  /// Pro 客製風格描述（非 null 時 fallback 改顯示黃金佔位，不嘗試載入 asset）
  final String? customStyleDesc;

  /// Pro 客製情緒描述（非 null 時 fallback 改顯示黃金佔位）
  final String? customEmotionDesc;

  /// 背景填色（null = 透明）
  final Color? backgroundColor;

  /// true → 啟用選取模式（編輯 Sheet），false → 主卡片模式
  final bool enableTextGestures;

  /// false → 停用所有手勢（圖片/文字皆無法拖拉/縮放），用於選擇畫面純預覽
  final bool interactive;

  /// 外部顯式指定選取目標（由 StickerEditSheet 的模式按鈕控制）
  /// 設定後 canvas 不再透過 tap 自行切換 _EditTarget
  final StickerEditTarget? externalTarget;

  /// 主卡片模式點圖回呼（打開編輯 popup）
  final VoidCallback? onTap;

  /// 圖片 transform 變化回呼（scale, offset, angle）
  final void Function(double scale, Offset offset, double angle)?
      onTransformChanged;

  /// 文字 transform 變化回呼（xAlign, yAlign, angle, sizeScale）
  final void Function(
    double xAlign,
    double yAlign,
    double angle,
    double sizeScale,
  )? onTextGestureChanged;

  static const double aspectRatio = 1.0; // 正方形畫布

  const StickerCanvas({
    super.key,
    this.subjectBytes,
    this.generatedImage,
    this.stickerShape = StickerShape.circle,
    required this.text,
    required this.config,
    this.initialScale = 1.0,
    this.initialOffset = Offset.zero,
    this.initialImageAngle = 0.0,
    this.fontIndex = 0,
    this.fontSizeScale = 1.0,
    this.textXAlign = 0.0,
    this.textYAlign = 0.85,
    this.textAngle = 0.0,
    this.styleIndex = 0,
    this.categoryId = '',
    this.customStyleDesc,
    this.customEmotionDesc,
    this.backgroundColor,
    this.enableTextGestures = false,
    this.interactive = true,
    this.externalTarget,
    this.onTap,
    this.onTransformChanged,
    this.onTextGestureChanged,
  });

  @override
  State<StickerCanvas> createState() => _StickerCanvasState();
}

class _StickerCanvasState extends State<StickerCanvas> {
  // ── 圖片 transform ──────────────────────────────────────────────────────────
  late double _imgScale;
  late Offset _imgOffset;
  late double _imgAngle;
  double _imgStartScale = 1.0;
  Offset _imgStartFocal = Offset.zero;
  Offset _imgStartOffset = Offset.zero;
  double _imgStartAngle = 0.0;

  // ── 文字 transform ──────────────────────────────────────────────────────────
  late double _textXAlign;
  late double _textYAlign;
  late double _textAngle;
  late double _textSizeScale;
  double _txtStartXAlign = 0.0;
  double _txtStartYAlign = 0.0;
  double _txtStartAngle = 0.0;
  double _txtStartScale = 1.0;
  Offset _txtStartFocal = Offset.zero;
  bool _textGestureActive = false;

  // ── 選取狀態（externalTarget 為 null 時由 tap 自行維護）─────────────────
  StickerEditTarget _internalSelected = StickerEditTarget.none;

  /// 實際生效的選取目標：外部優先，否則用內部狀態
  StickerEditTarget get _effective =>
      widget.externalTarget ?? _internalSelected;

  // ── 手勢 tap 偵測（在 scale handler 內判斷）──────────────────────────────
  Offset _gestureStartFocal = Offset.zero;
  bool _wasTap = false;

  // 畫布實際尺寸（LayoutBuilder 填入）
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _imgScale = widget.initialScale;
    _imgOffset = widget.initialOffset;
    _imgAngle = widget.initialImageAngle;
    _textXAlign = widget.textXAlign;
    _textYAlign = widget.textYAlign;
    _textAngle = widget.textAngle;
    _textSizeScale = widget.fontSizeScale;
    // 編輯 popup 開啟時 generatedImage 一開始就非 null，
    // didUpdateWidget 的條件不會觸發，在此補上 auto-fit
    // length > 1：排除 sentinel(1) 與失敗狀態(0)，只處理真實圖片
    if (widget.generatedImage != null && widget.generatedImage!.length > 1) {
      _autoFitGeneratedImage(widget.generatedImage!);
    }
  }

  @override
  void didUpdateWidget(StickerCanvas old) {
    super.didUpdateWidget(old);

    // 圖片首次到達時重置視角
    // Gemini 產出的圓形貼圖圓圈約佔畫布 90–95%，以 1.12x 補足至填滿 ClipOval
    if (old.generatedImage == null && widget.generatedImage != null &&
        widget.generatedImage!.length > 1) {
      _imgOffset = Offset.zero;
      _imgScale = 1.12; // temporary default；isolate 計算完後會更新
      _imgAngle = 0.0;
      widget.onTransformChanged?.call(_imgScale, _imgOffset, _imgAngle);
      _autoFitGeneratedImage(widget.generatedImage!);
    }

    // 父層更新圖片 transform 時同步（popup 關閉後）
    if (old.initialScale != widget.initialScale ||
        old.initialOffset != widget.initialOffset ||
        old.initialImageAngle != widget.initialImageAngle) {
      setState(() {
        _imgScale = widget.initialScale;
        _imgOffset = widget.initialOffset;
        _imgAngle = widget.initialImageAngle;
      });
    }

    // 文字 transform：手勢進行中不覆寫本地狀態
    if (!_textGestureActive) {
      if (old.textXAlign != widget.textXAlign) {
        setState(() => _textXAlign = widget.textXAlign);
      }
      if (old.textYAlign != widget.textYAlign) {
        setState(() => _textYAlign = widget.textYAlign);
      }
      if (old.textAngle != widget.textAngle) {
        setState(() => _textAngle = widget.textAngle);
      }
      if (old.fontSizeScale != widget.fontSizeScale) {
        setState(() => _textSizeScale = widget.fontSizeScale);
      }
    }
  }

  // ── Auto-fit: 偵測彩色內容 bounding box，縮放並置中至填滿畫布 ────────────

  /// 在 isolate 中執行（透過 compute）。
  /// 回傳 [minX, minY, maxX, maxY, imageWidth, imageHeight]。
  ///
  /// 同時計算兩種 bounding box：
  ///   - Color bounds：排除透明 + 近黑色（R < 40 && G < 40 && B < 40），
  ///     用於大多數彩色風格，縮放更緊湊
  ///   - Alpha bounds：所有不透明像素，含黑色輪廓
  ///
  /// 當 alpha bounds 的垂直範圍比 color bounds 大超過 8%（即角色頂/底有
  /// 大量黑色輪廓，如 yuruDoodle ゆるい塗鴉 / showaManga 昭和漫畫），
  /// 改用 alpha bounds，避免頭頂等黑色區域被誤算而截圖。
  static List<int>? _findContentBounds(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final data = image.getBytes(order: img.ChannelOrder.rgba);
    final w = image.width;
    final h = image.height;

    // 同一個 pass 計算 color bounds 和 alpha bounds
    int cMinX = w, cMaxX = 0, cMinY = h, cMaxY = 0; // 彩色
    int aMinX = w, aMaxX = 0, aMinY = h, aMaxY = 0; // alpha（含黑色輪廓）

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        if (data[i + 3] <= 10) continue; // 透明

        // alpha bounds（所有不透明像素）
        if (x < aMinX) aMinX = x;
        if (x > aMaxX) aMaxX = x;
        if (y < aMinY) aMinY = y;
        if (y > aMaxY) aMaxY = y;

        // color bounds（排除近黑色輪廓線）
        final r = data[i], g = data[i + 1], b = data[i + 2];
        if (r < 40 && g < 40 && b < 40) continue;
        if (x < cMinX) cMinX = x;
        if (x > cMaxX) cMaxX = x;
        if (y < cMinY) cMinY = y;
        if (y > cMaxY) cMaxY = y;
      }
    }

    if (aMinX >= aMaxX || aMinY >= aMaxY) return null; // 完全透明

    // 彩色像素充足時：比較 color bounds 與 alpha bounds 的垂直差距
    // 差距 > 8%（如 yuruDoodle/showaManga 的厚黑輪廓風格），改用 alpha bounds，
    // 避免頭頂、腳底的黑色輪廓被誤算為空白而造成截圖
    final hasColorBounds = cMinX < cMaxX && cMinY < cMaxY;
    if (hasColorBounds) {
      final alphaH = aMaxY - aMinY;
      final topExcess = (cMinY - aMinY) / alphaH; // 頂部黑色輪廓佔比
      final botExcess = (aMaxY - cMaxY) / alphaH; // 底部黑色輪廓佔比
      if (topExcess < 0.08 && botExcess < 0.08) {
        return [cMinX, cMinY, cMaxX, cMaxY, w, h];
      }
    }
    // alpha bounds fallback：彩色像素全無，或黑色輪廓比例過高
    return [aMinX, aMinY, aMaxX, aMaxY, w, h];
  }

  void _autoFitGeneratedImage(Uint8List bytes) {
    // 若畫布尚未 layout（initState 首次呼叫時 _canvasSize == Size.zero），
    // 延至下一幀再執行，確保置中計算有正確的 _canvasSize。
    if (_canvasSize == Size.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoFitGeneratedImage(bytes);
      });
      return;
    }

    compute(_findContentBounds, bytes).then((bounds) {
      if (!mounted || bounds == null) return;

      final minX = bounds[0].toDouble();
      final minY = bounds[1].toDouble();
      final maxX = bounds[2].toDouble();
      final maxY = bounds[3].toDouble();
      final iW   = bounds[4].toDouble();
      final iH   = bounds[5].toDouble();

      // Scale：Cover 計算——兩個方向都必須填滿，取較大倍率（1.05× 推殘留薄邊出 ClipOval）
      // 注意：不可用 max÷max，否則當內容非正方形時短軸仍有空隙
      final scaleX = iW / (maxX - minX);
      final scaleY = iH / (maxY - minY);
      final newScale = (max(scaleX, scaleY) * 1.05).clamp(1.0, 3.0);

      // Offset：把彩色內容中心對齊畫布中心
      // Transform 順序：先 Translate（_imgOffset）再 Scale（_imgScale，從畫布中心縮放）
      // 公式：offset = (canvasCenter - naturalContentCenter) × newScale
      final cx = (minX + maxX) / 2.0;
      final cy = (minY + maxY) / 2.0;
      final naturalCx = cx * (_canvasSize.width  / iW);
      final naturalCy = cy * (_canvasSize.height / iH);
      final dx = (_canvasSize.width  / 2.0 - naturalCx) * newScale;
      final dy = (_canvasSize.height / 2.0 - naturalCy) * newScale;

      setState(() {
        _imgScale  = newScale;
        _imgOffset = Offset(dx, dy);
      });
      widget.onTransformChanged?.call(_imgScale, _imgOffset, _imgAngle);
    });
  }

  // ── 手勢處理（統一 Handler）────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _gestureStartFocal = d.localFocalPoint;
    _wasTap = true;

    if (!widget.enableTextGestures || _effective == StickerEditTarget.image) {
      // 主卡片圖片縮放 or 編輯模式圖片選取
      _imgStartScale = _imgScale;
      _imgStartFocal = d.localFocalPoint;
      _imgStartOffset = _imgOffset;
      _imgStartAngle = _imgAngle;
    } else if (_effective == StickerEditTarget.text) {
      _textGestureActive = true;
      _txtStartXAlign = _textXAlign;
      _txtStartYAlign = _textYAlign;
      _txtStartAngle = _textAngle;
      _txtStartScale = _textSizeScale;
      _txtStartFocal = d.localFocalPoint;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // 判斷是否為「真實手勢」（非 tap）
    if ((d.scale - 1.0).abs() > 0.04 ||
        d.rotation.abs() > 0.04 ||
        (d.localFocalPoint - _gestureStartFocal).distance > 8) {
      _wasTap = false;
    }

    if (!widget.enableTextGestures || _effective == StickerEditTarget.image) {
      // 圖片：縮放 + 位移（編輯模式下加旋轉）
      setState(() {
        _imgScale = (_imgStartScale * d.scale).clamp(0.5, 4.0);
        _imgOffset = _imgStartOffset + (d.localFocalPoint - _imgStartFocal);
        if (widget.enableTextGestures) {
          _imgAngle = _imgStartAngle + d.rotation;
        }
      });
      widget.onTransformChanged?.call(_imgScale, _imgOffset, _imgAngle);
    } else if (_effective == StickerEditTarget.text) {
      // 文字：移動 + 縮放 + 旋轉
      if (_canvasSize == Size.zero) return;
      final delta = d.localFocalPoint - _txtStartFocal;
      final halfW = _canvasSize.width / 2;
      final halfH = _canvasSize.height / 2;
      setState(() {
        _textXAlign = (_txtStartXAlign + delta.dx / halfW).clamp(-1.5, 1.5);
        _textYAlign = (_txtStartYAlign + delta.dy / halfH).clamp(-1.5, 1.5);
        _textAngle = _txtStartAngle + d.rotation;
        _textSizeScale = (_txtStartScale * d.scale).clamp(0.3, 3.0);
      });
      widget.onTextGestureChanged
          ?.call(_textXAlign, _textYAlign, _textAngle, _textSizeScale);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _textGestureActive = false;

    if (_wasTap) {
      if (widget.enableTextGestures &&
          _canvasSize != Size.zero &&
          widget.externalTarget == null) {
        // 僅在無外部控制時才允許 tap 自行切換選取目標
        _handleSelectionTap(_gestureStartFocal);
      } else if (!widget.enableTextGestures) {
        // 主卡片：呼叫 onTap 打開編輯 Sheet
        widget.onTap?.call();
      }
    }
  }

  /// 依點擊座標決定選取圖片或文字（僅 externalTarget == null 時呼叫）
  void _handleSelectionTap(Offset pos) {
    final cx = _canvasSize.width * (1 + _textXAlign) / 2;
    final cy = _canvasSize.height * (1 + _textYAlign) / 2;
    final dist = (pos - Offset(cx, cy)).distance;

    // 命中範圍：以字體大小倍率調整（最小 44px，最大畫布寬一半）
    final hitR =
        (_canvasSize.width * 0.28 * _textSizeScale).clamp(44.0, _canvasSize.width * 0.5);

    final next = dist < hitR ? StickerEditTarget.text : StickerEditTarget.image;
    if (next != _internalSelected) {
      HapticFeedback.selectionClick();
      setState(() => _internalSelected = next);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final child = AspectRatio(
      aspectRatio: StickerCanvas.aspectRatio,
      child: _hasAiImage
          ? _buildAiImage()
          : _hasFailed
              ? _buildFailedPlaceholder()
              : _buildFallback(),
    );

    // 編輯模式（enableTextGestures: true）：使用 _CanvasScaleGestureRecognizer
    // 強制贏得手勢競技場，防止 DraggableScrollableSheet 的 drag recognizer 搶走單指事件。
    // 主卡片模式（enableTextGestures: false）：使用一般 GestureDetector，
    // 保留 StickerSwipeCard 的水平滑動能正常觸發。
    if (widget.enableTextGestures && widget.interactive) {
      return RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _CanvasScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_CanvasScaleGestureRecognizer>(
            () => _CanvasScaleGestureRecognizer(debugOwner: this),
            (recognizer) {
              recognizer
                ..onStart = _onScaleStart
                ..onUpdate = _onScaleUpdate
                ..onEnd = _onScaleEnd;
            },
          ),
        },
        child: child,
      );
    }

    return GestureDetector(
      onScaleStart: widget.interactive ? _onScaleStart : null,
      onScaleUpdate: widget.interactive ? _onScaleUpdate : null,
      onScaleEnd: widget.interactive ? _onScaleEnd : null,
      child: child,
    );
  }

  bool get _hasAiImage =>
      widget.generatedImage != null && widget.generatedImage!.length > 1;

  bool get _hasFailed =>
      widget.generatedImage != null && widget.generatedImage!.isEmpty;

  Widget _buildAiImage() {
    final content = ClipRect(
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          _canvasSize = constraints.biggest;

          // ── 圖片層（縮放 + 位移 + 旋轉）────────────────────────────────
          final imageContent = Transform.translate(
            offset: _imgOffset,
            child: Transform.scale(
              scale: _imgScale,
              child: Transform.rotate(
                angle: _imgAngle,
                child: Image.memory(
                  widget.generatedImage!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          );

          // ── 文字層（位移 + 旋轉 + 選取框）──────────────────────────────
          final textLayer = Align(
            alignment: Alignment(_textXAlign, _textYAlign),
            child: Transform.rotate(
              angle: _textAngle,
              child: _TextSelectionWidget(
                text: widget.text,
                config: widget.config,
                fontIndex: widget.fontIndex,
                fontSizeScale: _textSizeScale,
                isSelected:
                    widget.enableTextGestures && _effective == StickerEditTarget.text,
              ),
            ),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── 背景填色層（透明時不渲染）──────────────────────────────────
              if (widget.backgroundColor != null)
                ColoredBox(color: widget.backgroundColor!),

              imageContent,

              // ── 人物層（ML Kit 去背，疊在 AI 背景上，同步 transform）──
              if (widget.subjectBytes != null)
                Transform.translate(
                  offset: _imgOffset,
                  child: Transform.scale(
                    scale: _imgScale,
                    child: Transform.rotate(
                      angle: _imgAngle,
                      child: Image.memory(
                        widget.subjectBytes!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),

              // 圖片選取框（編輯模式下圖片被選中時）
              if (widget.enableTextGestures && _effective == StickerEditTarget.image)
                _ImageSelectionOverlay(
                  canvasSize: _canvasSize,
                  stickerShape: widget.stickerShape,
                ),

              textLayer,

              // 提示文字（無外部控制且尚未選取任何物件時顯示）
              if (widget.enableTextGestures &&
                  widget.externalTarget == null &&
                  _internalSelected == StickerEditTarget.none)
                const _SelectionHint(),
            ],
          );
        },
      ),
    );
    // 圓形模式：預覽時加 ClipOval（不影響 RepaintBoundary 擷取）
    if (widget.stickerShape == StickerShape.circle) {
      return ClipOval(child: content);
    }
    return content;
  }

  Widget _buildFailedPlaceholder() {
    final color = widget.config.colorScheme.borderColor;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildFallback() {
    // 客製情緒：無對應 preview asset，改用黃金佔位圖
    if (widget.customEmotionDesc != null) {
      return _buildCustomPlaceholder();
    }

    final style = StickerStyle.values[
        widget.styleIndex.clamp(0, StickerStyle.values.length - 1)];
    // 依 style × emotion 組合選擇示意圖；categoryId 為空時退回 greeting
    final emotionId = widget.categoryId.isNotEmpty ? widget.categoryId : 'greeting';
    final asset = 'assets/images/preview_${style.name}_$emotionId.webp';

    // 預覽圖標籤：自訂風格時仍顯示「示意圖」，避免誤導使用者以為已在生成
    const badgeLabel = '示意圖';
    final badgeBg = Colors.black.withValues(alpha: 0.45);
    final badgeFg = Colors.white.withValues(alpha: 0.9);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // 縮圖尚未產生時（如新風格），顯示品牌色底 + 風格 emoji
              errorBuilder: (_, __, ___) =>
                  _StyleEmojiPlaceholder(style: style, size: size),
            ),
            // 文字示意（AI 已生成文案時顯示，與最終成品相同位置）
            if (widget.text.isNotEmpty)
              Align(
                alignment: Alignment(_textXAlign, _textYAlign),
                child: Transform.rotate(
                  angle: _textAngle,
                  child: _TextSelectionWidget(
                    text: widget.text,
                    config: widget.config,
                    fontIndex: widget.fontIndex,
                    fontSizeScale: _textSizeScale,
                    isSelected: false,
                  ),
                ),
              ),
            // 標籤：「示意圖」或「客製中」
            Positioned(
              top: size * 0.04,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      color: badgeFg,
                      fontSize: size * 0.07,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 客製模式佔位圖：黃金漸層 + 描述文字
  Widget _buildCustomPlaceholder() {
    final style = StickerStyle.values[
        widget.styleIndex.clamp(0, StickerStyle.values.length - 1)];
    final styleLabel = widget.customStyleDesc ?? style.label;
    final styleEmoji = widget.customStyleDesc != null ? '✏️' : style.emoji;
    final emotionText = widget.customEmotionDesc ?? widget.customStyleDesc!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFFBE7), Color(0xFFFFF3CD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 文字示意（AI 已生成文案時顯示）
              if (widget.text.isNotEmpty)
                Align(
                  alignment: Alignment(_textXAlign, _textYAlign),
                  child: Transform.rotate(
                    angle: _textAngle,
                    child: _TextSelectionWidget(
                      text: widget.text,
                      config: widget.config,
                      fontIndex: widget.fontIndex,
                      fontSizeScale: _textSizeScale,
                      isSelected: false,
                    ),
                  ),
                ),
              // 尚未生成文案時：中央描述（情緒 + 提示）
              if (widget.text.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        size * 0.08, size * 0.16, size * 0.08, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('✨', style: TextStyle(fontSize: 44)),
                        const SizedBox(height: 10),
                        Text(
                          emotionText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: size * 0.09,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF8B6914),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'AI 生成後將顯示於此',
                          style: TextStyle(
                            fontSize: size * 0.055,
                            color: const Color(0xFFB8860B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // 風格資訊 chip（取代「客製中」，不暗示生成中）
              Positioned(
                top: size * 0.04,
                left: size * 0.06,
                right: size * 0.06,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: size * 0.04, vertical: size * 0.014),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFB8860B).withValues(alpha: 0.45),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(styleEmoji,
                            style: TextStyle(fontSize: size * 0.05)),
                        SizedBox(width: size * 0.018),
                        Flexible(
                          child: Text(
                            styleLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: size * 0.058,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF8B6914),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── 風格 Emoji 佔位圖（縮圖尚未產生時使用）──────────────────────────────────────

class _StyleEmojiPlaceholder extends StatelessWidget {
  final StickerStyle style;
  final double size;

  const _StyleEmojiPlaceholder({required this.style, required this.size});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFFF0F3), // 品牌淡玫瑰底，與 loading 畫面一致
      child: Center(
        child: Text(
          style.emoji,
          style: TextStyle(fontSize: size * 0.35),
        ),
      ),
    );
  }
}

// ─── 文字 + 選取框 ─────────────────────────────────────────────────────────────

class _TextSelectionWidget extends StatelessWidget {
  final String text;
  final StickerConfig config;
  final int fontIndex;
  final double fontSizeScale;
  final bool isSelected;

  const _TextSelectionWidget({
    required this.text,
    required this.config,
    required this.fontIndex,
    required this.fontSizeScale,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    const double handleR = 8.0;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: isSelected
          ? BoxDecoration(
              border: Border.all(color: _kHandleColor, width: 2),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: _OutlinedStickerText(
        text: text,
        config: config,
        fontIndex: fontIndex,
        fontSizeScale: fontSizeScale,
      ),
    );

    if (!isSelected) return content;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        content,

        // 旋轉控制點（文字上方：24px 圓圈 + 20px 連接線，4px 間距）
        Positioned(
          top: -(24 + 20 + 4).toDouble(), // 頂部留出 handle 高度 + 4px 間距
          child: const _RotationHandle(),
        ),

        // 四角縮放控制點
        const Positioned(top: -handleR, left: -handleR, child: _CircleHandle()),
        const Positioned(top: -handleR, right: -handleR, child: _CircleHandle()),
        const Positioned(bottom: -handleR, left: -handleR, child: _CircleHandle()),
        const Positioned(bottom: -handleR, right: -handleR, child: _CircleHandle()),
      ],
    );
  }
}

class _RotationHandle extends StatelessWidget {
  const _RotationHandle();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kHandleColor,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(
            Icons.rotate_right_rounded,
            size: 14,
            color: Colors.white,
          ),
        ),
        Container(
          width: 2,
          height: 20,
          color: _kHandleColor.withValues(alpha: 0.75),
        ),
      ],
    );
  }
}

class _CircleHandle extends StatelessWidget {
  const _CircleHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kHandleColor,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
    );
  }
}

// ─── 圖片選取框（全畫布角落控制點）──────────────────────────────────────────

class _ImageSelectionOverlay extends StatelessWidget {
  final Size canvasSize;
  final StickerShape stickerShape;

  const _ImageSelectionOverlay({
    required this.canvasSize,
    required this.stickerShape,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 邊框 + 角落控制點（CustomPainter）
          CustomPaint(painter: _ImageSelectionPainter(stickerShape: stickerShape)),

          // 中心旋轉提示圓圈
          Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.88),
                border: Border.all(color: _kHandleColor, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6)
                ],
              ),
              child: const Icon(
                Icons.open_with_rounded,
                size: 22,
                color: _kHandleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageSelectionPainter extends CustomPainter {
  final StickerShape stickerShape;
  const _ImageSelectionPainter({required this.stickerShape});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = _kHandleColor.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = _kHandleColor
      ..style = PaintingStyle.fill;
    final whitePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (stickerShape == StickerShape.circle) {
      // ── 圓形邊框 ──────────────────────────────────────────────────
      final center = Offset(size.width / 2, size.height / 2);
      final radius = (size.width / 2) - 4;
      canvas.drawCircle(center, radius, borderPaint);

      // 控制點在 45° / 135° / 225° / 315° 的圓圈邊緣
      for (final a in [pi * 0.25, pi * 0.75, pi * 1.25, pi * 1.75]) {
        final pt = center + Offset(cos(a) * radius, sin(a) * radius);
        canvas.drawCircle(pt, 8, fillPaint);
        canvas.drawCircle(pt, 8, whitePaint);
      }
    } else {
      // ── 方形邊框（原邏輯）──────────────────────────────────────────
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(4, 4, size.width - 4, size.height - 4),
          const Radius.circular(4),
        ),
        borderPaint,
      );

      for (final pt in [
        const Offset(4, 4),
        Offset(size.width - 4, 4),
        Offset(4, size.height - 4),
        Offset(size.width - 4, size.height - 4),
      ]) {
        canvas.drawCircle(pt, 8, fillPaint);
        canvas.drawCircle(pt, 8, whitePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ImageSelectionPainter old) =>
      old.stickerShape != stickerShape;
}

// ─── 操作提示（尚未選取任何物件時）─────────────────────────────────────────

class _SelectionHint extends StatelessWidget {
  const _SelectionHint();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, 0.92),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_rounded, size: 13, color: Colors.white),
            SizedBox(width: 5),
            Text(
              '點選圖片或文字來編輯',
              style: TextStyle(fontSize: 11, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── LINE 貼圖風格：粗 outline 文字 ──────────────────────────────────────────

class _OutlinedStickerText extends StatelessWidget {
  final String text;
  final StickerConfig config;
  final int fontIndex;
  final double fontSizeScale;

  const _OutlinedStickerText({
    required this.text,
    required this.config,
    this.fontIndex = 0,
    this.fontSizeScale = 1.0,
  });

  static const _kBaseFontSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final fontSize = _kBaseFontSize * fontSizeScale;
    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1.15,
    );
    final font = kStickerFonts[fontIndex.clamp(0, kStickerFonts.length - 1)];
    final styledBase = font.apply(baseStyle);

    final outlineText = Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: styledBase.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (fontSize * 0.14).clamp(3.0, 7.0)
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      ),
    );
    final fillText = Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: styledBase.copyWith(color: config.colorScheme.textFill),
    );

    return Stack(
      alignment: Alignment.center,
      textDirection: TextDirection.ltr,
      children: [outlineText, fillText],
    );
  }
}


