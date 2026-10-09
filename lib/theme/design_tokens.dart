import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'oklch.dart';

/// 设计稿的完整 token 表 —— 与 `pi-remote-app.html` 的 `:root` 和
/// `html[data-theme="dark"]` 逐条对应。
///
/// 每个字段上方都留着设计稿的原始写法，想核对「这个色到底抄对没有」，
/// 直接在设计稿里搜 `--bg:` 之类的变量名就能对上。
///
/// 新拟态的第一定律：**材质就是画布本身**。所以这里没有「卡片色 / 边框色」，
/// 只有画布（bg）、隆起面（surface）、凹槽（well）三族，各带亮端/暗端，
/// 形体完全由「左上白光 + 右下暗影」一对软阴影建立 —— 见 [NeuShadows]。
class NeuTokens {
  const NeuTokens({
    required this.bg,
    required this.bgHi,
    required this.bgLo,
    required this.surface,
    required this.surfaceHi,
    required this.surfaceLo,
    required this.well,
    required this.wellHi,
    required this.wellLo,
    required this.nmHi,
    required this.nmLo,
    required this.nmLoDeep,
    required this.fg,
    required this.muted,
    required this.onBg,
    required this.onBgDim,
    required this.border,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.success,
    required this.danger,
    required this.dangerSoft,
    required this.onDanger,
    required this.warn,
    required this.lvOk,
    required this.lvWarn,
    required this.lvErr,
    required this.viz,
    required this.toastBg,
    required this.toastFg,
    required this.toastAccent,
    required this.stage,
    required this.orbOpacity,
  });

  // ── 画布与材质 ──
  /// `--bg` 画布基底
  final Color bg;

  /// `--bg-hi` 画布亮端（光源侧）
  final Color bgHi;

  /// `--bg-lo` 画布暗端（背光侧）
  final Color bgLo;

  /// `--surface` 隆起面：与画布同色，只靠阴影成形
  final Color surface;
  final Color surfaceHi;
  final Color surfaceLo;

  /// `--well` 内凹槽（输入框、选中态）
  final Color well;
  final Color wellHi;
  final Color wellLo;

  // ── 一对软阴影：整套设计只有这一个光源（左上）──
  /// `--nm-hi` 迎光面（左上）
  final Color nmHi;

  /// `--nm-lo` 背光面（右下）
  final Color nmLo;

  /// `--nm-lo-deep` 贴地那层的深色，给隆起面一点落地感
  final Color nmLoDeep;

  // ── 文字 ──
  /// `--fg` 主文字（材质上的石板青）
  final Color fg;

  /// `--muted` 次要文字
  final Color muted;

  /// `--on-bg` 画布上的文字
  final Color onBg;

  /// `--on-bg-dim` 画布暗端上的文字（比 onBg 再压一档）
  final Color onBgDim;

  /// `--border` 只用于分隔细线与内凹描边
  final Color border;

  // ── 强调色：一屏一处 ──
  /// `--accent` 实心块专用
  final Color accent;

  /// `--accent-ink` 材质上的强调文字/图标
  final Color accentInk;

  /// `--on-accent` 实心强调块上的字
  final Color onAccent;

  final Color success;
  final Color danger;

  /// `--danger-soft` 危险操作 hover 底色
  final Color dangerSoft;

  /// `--on-danger` 实心危险块上的字
  final Color onDanger;

  final Color warn;

  // ── 日志等级字（按凹槽上 ≥4.5:1 单独定值，不能复用状态色）──
  final Color lvOk;
  final Color lvWarn;
  final Color lvErr;

  /// 饼图分类色：全部落在薄荷→青的色弧，靠明度拉开差异
  final List<Color> viz;

  // ── 浮层 ──
  final Color toastBg;
  final Color toastFg;
  final Color toastAccent;

  /// `--stage` 桌面舞台：中性冷灰，比画布深一档，设备壳才跳得出来
  final Color stage;

  /// `--orb-op` 光源层的光斑透明度
  final double orbOpacity;

