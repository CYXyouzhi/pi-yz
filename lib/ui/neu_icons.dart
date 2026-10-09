import 'package:flutter/material.dart';

import '../theme/svg_path.dart';

/// 图标图元 —— 忠实对应设计稿里混用的 `<path>` / `<rect>` / `<circle>`。
///
/// 不统一压成 path 字符串，是因为设计稿本身就用这三种元素混写；
/// 保持同构，抄图标时不必手工改写数据，也就不会抄错。
sealed class IconShape {
  const IconShape();
}

/// `<path d="...">`
class PathShape extends IconShape {
  const PathShape(this.d);
  final String d;
}

/// `<rect x y width height rx>`
class RectShape extends IconShape {
  const RectShape(this.x, this.y, this.width, this.height, [this.rx = 0]);
  final double x, y, width, height, rx;
}

/// `<circle cx cy r>`
class CircleShape extends IconShape {
  const CircleShape(this.cx, this.cy, this.r);
  final double cx, cy, r;
}

/// 一个图标的形状集合。
class NeuIconData {
  const NeuIconData(this.shapes);

  /// 同一个图标可含多条线（例如「服务器堆叠」= 两个方块 + 内部短横 + 两个指示灯）。
  final List<IconShape> shapes;
}

/// 唯一真源图标集。
///
/// 设计稿强调过：**同语义必须复用同一路径，不得另画**。
/// 所以这里每个条目只存一份数据，页面里按语义引用，尺寸由渲染端控制。
enum IconId {
  /// 服务器堆叠 SERVER —— 连接入口 / 设置 hero / 主机条目 / 配置页标题
  server,

  /// 服务器 + 加号 —— 新建连接
  serverPlus,

  /// 会话气泡 BUBBLE —— Tab 会话 / 空态 / 会话条目
  bubble,

  /// 垃圾桶 TRASH（无内部竖线，小尺寸不粘连）
  trash,

  /// 电源 POWER —— 断开连接（全 App 唯一）
  power,

  /// 加号 PLUS —— 新会话
  plus,

  /// 笔 PEN —— 编辑连接配置
  pen,

  chevronRight,
  chevronDown,
  chevronLeft,
  check,
  close,
  warn,
  info,
  spinner,
  circle,
  terminal,
  folder,
  lock,
  cmd,
  send,
  gear,
  home,
  sync,
  download,

  /// 复制 —— 长按菜单里的「复制」
  copy,

  /// 分享 —— 系统分享面板
  share,

  /// 图片 —— 存到相册
  image,

  /// 更多 —— 消息上的「复制/引用/编辑重发/分享」菜单入口
  more,
}

