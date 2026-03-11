import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─── Macaron pastel palette ────────────────────────────────────────────────

class MacaronColors {
  static const babyPink   = Color(0xFFFFB7C5);
  static const lavender   = Color(0xFFC9B1E0);
  static const mint       = Color(0xFFB5EAD7);
  static const peach      = Color(0xFFFFDAC1);
  static const skyBlue    = Color(0xFFAED6F1);
  static const butter     = Color(0xFFFFF3AE);
  static const rose       = Color(0xFFFFD1DC);
  static const lilac      = Color(0xFFE6CCFF);
  static const aqua       = Color(0xFFB5F0F0);
  static const coral      = Color(0xFFFFB3A7);
  static const sage       = Color(0xFFD4EAC8);
  static const periwinkle = Color(0xFFBFCFFF);

  static const all = [
    babyPink, lavender, mint, peach, skyBlue, butter,
    rose, lilac, aqua, coral, sage, periwinkle,
  ];
}

// ─── Frame style enum ─────────────────────────────────────────────────────

enum FrameShape {
  // ── 花形系列 ──────────────────
  flower5,      // 5 瓣花（像照片）
  flower6,      // 6 瓣花
  flower8,      // 8 瓣圓花
  clover4,      // 四葉草
  sunflower,    // 向日葵 (尖瓣)
  // ── 雲朵 / 泡泡 ───────────────
  cloud,        // 雲朵
  cloudRound,   // 圓潤雲朵
  bubble,       // 思考泡泡
  // ── 幾何 ──────────────────────
  heart,        // 愛心
  star5,        // 五角星
  star6,        // 六角星
  star8,        // 八角放射
  diamond,      // 菱形
  hexagon,      // 六邊形
  octagon,      // 八邊形
  shield,       // 盾形
  // ── 有機形 ────────────────────
  scallop,      // 扇形/荷葉邊圓
  squircle,     // 超橢圓
  petal,        // 花瓣橢圓
  arch,         // 拱形
  // ── 動物耳 ────────────────────
  bearEars,     // 熊耳圓
  bunnyEars,    // 兔耳圓
  catEars,      // 貓耳圓
  // ── 裝飾框 ────────────────────
  polaroid,     // 拍立得白框
  filmStrip,    // 底片格
  ribbon,       // 緞帶蝴蝶結框
  crown,        // 皇冠頂邊框
  stamp,        // 郵票鋸齒
  // ── 對話泡泡形 ─────────────────
  speechLeft,   // 左側對話尾
  speechRight,  // 右側對話尾
}

// ─── FrameStyle definition ────────────────────────────────────────────────

class FrameStyle {
  final FrameShape shape;
  final String label;        // UI 顯示名稱
  final Color color;         // 馬卡龍主色
  final double strokeWidth;  // 邊框粗細
  final bool filled;         // 實心填色 or 僅外框

  const FrameStyle({
    required this.shape,
    required this.label,
    required this.color,
    this.strokeWidth = 8,
    this.filled = false,
  });
}

// ─── 30 preset frames ─────────────────────────────────────────────────────