  /// 浅色档：薄荷画布 + 石板青字形（设计稿默认主题）。
  static final NeuTokens light = NeuTokens(
    bg: oklch(0.935, 0.038, 172), // oklch(93.5% 0.038 172)
    bgHi: oklch(0.962, 0.030, 170), // oklch(96.2% 0.030 170)
    bgLo: oklch(0.870, 0.044, 176), // oklch(87% 0.044 176)
    surface: oklch(0.952, 0.032, 172), // oklch(95.2% 0.032 172)
    surfaceHi: oklch(0.970, 0.026, 170), // oklch(97.0% 0.026 170)
    surfaceLo: oklch(0.902, 0.040, 176), // oklch(90.2% 0.040 176)
    well: oklch(0.915, 0.038, 174), // oklch(91.5% 0.038 174)
    wellHi: oklch(0.884, 0.040, 176), // oklch(88.4% 0.040 176) 亮端反而更深
    wellLo: oklch(0.950, 0.028, 170), // oklch(95.0% 0.028 170)
    nmHi: const Color(0xF2FFFFFF), // rgb(255 255 255 / .95)
    nmLo: oklch(0.70, 0.036, 192, 0.80), // oklch(70% 0.036 192 / .80)
    nmLoDeep: oklch(0.62, 0.034, 192, 0.40), // oklch(62% 0.034 192 / .40)
    fg: oklch(0.40, 0.038, 205), // 材质上 7.9:1
    muted: oklch(0.48, 0.038, 205), // 隆面 5.6:1、凹槽 5.0:1
    onBg: oklch(0.38, 0.042, 205),
    onBgDim: oklch(0.46, 0.040, 203), // 画布最暗端上 4.8:1
    border: oklch(0.80, 0.026, 178),
    accent: oklch(0.55, 0.060, 200), // 配白字 4.7:1
    accentInk: oklch(0.46, 0.058, 202), // 6.1:1
    onAccent: const Color(0xFFFFFFFF),
    success: oklch(0.58, 0.095, 168),
    danger: oklch(0.52, 0.150, 25),
    dangerSoft: oklch(0.52, 0.150, 25, 0.14),
    onDanger: const Color(0xFFFFFFFF), // 5.9:1
    warn: oklch(0.52, 0.105, 62),
    lvOk: oklch(0.47, 0.095, 168), // 凹槽 5.12:1
    lvWarn: oklch(0.50, 0.105, 62), // 凹槽 4.88:1
    lvErr: oklch(0.52, 0.150, 25), // 凹槽 4.69:1
    viz: [
      oklch(0.42, 0.078, 206),
      oklch(0.47, 0.072, 192),
      oklch(0.52, 0.066, 178),
      oklch(0.57, 0.058, 164),
      oklch(0.40, 0.058, 228),
    ],
    toastBg: oklch(0.34, 0.030, 205, 0.96),
    toastFg: oklch(0.97, 0.010, 180),
    toastAccent: oklch(0.84, 0.070, 180),
    stage: oklch(0.79, 0.012, 205),
    orbOpacity: 0.75,
  );