/// 图标数据表 —— 路径逐条抄自 `pi-remote-app.html`，未做任何改写。
const Map<IconId, NeuIconData> kNeuIcons = {
  IconId.server: NeuIconData([
    RectShape(3.1, 3.6, 17.8, 7.2, 2.3),
    RectShape(3.1, 13.2, 17.8, 7.2, 2.3),
    PathShape('M6.8 7.2h3.3M6.8 16.8h3.3'),
    CircleShape(17.1, 7.2, 1.05),
    CircleShape(17.1, 16.8, 1.05),
  ]),
  IconId.serverPlus: NeuIconData([
    RectShape(3.1, 3.6, 17.8, 7.2, 2.3),
    RectShape(3.1, 13.2, 17.8, 7.2, 2.3),
    PathShape('M6.8 7.2h3.3M6.8 16.8h3.3'),
    PathShape('M15.4 7.2h3.4M17.1 5.5v3.4'),
    CircleShape(17.1, 16.8, 1.05),
  ]),
  IconId.bubble: NeuIconData([
    PathShape(
      'M8.2 4h7.6a5 5 0 0 1 5 5v2.8a5 5 0 0 1-5 5h-4.3l-3.9 3.4 2-3.4h-1.4a5 5 0 0 1-5-5V9a5 5 0 0 1 5-5Z',
    ),
  ]),
  IconId.trash: NeuIconData([
    PathShape('M3.4 6.2h17.2'),
    PathShape(
      'M18.9 6.2v11.9a2.3 2.3 0 0 1-2.3 2.3H7.4a2.3 2.3 0 0 1-2.3-2.3V6.2',
    ),
    PathShape(
      'M8.6 6.2V4.7a1.5 1.5 0 0 1 1.5-1.5h3.8a1.5 1.5 0 0 1 1.5 1.5v1.5',
    ),
  ]),
  IconId.power: NeuIconData([
    PathShape('M12 3v8'),
    PathShape('M6.8 6.8a8 8 0 1 0 10.4 0'),
  ]),
  IconId.plus: NeuIconData([PathShape('M12 3.8v16.4M3.8 12h16.4')]),
  IconId.pen: NeuIconData([
    PathShape('M4.6 19.25l1-4L16.1 4.75a2.35 2.35 0 0 1 3.32 3.32L8.8 18.65Z'),
    PathShape('M15.35 5.75l2.85 2.85'),
  ]),
  IconId.chevronRight: NeuIconData([PathShape('M9 6l6 6-6 6')]),
  IconId.chevronDown: NeuIconData([PathShape('M6 9l6 6 6-6')]),
  IconId.chevronLeft: NeuIconData([PathShape('M15 6l-6 6 6 6')]),
  IconId.check: NeuIconData([PathShape('M3.6 12.1 9.4 17.9 20.4 6.1')]),
  IconId.close: NeuIconData([
    PathShape('M6.2 6.2 17.8 17.8M17.8 6.2 6.2 17.8'),
  ]),
  IconId.warn: NeuIconData([
    CircleShape(12, 12, 9),
    PathShape('M12 7.6v5.4M12 16.4h.01'),
  ]),
  IconId.info: NeuIconData([
    CircleShape(12, 12, 8.4),
    PathShape('M12 11.4v4.4M12 8.2h.01'),
  ]),
  IconId.spinner: NeuIconData([PathShape('M12 3.6a8.4 8.4 0 1 0 8.4 8.4')]),
  IconId.circle: NeuIconData([CircleShape(12, 12, 8.4)]),
  IconId.terminal: NeuIconData([
    RectShape(3, 4.9, 18, 14.2, 3.4),
    PathShape('M7.6 9.6 10.4 12 7.6 14.4'),
    PathShape('M12.9 14.4h3.5'),
  ]),
  IconId.folder: NeuIconData([
    PathShape(
      'M3.2 6.7A2.2 2.2 0 0 1 5.4 4.5h4.2l2.1 2.6h7.1a2.2 2.2 0 0 1 2.2 2.2v8a2.2 2.2 0 0 1-2.2 2.2H5.4a2.2 2.2 0 0 1-2.2-2.2Z',
    ),
  ]),
  IconId.lock: NeuIconData([
    RectShape(4.5, 10.5, 15, 9, 2.5),
    PathShape('M8 10.5V7.5a4 4 0 0 1 8 0v3'),
  ]),
  IconId.cmd: NeuIconData([
    PathShape(
      'M15 6v12a3 3 0 1 0 3-3H6a3 3 0 1 0 3 3V6a3 3 0 1 0-3 3h12a3 3 0 1 0-3-3',
    ),
  ]),
  IconId.send: NeuIconData([
    PathShape('M19.28 4.58 3.32 12.37l6.37 2.37 2.66 6.08Z'),
    PathShape('M9.69 14.74 19.28 4.58'),
  ]),
  IconId.gear: NeuIconData([
    CircleShape(12, 12, 2.7),
    PathShape(
      'M10.21 3.59 13.79 3.59 13.82 6.39 15.95 7.62 18.39 6.25 20.18 9.34 17.77 10.77 '
      '17.77 13.23 20.18 14.66 18.39 17.75 15.95 16.38 13.82 17.61 13.79 20.41 10.21 20.41 '
      '10.18 17.61 8.05 16.38 5.61 17.75 3.82 14.66 6.23 13.23 6.23 10.77 3.82 9.34 5.61 6.25 '
      '8.05 7.62 10.18 6.39Z',
    ),
  ]),
  IconId.home: NeuIconData([
    PathShape(
      'M3.4 10.1 12 4.1l8.6 6V18.7a1.6 1.6 0 0 1-1.6 1.6H5a1.6 1.6 0 0 1-1.6-1.6Z',
    ),
  ]),
  IconId.sync: NeuIconData([
    PathShape('M4 9h12.6l-3.2-3.2'),
    PathShape('M20 15H7.4l3.2 3.2'),
  ]),
  IconId.download: NeuIconData([
    PathShape('M4.8 8.6 12 15.6 19.2 8.6'),
    PathShape('M5.2 19.4h13.6'),
  ]),

  // 下面三个是这次补的（菜单里要用，原设计稿没有）：
  // 复制 = 两张叠起来的纸；分享 = 安卓三节点；图片 = 相框里的山与太阳
  IconId.copy: NeuIconData([
    RectShape(8.4, 3.6, 11.6, 13.4, 2),
    PathShape('M15.6 20.4H6a2.4 2.4 0 0 1-2.4-2.4V7.2'),
  ]),
  IconId.share: NeuIconData([
    CircleShape(17.4, 5.6, 2.6),
    CircleShape(6.6, 12, 2.6),
    CircleShape(17.4, 18.4, 2.6),
    PathShape('M15.2 6.9 8.9 10.7'),
    PathShape('M8.9 13.3l6.3 3.8'),
  ]),
  IconId.more: NeuIconData([
    CircleShape(12, 5.4, 1.5),
    CircleShape(12, 12, 1.5),
    CircleShape(12, 18.6, 1.5),
  ]),
  IconId.image: NeuIconData([
    RectShape(3.4, 4.4, 17.2, 15.2, 2.6),
    CircleShape(8.8, 9.4, 1.7),
    PathShape('M4.2 17.2 10 11.8l4.4 4.2 3.2-2.8 2.8 2.6'),
  ]),
};