const kFrameStyles = <FrameStyle>[
  FrameStyle(shape: FrameShape.flower5,    label: '花朵',   color: MacaronColors.babyPink),
  FrameStyle(shape: FrameShape.flower6,    label: '六花',   color: MacaronColors.lavender),
  FrameStyle(shape: FrameShape.flower8,    label: '菊花',   color: MacaronColors.rose),
  FrameStyle(shape: FrameShape.clover4,    label: '四葉草', color: MacaronColors.mint),
  FrameStyle(shape: FrameShape.sunflower,  label: '向日葵', color: MacaronColors.butter),
  FrameStyle(shape: FrameShape.cloud,      label: '雲朵',   color: MacaronColors.skyBlue),
  FrameStyle(shape: FrameShape.cloudRound, label: '圓雲',   color: MacaronColors.periwinkle),
  FrameStyle(shape: FrameShape.bubble,     label: '泡泡',   color: MacaronColors.aqua),
  FrameStyle(shape: FrameShape.heart,      label: '愛心',   color: MacaronColors.rose,     strokeWidth: 9),
  FrameStyle(shape: FrameShape.star5,      label: '五星',   color: MacaronColors.butter,   strokeWidth: 7),
  FrameStyle(shape: FrameShape.star6,      label: '六星',   color: MacaronColors.lavender, strokeWidth: 7),
  FrameStyle(shape: FrameShape.star8,      label: '放射',   color: MacaronColors.peach,    strokeWidth: 6),
  FrameStyle(shape: FrameShape.diamond,    label: '菱形',   color: MacaronColors.lilac),
  FrameStyle(shape: FrameShape.hexagon,    label: '六角',   color: MacaronColors.mint),
  FrameStyle(shape: FrameShape.octagon,    label: '八角',   color: MacaronColors.skyBlue),
  FrameStyle(shape: FrameShape.shield,     label: '盾形',   color: MacaronColors.periwinkle),
  FrameStyle(shape: FrameShape.scallop,    label: '荷葉邊', color: MacaronColors.babyPink, strokeWidth: 6),
  FrameStyle(shape: FrameShape.squircle,   label: '超橢圓', color: MacaronColors.coral),
  FrameStyle(shape: FrameShape.petal,      label: '花瓣',   color: MacaronColors.lavender),
  FrameStyle(shape: FrameShape.arch,       label: '拱形',   color: MacaronColors.sage),
  FrameStyle(shape: FrameShape.bearEars,   label: '熊熊',   color: MacaronColors.peach,    strokeWidth: 7),
  FrameStyle(shape: FrameShape.bunnyEars,  label: '兔兔',   color: MacaronColors.babyPink, strokeWidth: 7),
  FrameStyle(shape: FrameShape.catEars,    label: '貓咪',   color: MacaronColors.lavender, strokeWidth: 7),
  FrameStyle(shape: FrameShape.polaroid,   label: '拍立得', color: Colors.white,           strokeWidth: 12, filled: true),
  FrameStyle(shape: FrameShape.filmStrip,  label: '底片',   color: Color(0xFFFFF0F5),      strokeWidth: 10, filled: true),
  FrameStyle(shape: FrameShape.ribbon,     label: '緞帶',   color: MacaronColors.rose),
  FrameStyle(shape: FrameShape.crown,      label: '皇冠',   color: MacaronColors.butter,   strokeWidth: 7),
  FrameStyle(shape: FrameShape.stamp,      label: '郵票',   color: MacaronColors.mint,     strokeWidth: 5),
  FrameStyle(shape: FrameShape.speechLeft, label: '對話↙',  color: MacaronColors.skyBlue),
  FrameStyle(shape: FrameShape.speechRight,label: '對話↘',  color: MacaronColors.coral),
];

// ─── Path builder ─────────────────────────────────────────────────────────