  /// 深色档。注意暗色下 nm-hi 只剩一点点白（`rgb(255 255 255 / .055)`）——
  /// 暗部想表现「被光照亮」只能靠极轻微的提亮，否则立刻变成灰糊。
  static final NeuTokens dark = NeuTokens(
    bg: oklch(0.260, 0.022, 195),
    bgHi: oklch(0.305, 0.024, 192),
    bgLo: oklch(0.210, 0.024, 198),
    surface: oklch(0.285, 0.022, 195),
    surfaceHi: oklch(0.315, 0.023, 192),
    surfaceLo: oklch(0.245, 0.023, 198),
    well: oklch(0.250, 0.023, 197),
    wellHi: oklch(0.220, 0.024, 199),
    wellLo: oklch(0.290, 0.022, 194),
    nmHi: const Color(0x0EFFFFFF), // rgb(255 255 255 / .055)
    nmLo: oklch(0.11, 0.014, 202, 0.70),
    nmLoDeep: oklch(0.08, 0.012, 202, 0.55),
    fg: oklch(0.930, 0.012, 180), // 12.3:1
    muted: oklch(0.740, 0.018, 180), // 6.6:1
    onBg: oklch(0.940, 0.012, 180),
    onBgDim: oklch(0.740, 0.016, 180),
    border: const Color(0x1AFFFFFF), // oklch(100% 0 0 / 10%)
    accent: oklch(0.660, 0.075, 190), // 亮青实心块，配深字
    accentInk: oklch(0.820, 0.060, 180), // 8.8:1
    onAccent: oklch(0.240, 0.020, 205),
    success: oklch(0.780, 0.090, 168),
    danger: oklch(0.720, 0.130, 28),
    dangerSoft: oklch(0.720, 0.130, 28, 0.20),
    onDanger: oklch(0.200, 0.030, 25), // 亮红上配白字只有 2.3:1，必须翻成深字
    warn: oklch(0.800, 0.100, 70),
    lvOk: oklch(0.780, 0.090, 168), // 凹槽 8.25:1
    lvWarn: oklch(0.800, 0.100, 70), // 凹槽 8.37:1
    lvErr: oklch(0.720, 0.130, 28), // 凹槽 6.06:1
    viz: [
      oklch(0.72, 0.070, 206),
      oklch(0.80, 0.062, 192),
      oklch(0.86, 0.052, 178),
      oklch(0.92, 0.038, 164),
      oklch(0.76, 0.052, 228),
    ],
    toastBg: oklch(0.92, 0.018, 180, 0.96),
    toastFg: oklch(0.24, 0.020, 205),
    toastAccent: oklch(0.40, 0.070, 195),
    stage: oklch(0.155, 0.014, 202),
    orbOpacity: 0.85,
  );
}

/// 圆角制式。新拟态的形体全靠圆角 + 软阴影，所以这里统一收口，
/// 禁止在页面里随手写圆角数值。
abstract final class NeuRadii {
  /// `--r-lg` 大卡片、输入条、Tab 栏
  static const double lg = 26;

  /// `--r-md` 中卡片、气泡、快捷键栏
  static const double md = 20;

  /// `--r-sm` 小按钮、表单控件
  static const double sm = 14;

  /// 小标签 / 内联 chip 圆角 12px（统计出现 3 次）
  static const double chip = 12;

  /// 小控件圆角 10px（出现 2 次）
  static const double xs = 10;

  /// 微圆角 2px（出现 11 次：进度条、细条、分隔块）
  static const double hairline = 2;

  /// `--kb-h` 快捷键栏折叠高度（一行键帽）—— 与滚动到底部按钮的落点耦合，
  /// 改这里必须同时改那个按钮的 bottom 计算。
  static const double keyBarH = 44;

  /// `--kb-h-open` 快捷键栏展开高度（标题行 + 三列四行）
  static const double keyBarHOpen = 244;
}

/// 间距制式。命名直接用数值（`n8` = 8），避免 `xs/sm/md` 这种「记不住哪个大」的
/// 命名在十几个档位下失控；值与原字面量完全相同（视觉零变化）。
///
/// 统计来源（task-4 第二轮）：全仓 356 处 `EdgeInsets.*`（602 个数值）+
/// 334 处 `SizedBox(width/height: 数字)`，频次依次是
/// 18/10/6/12/8/14/4/9/16/11/24/2/20/13/3/1/5/7 —— 覆盖 0–24 整数即可打包绝大多数；
/// `EdgeInsets.zero` 仍直接用框架常量，不进令牌。
abstract final class NeuSpace {
  static const double n1 = 1;
  static const double n2 = 2;
  static const double n3 = 3;
  static const double n4 = 4;
  static const double n5 = 5;
  static const double n6 = 6;
  static const double n7 = 7;
  static const double n8 = 8;
  static const double n9 = 9;
  static const double n10 = 10;
  static const double n11 = 11;
  static const double n12 = 12;
  static const double n13 = 13;
  static const double n14 = 14;
  static const double n16 = 16;
  static const double n18 = 18;
  static const double n20 = 20;
  static const double n24 = 24;
}

