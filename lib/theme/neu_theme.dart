import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'neu.dart';

/// 用 token 表生成 Flutter 的 ThemeData。
///
/// 这里只做「把材质系统交给 Flutter」这件事：颜色、文字层级、组件默认样式。
/// 画布背景不走 `scaffoldBackgroundColor` —— 它需要渐变 + 光源层，
/// 由 [NeuCanvas] 负责，Scaffold 保持透明即可。
ThemeData buildNeuTheme(NeuTokens t, {required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final base = isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);

  // 文字层级全部映射到 token：设计稿里标题用 ui-rounded、正文用系统字、
  // 数据用等宽字。Android 没有 ui-rounded，标题靠 700 字重维持「更实」的层级差。
  final text = base.textTheme.apply(bodyColor: t.fg, displayColor: t.onBg);

  return base.copyWith(
    // 画布由 NeuCanvas 绘制（渐变 + 光源），Scaffold 必须透明
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: t.bg,
    splashFactory: NoSplash.splashFactory, // 新拟态没有水波纹，按压语义是「凹进去」
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    extensions: [NeuTheme(t)],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accentInk,
      onSecondary: t.onAccent,
      error: t.danger,
      onError: t.onDanger,
      surface: t.surface,
      onSurface: t.fg,
    ),
    textTheme: text.copyWith(
      // .page-title 27 / 700
      headlineMedium: text.headlineMedium?.copyWith(
        fontSize: NeuFonts.pageTitle,
        fontWeight: FontWeight.w700,
        color: t.onBg,
      ),
      // .cfg-title / .ct-title 17 / 700
      titleMedium: text.titleMedium?.copyWith(
        fontSize: NeuFonts.sectionTitle,
        fontWeight: FontWeight.w700,
        color: t.fg,
      ),
      // 正文 14.5
      bodyMedium: text.bodyMedium?.copyWith(
        fontSize: NeuFonts.body,
        color: t.fg,
      ),
      // .ct-sub / 次要说明 12.5
      bodySmall: text.bodySmall?.copyWith(
        fontSize: NeuFonts.sub,
        color: t.muted,
      ),
      // .hist-title / .set-label 11.5 / 700
      labelSmall: text.labelSmall?.copyWith(
        fontSize: NeuFonts.label,
        fontWeight: FontWeight.w700,
        color: t.onBgDim,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: t.fg,
    ),
    dividerColor: t.border,
    // 输入相关：设计稿里输入框一律是凹槽，不带边框
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      hintStyle: TextStyle(color: t.muted),
    ),
  );
}

/// 应用画布：渐变底 + 固定光源层。所有页面都套在它里面。
///
/// **光源是固定的**：设计稿特别说明旧版让光斑漂移是错的 ——
/// 光一移动，所有阴影的方向就全错了。所以这里只是一幅静态背景。
class NeuCanvas extends StatelessWidget {
  const NeuCanvas({super.key, required this.child, this.brightness = Brightness.light});

  final Widget child;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: NeuDecorations.canvasGradient(t)),
      // RepaintBoundary：光源层是静态装饰，交互时不该跟着重绘
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _OrbPainter(tokens: t, isDark: brightness == Brightness.dark),
          child: child,
        ),
      ),
    );
  }
}

/// 四个柔光池（设计稿 `.orb-a` ~ `.orb-d`）。
///
/// 直接用径向渐变的自然衰减来表达模糊，不额外套 `ImageFilter.blur` ——
/// CSS 那边要 blur(72px) 是因为它在画实心圆；这里渐变的透明端本来就够软，
/// 省掉四层全屏模糊，移动端帧率差别很明显。
class _OrbPainter extends CustomPainter {
  const _OrbPainter({required this.tokens, required this.isDark});

  final NeuTokens tokens;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    // orb-a：左上白光池。暗色档只剩 10% 白（设计稿对暗色档的单独覆盖）
    _orb(
      canvas,
      size,
      left: -0.26,
      top: -0.26,
      diameter: 1.04,
      color: Colors.white,
      opacity: isDark ? 0.10 : 0.55,
    );
    // orb-b：右上，用画布亮端混白
    _orb(
      canvas,
      size,
      left: 0.48,
      top: -0.06,
      diameter: 0.76,
      color: Color.lerp(tokens.bgHi, Colors.white, 0.9)!,
      opacity: tokens.orbOpacity * 0.7,
    );
    // orb-c：右下，画布暗端
    _orb(
      canvas,
      size,
      left: 0.24,
      top: 0.30,
      diameter: 0.96,
      color: tokens.bgLo,
      opacity: tokens.orbOpacity,
    );
    // orb-d：左下，画布暗端（更淡）
    _orb(
      canvas,
      size,
      left: -0.16,
      top: 0.42,
      diameter: 0.70,
      color: tokens.bgLo,
      opacity: tokens.orbOpacity * 0.7,
    );
  }

  /// [left] / [top] 是相对画布宽高的百分比（对应 CSS 的 left/top 百分比），
  /// [diameter] 是相对**宽度**的直径（CSS 用 aspect-ratio:1 保持正圆）。
  void _orb(
    Canvas canvas,
    Size size, {
    required double left,
    required double top,
    required double diameter,
    required Color color,
    required double opacity,
  }) {
    final d = size.width * diameter;
    final center = Offset(size.width * left + d / 2, size.height * top + d / 2);
    final radius = d / 2;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: opacity.clamp(0.0, 1.0)),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.78],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.tokens != tokens;
}
