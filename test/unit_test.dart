// ignore_for_file: avoid_print
//
// 单元层验证：按键编码 / oklch 换算 / 图标路径解析。
// 这三块是「UI 之下的地基」—— 它们错了，页面看起来可能还是对的，
// 但实际发出去的字节、画出来的颜色就是错的。所以单独锁死。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/services/key_encoder.dart';
import 'package:pi_yz/theme/design_tokens.dart';
import 'package:pi_yz/theme/svg_path.dart';
import 'package:pi_yz/ui/neu_icons.dart';

void main() {
  group('KeyEncoder —— 转义序列编码', () {
    test('光标键：无修饰用短形式，有修饰带参', () {
      expect(KeyEncoder.up(), '\x1b[A');
      expect(KeyEncoder.down(), '\x1b[B');
      expect(KeyEncoder.right(), '\x1b[C');
      expect(KeyEncoder.left(), '\x1b[D');

      // 修饰符 = 1 + shift*1 + alt*2 + ctrl*4
      expect(KeyEncoder.up(ctrl: true), '\x1b[1;5A');
      expect(KeyEncoder.up(shift: true), '\x1b[1;2A');
      expect(KeyEncoder.up(alt: true), '\x1b[1;3A');
      expect(KeyEncoder.up(ctrl: true, shift: true), '\x1b[1;6A');
    });

    test('翻页与首尾键', () {
      expect(KeyEncoder.pageUp(), '\x1b[5~');
      expect(KeyEncoder.pageDown(), '\x1b[6~');
      expect(KeyEncoder.home(), '\x1b[H');
      expect(KeyEncoder.end(), '\x1b[F');
    });

    test('Ctrl + 字母走传统控制字符（最兼容）', () {
      expect(KeyEncoder.ctrlLetter('c'), '\x03');
      expect(KeyEncoder.ctrlLetter('d'), '\x04');
      expect(KeyEncoder.ctrlLetter('C'), '\x03'); // 大小写等价
      expect(KeyEncoder.ctrlLetter('1'), isNull); // 非字母
    });

    test('基础键', () {
      expect(KeyEncoder.esc, '\x1b');
      expect(KeyEncoder.tab, '\t');
      expect(KeyEncoder.shiftTab, '\x1b[Z');
      expect(KeyEncoder.enter, '\r');
      expect(KeyEncoder.backspace, '\x7f');
      expect(KeyEncoder.delete, '\x1b[3~');
    });

    test('Shift+Enter 用 CSI-u（与 Enter 区分开）', () {
      expect(KeyEncoder.shiftEnter(), '\x1b[13;2u');
      expect(KeyEncoder.csiU(99, ctrl: true), '\x1b[99;5u');
    });

    test('功能键：F1-F4 用 SS3，F5 起用 CSI', () {
      expect(KeyEncoder.f(1), '\x1bOP');
      expect(KeyEncoder.f(5), '\x1b[15~');
      expect(KeyEncoder.f(12), '\x1b[24~');
    });
  });

  group('oklch → sRGB', () {
    // 期望值来自 Chrome 的 canvas 取像素（浏览器自己的 CSS Color 4 实现），
    // 允许每通道 ±1 的舍入差。
    void expectClose(Color actual, int r, int g, int b, {String? label}) {
      final ar = (actual.r * 255).round();
      final ag = (actual.g * 255).round();
      final ab = (actual.b * 255).round();
      expect((ar - r).abs() <= 1, isTrue, reason: '$label R: $ar vs $r');
      expect((ag - g).abs() <= 1, isTrue, reason: '$label G: $ag vs $g');
      expect((ab - b).abs() <= 1, isTrue, reason: '$label B: $ab vs $b');
    }

    test('浅色档关键 token 与设计稿一致', () {
      final t = NeuTokens.light;
      expectClose(t.bg, 0xD1, 0xF2, 0xE7, label: 'bg');
      expectClose(t.bgHi, 0xE0, 0xF9, 0xEF, label: 'bg-hi');
      expectClose(t.bgLo, 0xB7, 0xDE, 0xD3, label: 'bg-lo');
      expectClose(t.surface, 0xDB, 0xF7, 0xED, label: 'surface');
      expectClose(t.well, 0xCA, 0xEC, 0xE1, label: 'well');
      expectClose(t.fg, 0x2E, 0x4E, 0x51, label: 'fg');
      expectClose(t.muted, 0x44, 0x64, 0x68, label: 'muted');
      expectClose(t.success, 0x35, 0x8C, 0x6F, label: 'success');
      expectClose(t.danger, 0xAF, 0x3C, 0x3A, label: 'danger');
    });

    test('深色档关键 token 与设计稿一致', () {
      final t = NeuTokens.dark;
      expectClose(t.bg, 0x17, 0x27, 0x27, label: 'dark bg');
      expectClose(t.bgHi, 0x21, 0x33, 0x32, label: 'dark bg-hi');
      expectClose(t.fg, 0xE0, 0xEB, 0xE8, label: 'dark fg');
      expectClose(t.muted, 0x9F, 0xAF, 0xAB, label: 'dark muted');
      expectClose(t.stage, 0x06, 0x0E, 0x0F, label: 'dark stage');
    });

    test('新拟态的光照关系不能反：well-hi 必须比 well 暗、surface-hi 比 surface 亮', () {
      // 这是整套材质的物理一致性 —— 搞反了凹槽会读成隆起
      final l = NeuTokens.light;
      expect(l.wellHi.computeLuminance() < l.well.computeLuminance(), isTrue);
      expect(
        l.surfaceHi.computeLuminance() > l.surface.computeLuminance(),
        isTrue,
      );
      expect(l.bgHi.computeLuminance() > l.bgLo.computeLuminance(), isTrue);
    });
  });

  group('图标路径解析', () {
    test('每个图标都能解析出非空的、落在 24×24 光学框附近的包围盒', () {
      for (final entry in kNeuIcons.entries) {
        final bounds = _boundsOf(entry.value);
        expect(
          bounds.isEmpty,
          isFalse,
          reason: '${entry.key.name} 解析出空路径（数据或解析器有问题）',
        );
        // 光学框是 3–21；留一点余量给描边与个别出框的笔锋
        expect(
          bounds.left,
          greaterThanOrEqualTo(-0.5),
          reason: '${entry.key.name} 左边界越出网格: ${bounds.left}',
        );
        expect(
          bounds.top,
          greaterThanOrEqualTo(-0.5),
          reason: '${entry.key.name} 上边界越出网格: ${bounds.top}',
        );
        expect(
          bounds.right,
          lessThanOrEqualTo(24.5),
          reason: '${entry.key.name} 右边界越出网格: ${bounds.right}',
        );
        expect(
          bounds.bottom,
          lessThanOrEqualTo(24.5),
          reason: '${entry.key.name} 下边界越出网格: ${bounds.bottom}',
        );
      }
    });

    test('线宽补偿：渲染后恒定 1.55px', () {
      expect(NeuIcon.strokeWidthFor(12), closeTo(3.10, 0.01));
      expect(NeuIcon.strokeWidthFor(14), closeTo(2.66, 0.01));
      expect(NeuIcon.strokeWidthFor(16), closeTo(2.33, 0.01));
      expect(NeuIcon.strokeWidthFor(18), closeTo(2.07, 0.01));
      expect(NeuIcon.strokeWidthFor(20), closeTo(1.86, 0.01));
      expect(NeuIcon.strokeWidthFor(22), closeTo(1.69, 0.01));
      expect(NeuIcon.strokeWidthFor(24), closeTo(1.55, 0.01));
      expect(NeuIcon.strokeWidthFor(26), closeTo(1.43, 0.01));

      // 关键性质：坐标系线宽 × 缩放 = 恒定
      for (final size in [12.0, 16.0, 22.0, 26.0]) {
        final rendered = NeuIcon.strokeWidthFor(size) * size / 24;
        expect(rendered, closeTo(1.55, 0.001), reason: '${size}px 渲染线宽漂了');
      }
    });

    test('弧形与隐式重复参数都被吃下', () {
      // 设计稿里真实用到的两种紧凑写法
      final arc = parseSvgPath('M12 3.6a8.4 8.4 0 1 0 8.4 8.4');
      expect(arc.getBounds().isEmpty, isFalse);

      final implicit = parseSvgPath('M3.6 12.1 9.4 17.9 20.4 6.1');
      final b = implicit.getBounds();
      expect(b.width, closeTo(16.8, 0.01));
      expect(b.height, closeTo(11.8, 0.01));
    });
  });
}

Rect _boundsOf(NeuIconData data) {
  Rect? acc;
  for (final shape in data.shapes) {
    final path = switch (shape) {
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
    final b = path.getBounds();
    acc = acc == null ? b : acc.expandToInclude(b);
  }
  return acc ?? Rect.zero;
}