/// 动效制式：曲线收敛为 3 条、时长收敛为 6 档（设计稿原文的取舍）。
///
/// 设计稿的病因分析值得记下来：旧版散落 7 条自定义贝塞尔，同一屏里
/// 面板、Tab、toast 各弹各的强度，用户感觉不到规律，只觉得「杂」。
/// 层级越浅的动作弹性越小；位移进场的末梢减速比弹跳更耐看。
abstract final class NeuMotion {
  /// `--e-out` 位移 / 进场：末梢减速
  static const Curve out = Cubic(0.22, 1, 0.36, 1);

  /// `--e-spring` 结构动作：面板、Tab、消息
  static const Curve spring = Cubic(0.24, 1.16, 0.36, 1);

  /// `--e-inout` 对称：箭头翻转、状态切换
  static const Curve inOut = Cubic(0.4, 0, 0.2, 1);

  /// `--d-press` 按压位移（emil 准则 100–160ms 的下限，手指必须有即时响应）
  static const Duration press = Duration(milliseconds: 120);

  /// 常规过渡的主档（task-22 合同⑥ 收的：全 App 有 5 处散着写 220ms）
  static const Duration base = Duration(milliseconds: 220);

  /// `--d-micro` hover / 颜色 / 阴影微变
  static const Duration micro = Duration(milliseconds: 160);

  /// `--d-struct` 列表展开、图标浮现、箭头翻转
  static const Duration struct = Duration(milliseconds: 260);

  /// `--d-panel` 面板与浮层进出（sheet / 命令菜单 / toast）
  static const Duration panel = Duration(milliseconds: 340);

  /// `--d-page` 页面切换（唯一需要更长的动作，因为它跨越整屏）
  static const Duration page = Duration(milliseconds: 420);

  /// `--d-data` 数据变化（环形进度）：读数需可追溯，比结构动作慢一档
  static const Duration data = Duration(milliseconds: 620);
}

/// 一套光源（左上迎光 / 右下背光）推导出的全部阴影。
///
/// 外阴影直接交给 Flutter 的 [BoxShadow]；**内凹阴影 Flutter 没有原生支持**，
/// 这里同样产出 [BoxShadow] 描述，由 `NeuInset` 用 CustomPainter 绘制
/// （见 `neu.dart`）。CSS 的 blur radius 与 Flutter 的 blurRadius 语义一致，
/// 因此数值照抄设计稿即可。
abstract final class NeuShadows {
  /// `--nm-raise-sm` 小隆起：图标底板、键帽
  ///
  /// 模糊半径从设计稿的 7 收到 5。理由是实测的性能账：连接页这类长表单页
  /// 上同时存在二十多个这种图层，滚动时每个都要做一次高斯模糊 ——
  /// 用户在真机上反馈「手指滑、画面跟不上」。偏移量没动，所以明暗方向
  /// 和投影形状不变，只是边缘略紧一点，肉眼看不出差别。
  /// 要回到设计稿原值：7 / 16 / 24。
  static List<BoxShadow> raiseSm(NeuTokens t) => [
    BoxShadow(color: t.nmLo, offset: const Offset(3, 3), blurRadius: 5),
    BoxShadow(color: t.nmHi, offset: const Offset(-3, -3), blurRadius: 5),
  ];

  /// `--nm-raise` 标准隆起：卡片、气泡（模糊半径 16 → 11，见上）
  static List<BoxShadow> raise(NeuTokens t) => [
    BoxShadow(color: t.nmLo, offset: const Offset(7, 7), blurRadius: 11),
    BoxShadow(color: t.nmHi, offset: const Offset(-7, -7), blurRadius: 11),
    BoxShadow(color: t.nmLoDeep, offset: const Offset(0, 1), blurRadius: 2),
  ];