/// 依 [FrameShape] 產生對應的 Path（以 [bounds] 為邊界框）
Path buildFramePath(FrameShape shape, Rect bounds) {
  switch (shape) {
    case FrameShape.flower5:    return _flower(bounds, petals: 5, petalRatio: 0.38);
    case FrameShape.flower6:    return _flower(bounds, petals: 6, petalRatio: 0.34);
    case FrameShape.flower8:    return _flower(bounds, petals: 8, petalRatio: 0.28);
    case FrameShape.clover4:    return _flower(bounds, petals: 4, petalRatio: 0.44);
    case FrameShape.sunflower:  return _star(bounds, points: 16, innerRatio: 0.72);
    case FrameShape.cloud:      return _cloud(bounds, bumps: 7);
    case FrameShape.cloudRound: return _cloud(bounds, bumps: 5, bumpScale: 0.28);
    case FrameShape.bubble:     return _thoughtBubble(bounds);
    case FrameShape.heart:      return _heart(bounds);
    case FrameShape.star5:      return _star(bounds, points: 5, innerRatio: 0.42);
    case FrameShape.star6:      return _star(bounds, points: 6, innerRatio: 0.55);
    case FrameShape.star8:      return _star(bounds, points: 8, innerRatio: 0.60);
    case FrameShape.diamond:    return _diamond(bounds);
    case FrameShape.hexagon:    return _polygon(bounds, sides: 6);
    case FrameShape.octagon:    return _polygon(bounds, sides: 8);
    case FrameShape.shield:     return _shield(bounds);
    case FrameShape.scallop:    return _scallop(bounds, bumps: 14);
    case FrameShape.squircle:   return _squircle(bounds);
    case FrameShape.petal:      return _petal(bounds);
    case FrameShape.arch:       return _arch(bounds);
    case FrameShape.bearEars:   return _animalEars(bounds, earShape: _EarShape.bear);
    case FrameShape.bunnyEars:  return _animalEars(bounds, earShape: _EarShape.bunny);
    case FrameShape.catEars:    return _animalEars(bounds, earShape: _EarShape.cat);
    case FrameShape.polaroid:   return _polaroid(bounds);
    case FrameShape.filmStrip:  return _filmStrip(bounds);
    case FrameShape.ribbon:     return _ribbonFrame(bounds);
    case FrameShape.crown:      return _crownFrame(bounds);
    case FrameShape.stamp:      return _stamp(bounds);
    case FrameShape.speechLeft: return _speechBubble(bounds, tailRight: false);
    case FrameShape.speechRight:return _speechBubble(bounds, tailRight: true);
  }
}

// ─── Shape math helpers ───────────────────────────────────────────────────

Offset _center(Rect r) => r.center;
double _rx(Rect r) => r.width / 2;
double _ry(Rect r) => r.height / 2;

// Flower / clover: overlapping circles arranged in a ring
Path _flower(Rect bounds, {required int petals, required double petalRatio}) {
  final cx = _center(bounds).dx;
  final cy = _center(bounds).dy;
  final r = math.min(_rx(bounds), _ry(bounds));
  final petalR = r * petalRatio * 2;
  final dist   = r * (1 - petalRatio * 0.8);
  final path   = Path();
  for (int i = 0; i < petals; i++) {
    final angle = (2 * math.pi * i / petals) - math.pi / 2;
    final px = cx + dist * math.cos(angle);
    final py = cy + dist * math.sin(angle);
    path.addOval(Rect.fromCircle(center: Offset(px, py), radius: petalR));
  }
  // Center circle to fill gap
  path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.55));
  return path;
}

// Star / sunflower / burst
Path _star(Rect bounds, {required int points, required double innerRatio}) {
  final cx = _center(bounds).dx;
  final cy = _center(bounds).dy;
  final outerR = math.min(_rx(bounds), _ry(bounds));
  final innerR = outerR * innerRatio;
  final path = Path();
  for (int i = 0; i < points * 2; i++) {
    final angle = (math.pi * i / points) - math.pi / 2;
    final r = i.isEven ? outerR : innerR;
    final x = cx + r * math.cos(angle);
    final y = cy + r * math.sin(angle);
    if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
  }
  path.close();
  return path;
}

// Cloud: overlapping circles across the top
Path _cloud(Rect bounds, {int bumps = 7, double bumpScale = 0.22}) {
  final path = Path();
  final cy = _center(bounds).dy;
  final w  = bounds.width;
  final h  = bounds.height;
  final bumpR = w * bumpScale;

  // Top bumps
  for (int i = 0; i < bumps; i++) {
    final x = bounds.left + w * (i + 0.5) / bumps;
    final y = cy - h * 0.18;
    path.addOval(Rect.fromCircle(center: Offset(x, y), radius: bumpR));
  }
  // Main body rectangle-ish
  path.addRRect(RRect.fromRectAndRadius(
    Rect.fromLTWH(bounds.left + 4, cy - h * 0.05, w - 8, h * 0.55),
    const Radius.circular(24),
  ));
  return path;
}