/// 图标渲染组件。
///
/// **线宽补偿**是这里唯一的巧思：设计稿要求「目标设备线宽恒定 1.55px」。
/// 画布固定 24×24，渲染到 [size] 时整体缩放 `size/24`，线宽会被一起缩放，
/// 于是把小尺寸的图标画细了（14px 的图标线宽会掉到 0.9px）。
/// 解决办法是**反向补偿**：坐标系里的线宽写成 `1.55 * 24 / size`，
/// 缩放回去正好是 1.55px。设计稿那张尺寸/线宽对照表就是这张换算的结果。
class NeuIcon extends StatelessWidget {
  const NeuIcon(this.icon, {super.key, this.size = 18, this.color});

  final IconId icon;
  final double size;

  /// 不传则跟随最近的 [IconTheme] / [DefaultTextStyle] 前景色。
  final Color? color;

  /// 设计稿的目标渲染线宽。
  static const double targetStrokeWidth = 1.55;

  /// 把「目标渲染线宽」换算成 24×24 坐标系里的线宽。
  static double strokeWidthFor(double size) => targetStrokeWidth * 24 / size;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    final data = kNeuIcons[icon]!;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _IconPainter(
          shapes: data.shapes,
          strokeWidth: strokeWidthFor(size),
          color: resolved,
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter({
    required this.shapes,
    required this.strokeWidth,
    required this.color,
  });

  final List<IconShape> shapes;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      // 设计稿规范：端帽一律 round，拐角一律 round
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    canvas.save();
    // 24×24 的图标坐标系 → 实际尺寸
    canvas.scale(size.width / 24);
    for (final shape in shapes) {
      canvas.drawPath(_toPath(shape), paint);
    }
    canvas.restore();
  }

  Path _toPath(IconShape shape) => switch (shape) {
    PathShape() => parseSvgPath(shape.d),
    RectShape() =>
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height),
          Radius.circular(shape.rx),
        ),
      ),
    CircleShape() =>
      Path()..addOval(
        Rect.fromCircle(center: Offset(shape.cx, shape.cy), radius: shape.r),
      ),
  };

  @override
  bool shouldRepaint(_IconPainter oldDelegate) =>
      oldDelegate.shapes != shapes ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.color != color;
}