  /// `--nm-raise-lg` 大隆起：压在画布最外层的元素（模糊半径 24 → 16，见上）
  static List<BoxShadow> raiseLg(NeuTokens t) => [
    BoxShadow(color: t.nmLo, offset: const Offset(10, 10), blurRadius: 16),
    BoxShadow(color: t.nmHi, offset: const Offset(-10, -10), blurRadius: 16),
    BoxShadow(color: t.nmLoDeep, offset: const Offset(0, 2), blurRadius: 4),
  ];

  /// `--nm-inset-sm` 浅凹槽：输入框、键帽底
  static List<BoxShadow> insetSm(NeuTokens t) => [
    BoxShadow(color: t.nmLo, offset: const Offset(2.5, 2.5), blurRadius: 6),
    BoxShadow(color: t.nmHi, offset: const Offset(-2.5, -2.5), blurRadius: 6),
  ];

  /// `--nm-inset` 深凹槽：输入条、日志面板、选中态
  static List<BoxShadow> inset(NeuTokens t) => [
    BoxShadow(color: t.nmLo, offset: const Offset(5, 5), blurRadius: 11),
    BoxShadow(color: t.nmHi, offset: const Offset(-5, -5), blurRadius: 11),
  ];
}

/// 字体层级。设计稿用 `ui-rounded` 做标题、系统字做正文、等宽字做数据；
/// Android 上没有 ui-rounded，标题退化为系统字 + 700 字重 —— 靠字重和字号
/// 维持「标题更实」的层级差，而不是硬换字体。
abstract final class NeuFonts {
  /// `.page-title` 27px
  static const double pageTitle = 27;

  /// `.ct-title` / `.cfg-title` 16.5–17px
  static const double sectionTitle = 17;

  /// 正文 14–15px
  static const double body = 14.5;

  /// `.ct-sub` / 次要说明 12.5–13px
  static const double sub = 12.5;

  /// `.hist-title` / `.set-label` 小号全大写标签 11.5px
  static const double label = 11.5;

  /// 键帽 / 调试数据 10.5–11.5px
  static const double mono = 11.5;

  // —— 下面三个是 task-21 合同⑥ 补的 ——
  // 统计五个页面发现：12.5 / 11.5 / 12 / 13 / 13.5 这五个值覆盖了绝大多数文字，
  // 但它们之前是**散在各处的字面量**（12.5 出现 67 次、11.5 出现 60 次…），
  // 想统一调一次字号得全局搜。这里给它们名字，值不变（视觉零变化），
  // 以后调"辅助文字多大"只需要改这一处。

  /// 比 sub 再小一档的说明文字 12px
  static const double small = 12;

  /// 次要正文 13px
  static const double bodySmall = 13;

  /// 主次之间的正文 13.5px
  static const double bodyMid = 13.5;

  // —— 下面这批是「代码体检」补的（task-4 一致性收敛）——
  // 方法同上：先统计各页面实际用的字号，把高频值给名字，**值不变**（视觉零变化）。
  // 统计时共 137 处硬编码 fontSize，频次为：
  // 11(41) 10.5(28) 14(24) 17(17) 15(9) 16(6) 10(6) 14.5(4) 24(1) 20(1)。
  // 其中 17 复用 sectionTitle、14.5 复用 body；24 / 20 各仅 1 次，作为特例豁免。

  /// 徽章 / 角标数字 11px
  static const double badge = 11;

  /// 比 label 再小一档 10.5px（卡片角落的元信息）
  static const double micro = 10.5;

  /// 紧凑正文 14px（列表行、副标题）
  static const double bodyTight = 14;

  /// 略大于正文 15px
  static const double bodyLg = 15;

  /// 小标题 16px（介于正文与 sectionTitle 之间）
  static const double heading = 16;

  /// 极小标注 10px（图标旁计数）
  static const double tiny = 10;
}
