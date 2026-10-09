import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 把 token 表挂到 Flutter 主题上，页面里用 `context.neu` 取。
///
/// 为什么不直接全局单例：设计稿有浅/深两档，且主题要能在运行时切换。
/// 挂进 ThemeData 后，切换主题只换一次 ThemeData，所有材质组件自动跟进。
class NeuTheme extends ThemeExtension<NeuTheme> {
  const NeuTheme(this.tokens);

  final NeuTokens tokens;

  @override
  NeuTheme copyWith({NeuTokens? tokens}) => NeuTheme(tokens ?? this.tokens);

  /// 设计稿明确说过：CSS 变量换值是瞬时的，**只有声明了 transition 的属性会滑过去**，
  /// 且那样会出现「背景在慢慢变色、卡片已经全换完」的割裂感。
  /// 所以这里不做颜色插值 —— 主题切换是一次干净的跳变。
  @override
  NeuTheme lerp(ThemeExtension<NeuTheme>? other, double t) {
    if (other is! NeuTheme) return this;
    return t < 0.5 ? this : other;
  }
}

/// 便捷取值：`context.neu.fg`
extension NeuContextExtension on BuildContext {
  NeuTokens get neu => Theme.of(this).extension<NeuTheme>()!.tokens;
}

/// **减少动态偏好**（对应 CSS 的 `prefers-reduced-motion`）。
///
/// 设计稿的取舍值得照抄：旧版一刀切 `animation:none / transition:none`，
/// 把连接心跳、诊断转圈也一并杀了 —— 用户于是完全看不到「连接中 / 运行中」，
/// 那是**信息缺失，不是无障碍**。
///
/// 现在的原则是：**去掉「运动」，保留「反馈」**。
/// - 允许透明度变化（不引起前庭反应）
/// - 位移与缩放一律归零
/// - 时长压到 1ms，等于瞬变，但状态仍会切换
///
extension NeuMotionContextExtension on BuildContext {
  /// 系统是否要求减少动态。
  bool get neuReduceMotion =>
      MediaQuery.maybeOf(this)?.disableAnimations ?? false;

  /// 时长：减少动态时瞬变。
  Duration neuDur(Duration normal) =>
      neuReduceMotion ? const Duration(milliseconds: 1) : normal;

  /// 位移 / 缩放量：减少动态时归零（只留透明度）。
  double neuMotion(double value) => neuReduceMotion ? 0 : value;
}

/// 从 token 推导出的常用装饰（渐变 + 阴影），页面里直接用，避免各页各写一遍。
abstract final class NeuDecorations {
  /// 隆起面渐变：`linear-gradient(145deg, surface-hi, surface 48%, surface-lo)`。
  /// 145° 与 135° 在眼睛看来差别极小，用 topLeft→bottomRight 表达
  /// 「左上迎光、右下背光」这个唯一光源的意图。
  static LinearGradient raisedGradient(NeuTokens t) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [t.surfaceHi, t.surface, t.surfaceLo],
    stops: const [0.0, 0.48, 1.0],
  );

  /// 凹槽渐变：`linear-gradient(145deg, well-hi, well 55%, well-lo)`。
  /// 注意 `well-hi` 比 `well` **更暗** —— 内凹的亮端反而更深，
  /// 因为背光的右侧要把光反上来。搞反这一条，凹槽会读成隆起。
  static LinearGradient wellGradient(NeuTokens t) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [t.wellHi, t.well, t.wellLo],
    stops: const [0.0, 0.55, 1.0],
  );

  /// 实心强调块的渐变：`accent` 两端各混一点白/黑，做出圆柱感。
  static LinearGradient accentGradient(NeuTokens t) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.lerp(t.accent, Colors.white, 0.12)!,
      t.accent,
      Color.lerp(t.accent, Colors.black, 0.14)!,
    ],
    stops: const [0.0, 0.52, 1.0],
  );

  /// 实心危险块的渐变（设计稿 `.set-cf-ok`）。
  static LinearGradient dangerGradient(NeuTokens t) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color.lerp(t.danger, Colors.white, 0.12)!, t.danger],
    stops: const [0.0, 0.6],
  );

  /// 画布背景：亮端左上、暗端右下，与所有材质面同向。
  static LinearGradient canvasGradient(NeuTokens t) => LinearGradient(
    begin: const Alignment(-0.4, -1.0),
    end: const Alignment(0.5, 1.0),
    colors: [t.bgHi, t.bg, t.bgLo],
    stops: const [0.0, 0.44, 1.0],
  );

  static BoxDecoration raised(
    NeuTokens t, {
    double radius = NeuRadii.lg,
    NeuLevel level = NeuLevel.standard,
  }) => BoxDecoration(
    gradient: raisedGradient(t),
    borderRadius: BorderRadius.circular(radius),
    boxShadow: switch (level) {
      NeuLevel.small => NeuShadows.raiseSm(t),
      NeuLevel.standard => NeuShadows.raise(t),
      NeuLevel.large => NeuShadows.raiseLg(t),
    },
  );
}