// Thought bubble
Path _thoughtBubble(Rect bounds) {
  final path = _cloud(bounds, bumps: 6, bumpScale: 0.20);
  // Small circles trailing down-left
  final cx = bounds.left + bounds.width * 0.3;
  final by = bounds.bottom;
  path.addOval(Rect.fromCircle(center: Offset(cx, by - 12), radius: 9));
  path.addOval(Rect.fromCircle(center: Offset(cx - 14, by - 3), radius: 6));
  path.addOval(Rect.fromCircle(center: Offset(cx - 24, by + 4), radius: 4));
  return path;
}

// Heart
Path _heart(Rect bounds) {
  final w = bounds.width;
  final h = bounds.height;
  final l = bounds.left;
  final t = bounds.top;
  final path = Path();
  path.moveTo(l + w / 2, t + h * 0.25);
  // Left lobe
  path.cubicTo(
    l + w * 0.05, t + h * 0.05,
    l,            t + h * 0.55,
    l + w / 2,    t + h * 0.88,
  );
  // Right lobe
  path.cubicTo(
    l + w,        t + h * 0.55,
    l + w * 0.95, t + h * 0.05,
    l + w / 2,    t + h * 0.25,
  );
  path.close();
  return path;
}

// Diamond
Path _diamond(Rect bounds) {
  final cx = _center(bounds).dx;
  final cy = _center(bounds).dy;
  return Path()
    ..moveTo(cx, bounds.top)
    ..lineTo(bounds.right, cy)
    ..lineTo(cx, bounds.bottom)
    ..lineTo(bounds.left, cy)
    ..close();
}

// Regular polygon
Path _polygon(Rect bounds, {required int sides}) {
  final cx = _center(bounds).dx;
  final cy = _center(bounds).dy;
  final r  = math.min(_rx(bounds), _ry(bounds));
  final path = Path();
  for (int i = 0; i < sides; i++) {
    final angle = (2 * math.pi * i / sides) - math.pi / 2;
    final x = cx + r * math.cos(angle);
    final y = cy + r * math.sin(angle);
    if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
  }
  path.close();
  return path;
}

// Shield
Path _shield(Rect bounds) {
  final w = bounds.width;
  final h = bounds.height;
  final l = bounds.left;
  final t = bounds.top;
  final path = Path();
  final r = w * 0.15;
  path.moveTo(l + r, t);
  path.lineTo(l + w - r, t);
  path.quadraticBezierTo(l + w, t, l + w, t + r);
  path.lineTo(l + w, t + h * 0.55);
  path.quadraticBezierTo(l + w / 2, t + h * 1.05, l, t + h * 0.55);
  path.lineTo(l, t + r);
  path.quadraticBezierTo(l, t, l + r, t);
  path.close();
  return path;
}

// Scalloped circle (bumps around perimeter)
Path _scallop(Rect bounds, {int bumps = 14}) {
  final cx = _center(bounds).dx;
  final cy = _center(bounds).dy;
  final rOuter = math.min(_rx(bounds), _ry(bounds));
  final rInner = rOuter * 0.88;
  final bumpR  = (2 * math.pi * rOuter / bumps) * 0.55;
  final path   = Path();
  for (int i = 0; i < bumps; i++) {
    final angle = 2 * math.pi * i / bumps - math.pi / 2;
    final bx = cx + rInner * math.cos(angle);
    final by = cy + rInner * math.sin(angle);
    path.addOval(Rect.fromCircle(center: Offset(bx, by), radius: bumpR));
  }
  path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: rInner));
  return path;
}

