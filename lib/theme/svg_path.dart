import 'dart:math' as math;
import 'dart:ui';

/// 极简 SVG path 解析器。
///
/// 只覆盖设计稿实际用到的命令：`M/L/H/V/C/Q/A/Z`（含相对形式与隐式重复参数）。
///
/// 为什么自己写而不引入 flutter_svg：图标规范的核心约束是
/// **「渲染后线宽恒定 1.55px」**，需要精确控制「画布缩放」与「线宽补偿」的
/// 关系（见 `neu_icons.dart` 里的 strokeWidth 换算）。自己解析最直接，
/// 也少一个依赖。设计稿里的图标都是简单几何，用不到 SVG 的完整语法。
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _tokenize(d);
  var i = 0;

  String cmd = '';
  double x = 0, y = 0; // 当前点
  double startX = 0, startY = 0; // 子路径起点，Z 回到这里

  double num() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    final t = tokens[i];
    if (_isCommand(t)) {
      cmd = t;
      i++;
    } else if (cmd.isEmpty) {
      // 路径不以命令开头是非法数据，跳过这个记号避免死循环
      i++;
      continue;
    }

    switch (cmd) {
      // ── 移动到／直线 ──
      case 'M':
        x = num();
        y = num();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // SVG 规定：M 后面多余的坐标对按 L 处理
        cmd = 'L';
        break;
      case 'm':
        x += num();
        y += num();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        cmd = 'l';
        break;
      case 'L':
        x = num();
        y = num();
        path.lineTo(x, y);
        break;
      case 'l':
        x += num();
        y += num();
        path.lineTo(x, y);
        break;
      case 'H':
        x = num();
        path.lineTo(x, y);
        break;
      case 'h':
        x += num();
        path.lineTo(x, y);
        break;
      case 'V':
        y = num();
        path.lineTo(x, y);
        break;
      case 'v':
        y += num();
        path.lineTo(x, y);
        break;

      // ── 三次贝塞尔 ──
      case 'C':
        final x1 = num(), y1 = num(), x2 = num(), y2 = num();
        x = num();
        y = num();
        path.cubicTo(x1, y1, x2, y2, x, y);
        break;
      case 'c':
        final x1 = x + num(), y1 = y + num(), x2 = x + num(), y2 = y + num();
        x += num();
        y += num();
        path.cubicTo(x1, y1, x2, y2, x, y);
        break;

      // ── 二次贝塞尔 ──
      case 'Q':
        final x1 = num(), y1 = num();
        x = num();
        y = num();
        path.quadraticBezierTo(x1, y1, x, y);
        break;
      case 'q':
        final x1 = x + num(), y1 = y + num();
        x += num();
        y += num();
        path.quadraticBezierTo(x1, y1, x, y);
        break;

      // ── 圆弧 ──
      case 'A':
        final rx = num(), ry = num(), rot = num();
        final largeArc = num() != 0;
        final sweep = num() != 0;
        final ex = num(), ey = num();
        _arcTo(path, rx, ry, rot, largeArc, sweep, x, y, ex, ey);
        x = ex;
        y = ey;
        break;
      case 'a':
        final rx = num(), ry = num(), rot = num();
        final largeArc = num() != 0;
        final sweep = num() != 0;
        final ex = x + num(), ey = y + num();
        _arcTo(path, rx, ry, rot, largeArc, sweep, x, y, ex, ey);
        x = ex;
        y = ey;
        break;

      // ── 闭合 ──
      case 'Z':
      case 'z':
        path.close();
        x = startX;
        y = startY;
        // 闭合后若还有坐标对，按当前点继续；把命令置空等下一个命令字母
        cmd = '';
        break;

      default:
        i++;
        break;
    }
  }
  return path;
}

/// 椭圆弧：按 SVG 规范附录 F.6.5 把「端点参数化」转成「中心参数化」，
/// 再交给 Flutter 的 [Path.arcTo]。
///
/// 设计稿里的弧都是正圆（rx == ry）且不旋转，但这里仍按一般情况实现，
/// 免得以后加图标时踩坑。
void _arcTo(
  Path path,
  double rx,
  double ry,
  double rotationDeg,
  bool largeArc,
  bool sweep,
  double x0,
  double y0,
  double x1,
  double y1,
) {
  if (rx == 0 || ry == 0) {
    path.lineTo(x1, y1);
    return;
  }
  rx = rx.abs();
  ry = ry.abs();

  final phi = rotationDeg * math.pi / 180.0;
  final cosPhi = math.cos(phi);
  final sinPhi = math.sin(phi);

  // 把终点变换到椭圆坐标系
  final dx = (x0 - x1) / 2.0;
  final dy = (y0 - y1) / 2.0;
  final x0p = cosPhi * dx + sinPhi * dy;
  final y0p = -sinPhi * dx + cosPhi * dy;

  // 半径不足时按规范等比放大
  final lambda = (x0p * x0p) / (rx * rx) + (y0p * y0p) / (ry * ry);
  if (lambda > 1) {
    final s = math.sqrt(lambda);
    rx *= s;
    ry *= s;
  }

  final rx2 = rx * rx;
  final ry2 = ry * ry;
  final x0p2 = x0p * x0p;
  final y0p2 = y0p * y0p;

  final numerator = rx2 * ry2 - rx2 * y0p2 - ry2 * x0p2;
  final denominator = rx2 * y0p2 + ry2 * x0p2;
  final factor = (largeArc != sweep ? 1 : -1) *
      math.sqrt(math.max(0.0, numerator / denominator));

  final cxp = factor * rx * y0p / ry;
  final cyp = -factor * ry * x0p / rx;

  // 转回原坐标系
  final cx = cosPhi * cxp - sinPhi * cyp + (x0 + x1) / 2.0;
  final cy = sinPhi * cxp + cosPhi * cyp + (y0 + y1) / 2.0;

  double angle(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    if (len == 0) return 0;
    var a = math.acos((dot / len).clamp(-1.0, 1.0));
    if (ux * vy - uy * vx < 0) a = -a;
    return a;
  }

  final ux = (x0p - cxp) / rx;
  final uy = (y0p - cyp) / ry;
  final vx = (-x0p - cxp) / rx;
  final vy = (-y0p - cyp) / ry;

  final startAngle = angle(1, 0, ux, uy);
  var sweepAngle = angle(ux, uy, vx, vy);

  if (!sweep && sweepAngle > 0) {
    sweepAngle -= 2 * math.pi;
  } else if (sweep && sweepAngle < 0) {
    sweepAngle += 2 * math.pi;
  }

  path.arcTo(
    Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
    startAngle,
    sweepAngle,
    false,
  );
}

bool _isCommand(String token) {
  final c = token.codeUnitAt(0);
  // A-Z 或 a-z
  return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
}

final _tokenPattern = RegExp(
  r'[MmLlHhVvCcQqAaZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
);

List<String> _tokenize(String d) =>
    _tokenPattern.allMatches(d).map((m) => m.group(0)!).toList();