/// 隆起幅度的三档（对应设计稿 --nm-raise-sm / --nm-raise / --nm-raise-lg）。
enum NeuLevel { small, standard, large }

/// **内凹阴影画笔** —— Flutter 的 `BoxShadow` 只支持外阴影，CSS 的 `inset` 没有对应物。
///
/// 实现原理：内阴影本质是「从边缘向内衰减的阴影」。把「整个画布」减去「一个平移过的
/// 圆角矩形」，剩下的环形区域正好落在**与平移相反的那一侧边缘**——
/// 例如形状向右下平移，环带就留在左上，也就得到了「左上暗」的内阴影。
/// 用 evenOdd 填充规则一次画出这个环，再对环做高斯模糊，就得到软过渡。
///
/// 模糊半径与 Flutter 的 `BoxShadow.blurRadius` 走同一套换算，
/// 保证内阴影和外阴影的软硬程度一致。
class InsetShadowPainter extends CustomPainter {
  const InsetShadowPainter({
    required this.shadows,
    required this.borderRadius,
    this.gradient,
  });

  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;
  final Gradient? gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    // 1) 打底渐变
    if (gradient != null) {
      canvas.drawRRect(rrect, Paint()..shader = gradient!.createShader(rect));
    }

    if (shadows.isEmpty) return;

    // 2) 内阴影：裁剪进圆角矩形后，逐条画「环带」
    canvas.save();
    canvas.clipRRect(rrect);

    // 环带的外框要比本体大得多，模糊才不会从外缘渗回来
    final outerRect = rect.inflate(rect.longestSide + 200);
    for (final shadow in shadows) {
      final paint = Paint()
        ..color = shadow.color
        ..maskFilter = shadow.blurRadius > 0
            ? MaskFilter.blur(BlurStyle.normal, _sigma(shadow.blurRadius))
            : null;
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(outerRect)
        ..addRRect(rrect.shift(shadow.offset));
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  /// 与 Flutter `BoxShadow` 内部一致的高斯换算（blurRadius → sigma）。
  static double _sigma(double blurRadius) => blurRadius * 0.57735 + 0.5;

  @override
  bool shouldRepaint(InsetShadowPainter oldDelegate) =>
      oldDelegate.shadows != shadows ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.gradient != gradient;
}

/// **凹槽**组件：内凹材质 + 可选的子内容。
///
/// 页面上凡是「输入框 / 选中态 / 日志面板 / 分隔槽」都走它，
/// 保证全 App 只有一个内凹公式。
class NeuInset extends StatelessWidget {
  const NeuInset({
    super.key,
    this.child,
    this.radius = NeuRadii.md,
    this.padding,
    this.margin,
    this.deep = false,
    this.gradient,
    this.width,
    this.height,
    this.shadows,
  });

  final Widget? child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// true 用 `--nm-inset`（深凹），false 用 `--nm-inset-sm`（浅凹）。
  final bool deep;

  /// 自定义渐变；默认用凹槽渐变。
  final Gradient? gradient;

  final double? width;
  final double? height;