// Squircle (superellipse exponent ~4)
Path _squircle(Rect bounds) {
  final cx = _center(bounds).dx;
  final cy = _center(bounds).dy;
  final rx = _rx(bounds) * 0.92;
  final ry = _ry(bounds) * 0.92;
  const n = 4.0;
  final path = Path();
  const steps = 120;
  for (int i = 0; i <= steps; i++) {
    final t = 2 * math.pi * i / steps;
    final cosT = math.cos(t);
    final sinT = math.sin(t);
    final cosSign = cosT < 0 ? -1.0 : 1.0;
    final sinSign = sinT < 0 ? -1.0 : 1.0;
    final x = cx + rx * math.pow(cosT.abs(), 2 / n).toDouble() * cosSign;
    final y = cy + ry * math.pow(sinT.abs(), 2 / n).toDouble() * sinSign;
    if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
  }
  path.close();
  return path;
}

// Petal ellipse (rotated ovals forming petal shape)
Path _petal(Rect bounds) {
  final cx = _center(bounds).dx;
  final cy = _center(bounds).dy;
  final rx = _rx(bounds) * 0.82;
  final ry = _ry(bounds) * 0.90;
  final path = Path();
  // Outer oval
  path.addOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2));
  return path;
}

// Arch (rounded top + straight bottom)
Path _arch(Rect bounds) {
  final w = bounds.width;
  final h = bounds.height;
  final l = bounds.left;
  final t = bounds.top;
  final path = Path();
  path.addArc(
    Rect.fromLTWH(l, t, w, h * 1.1),
    math.pi, math.pi,
  );
  path.lineTo(l + w, t + h * 0.7);
  path.lineTo(l, t + h * 0.7);
  path.close();
  return path;
}

// Animal ears
enum _EarShape { bear, bunny, cat }

Path _animalEars(Rect bounds, {required _EarShape earShape}) {
  final path = Path();
  final cx = _center(bounds).dx;
  final w  = bounds.width;
  final t  = bounds.top;
  final body = Rect.fromLTRB(bounds.left + 6, bounds.top + w * 0.18, bounds.right - 6, bounds.bottom);
  path.addOval(body);

  if (earShape == _EarShape.bear) {
    path.addOval(Rect.fromCircle(center: Offset(cx - w * 0.32, t + w * 0.13), radius: w * 0.17));
    path.addOval(Rect.fromCircle(center: Offset(cx + w * 0.32, t + w * 0.13), radius: w * 0.17));
  } else if (earShape == _EarShape.bunny) {
    path.addOval(Rect.fromCenter(center: Offset(cx - w * 0.22, t - w * 0.10), width: w * 0.16, height: w * 0.45));
    path.addOval(Rect.fromCenter(center: Offset(cx + w * 0.22, t - w * 0.10), width: w * 0.16, height: w * 0.45));
  } else {
    // cat ears — two triangles
    path.moveTo(cx - w * 0.38, t + w * 0.14);
    path.lineTo(cx - w * 0.26, t - w * 0.05);
    path.lineTo(cx - w * 0.14, t + w * 0.14);
    path.close();
    path.moveTo(cx + w * 0.14, t + w * 0.14);
    path.lineTo(cx + w * 0.26, t - w * 0.05);
    path.lineTo(cx + w * 0.38, t + w * 0.14);
    path.close();
  }
  return path;
}

// Polaroid: thick white frame, bottom slightly thicker
Path _polaroid(Rect bounds) {
  final inset = bounds.deflate(10);
  return Path()..addRRect(RRect.fromRectAndRadius(inset, const Radius.circular(4)));
}

// Film strip holes at left & right edges
Path _filmStrip(Rect bounds) {
  final path = Path();
  path.addRRect(RRect.fromRectAndRadius(bounds.deflate(8), const Radius.circular(6)));
  // Punch holes
  const holeH = 10.0;
  const holeW = 6.0;
  const count = 6;
  for (int i = 0; i < count; i++) {
    final y = bounds.top + bounds.height * (i + 0.5) / count;
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(bounds.left + 14, y), width: holeW, height: holeH),
      const Radius.circular(2),
    ));
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(bounds.right - 14, y), width: holeW, height: holeH),
      const Radius.circular(2),
    ));
  }
  return path;
}