  /// 自定义内阴影；默认按 [deep] 选一档。
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final br = BorderRadius.circular(radius);
    return Container(
      width: width,
      height: height,
      margin: margin,
      child: CustomPaint(
        painter: InsetShadowPainter(
          shadows:
              shadows ?? (deep ? NeuShadows.inset(t) : NeuShadows.insetSm(t)),
          borderRadius: br,
          gradient: gradient ?? NeuDecorations.wellGradient(t),
        ),
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}

/// **隆起面**组件：卡片、图标底板、气泡的默认材质。
class NeuRaised extends StatelessWidget {
  const NeuRaised({
    super.key,
    this.child,
    this.radius = NeuRadii.lg,
    this.padding,
    this.margin,
    this.level = NeuLevel.standard,
    this.gradient,
    this.width,
    this.height,
    this.alignment,
  });

  final Widget? child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final NeuLevel level;
  final Gradient? gradient;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Container(
      width: width,
      height: height,
      margin: margin,
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient ?? NeuDecorations.raisedGradient(t),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: switch (level) {
          NeuLevel.small => NeuShadows.raiseSm(t),
          NeuLevel.standard => NeuShadows.raise(t),
          NeuLevel.large => NeuShadows.raiseLg(t),
        },
      ),
      child: child,
    );
  }
}

/// **可按压的隆起面**：新拟态的按压语法是「按下即内凹」。
///
/// 设计稿反复强调过为什么不用变色表达按压：洗色会把底色压暗，
/// 深色文字的对比度反而下降（主卡 7.97 → 7.50）。内凹阴影不动底色，
/// 所以对比度恒定，而且「按进去」本来就是这套材质系统的原生语法。
class NeuPressable extends StatefulWidget {
  const NeuPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.radius = NeuRadii.sm,
    this.level = NeuLevel.small,
    this.insetDeep = false,
    this.enabled = true,
    this.padding,
    this.margin,
    this.gradient,
    this.alwaysInset = false,
    this.flat = false,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// 长按：同一个按钮上的第二层动作（例如「新会话」长按选模板）
  final VoidCallback? onLongPress;
  final double radius;
  final NeuLevel level;

  /// 按下时用深凹还是浅凹。
  final bool insetDeep;
  final bool enabled;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Gradient? gradient;

  /// 常驻内凹（用于「当前选中项」——设计稿里 .wsg-item.active 就是这个语义）。
  final bool alwaysInset;

  /// 平面模式：未按下、未选中时**不带任何材质**（透明、无阴影）。
  ///
  /// 列表行必须用它：设计稿的做法是「未选中是平的，不抢主卡的隆起，
  /// 选中 = 按进去」。全都隆起的话一屏全是凸起，反而认不出当前项在哪。
  final bool flat;

  final String? semanticLabel;

  @override
  State<NeuPressable> createState() => _NeuPressableState();
}

class _NeuPressableState extends State<NeuPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    final br = BorderRadius.circular(widget.radius);
    final inset = widget.alwaysInset || _down;

    final isFlat = widget.flat && !inset;
    final Widget content = Container(
      padding: widget.padding,
      decoration: isFlat
          ? null
          : BoxDecoration(
              gradient:
                  widget.gradient ??
                  (inset
                      ? NeuDecorations.wellGradient(t)
                      : NeuDecorations.raisedGradient(t)),
              borderRadius: br,
              // 按下时去掉外阴影 —— 同时留外阴影和内阴影会读成「两层材质叠一起」
              boxShadow: inset
                  ? null
                  : switch (widget.level) {
                      NeuLevel.small => NeuShadows.raiseSm(t),
                      NeuLevel.standard => NeuShadows.raise(t),
                      NeuLevel.large => NeuShadows.raiseLg(t),
                    },
            ),
      child: widget.child,
    );

    return Padding(
      padding: widget.margin ?? EdgeInsets.zero,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: widget.enabled
            ? () => setState(() => _down = false)
            : null,
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: Semantics(
          button: widget.onTap != null,
          label: widget.semanticLabel,
          child: AnimatedSwitcher(
            duration: NeuMotion.micro,
            switchInCurve: NeuMotion.out,
            switchOutCurve: NeuMotion.out,
            // 内凹用 CustomPaint 叠加：AnimatedSwitcher 在两个 DecoratedBox 之间
            // 交叉淡入，视觉上就是「隆起化开、凹陷浮现」，时长 160ms 符合 --d-micro。
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.center,
              // `?current` 是 Dart 的 null-aware element：为 null 时不产生这一项
              children: [...previous, ?current],
            ),
            child: KeyedSubtree(
              key: ValueKey(inset),
              child: inset
                  ? CustomPaint(
                      painter: InsetShadowPainter(
                        shadows: widget.insetDeep
                            ? NeuShadows.inset(t)
                            : NeuShadows.insetSm(t),
                        borderRadius: br,
                        gradient:
                            widget.gradient ?? NeuDecorations.wellGradient(t),
                      ),
                      child: Padding(
                        padding: widget.padding ?? EdgeInsets.zero,
                        child: widget.child,
                      ),
                    )
                  : content,
            ),
          ),
        ),
      ),
    );
  }
}