// Ribbon frame (decorative bows at top corners — simple approximation)
Path _ribbonFrame(Rect bounds) {
  final path = Path();
  path.addRRect(RRect.fromRectAndRadius(bounds.deflate(8), const Radius.circular(20)));
  // Bow at top center
  final cx = _center(bounds).dx;
  final ty = bounds.top + 4;
  // Left wing
  path.moveTo(cx, ty + 8);
  path.cubicTo(cx - 30, ty - 10, cx - 50, ty + 5, cx - 20, ty + 16);
  path.close();
  // Right wing
  path.moveTo(cx, ty + 8);
  path.cubicTo(cx + 30, ty - 10, cx + 50, ty + 5, cx + 20, ty + 16);
  path.close();
  return path;
}

// Crown frame (spiky top)
Path _crownFrame(Rect bounds) {
  final path = Path();
  final w = bounds.width;
  final l = bounds.left;
  final t = bounds.top;
  final crownH = bounds.height * 0.22;

  // Crown teeth
  path.moveTo(l, t + crownH);
  path.lineTo(l, t + crownH);
  path.lineTo(l + w * 0.15, t);
  path.lineTo(l + w * 0.3,  t + crownH * 0.55);
  path.lineTo(l + w * 0.5,  t);
  path.lineTo(l + w * 0.7,  t + crownH * 0.55);
  path.lineTo(l + w * 0.85, t);
  path.lineTo(l + w,         t + crownH);

  // Rest of frame
  path.lineTo(l + w, bounds.bottom);
  path.lineTo(l, bounds.bottom);
  path.close();
  return path;
}

// Stamp: outer rect + inner rect with scalloped border
Path _stamp(Rect bounds) {
  final path = Path();
  const perf = 8.0; // perforation radius
  const gap  = 6.0;
  // Outer
  path.addRect(bounds);
  // Inner content area
  final inner = bounds.deflate(perf + gap);
  path.addRRect(RRect.fromRectAndRadius(inner, const Radius.circular(2)));
  // Perforation holes along each edge
  void addPerfs(Offset start, Offset step, int count) {
    for (int i = 0; i < count; i++) {
      final c = start + step * i.toDouble();
      path.addOval(Rect.fromCircle(center: c, radius: perf / 2));
    }
  }
  final cols = (bounds.width / (perf * 2.2)).floor();
  final rows = (bounds.height / (perf * 2.2)).floor();
  addPerfs(Offset(bounds.left + perf, bounds.top + perf / 2),
    Offset(bounds.width / cols, 0), cols);
  addPerfs(Offset(bounds.left + perf, bounds.bottom - perf / 2),
    Offset(bounds.width / cols, 0), cols);
  addPerfs(Offset(bounds.left + perf / 2, bounds.top + perf),
    Offset(0, bounds.height / rows), rows);
  addPerfs(Offset(bounds.right - perf / 2, bounds.top + perf),
    Offset(0, bounds.height / rows), rows);
  return path;
}

// Speech bubble with rounded rect body + tail
Path _speechBubble(Rect bounds, {required bool tailRight}) {
  final bodyB = bounds.bottom - bounds.height * 0.18;
  final body  = Rect.fromLTRB(bounds.left, bounds.top, bounds.right, bodyB);
  final path  = Path();
  path.addRRect(RRect.fromRectAndRadius(body, const Radius.circular(24)));
  // Tail
  final cx = tailRight ? bounds.right - bounds.width * 0.25 : bounds.left + bounds.width * 0.25;
  path.moveTo(cx - 14, bodyB);
  path.lineTo(tailRight ? cx + 10 : cx - 10, bounds.bottom);
  path.lineTo(cx + 14, bodyB);
  path.close();
  return path;
}
