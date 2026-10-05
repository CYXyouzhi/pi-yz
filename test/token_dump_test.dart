// ignore_for_file: avoid_print
//
// 这是设计系统的**数值核对工具**：把 Dart 侧算出的 token 色值打到 stdout，
// 再用 Chrome 的 canvas 取同一份 oklch 的真实渲染像素做交叉验证。
// 之所以用 print 而不是日志框架，正是因为它要的就是一份可直接 diff 的纯文本。
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_mobile/theme/design_tokens.dart';

String h6(Color c) {
  String f(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '#${f((c.r * 255).round())}${f((c.g * 255).round())}${f((c.b * 255).round())}';
}

void main() {
  test('dump tokens for cross-check', () {
    final l = NeuTokens.light;
    print('DART light bg ${h6(l.bg)}');
    print('DART light bg-hi ${h6(l.bgHi)}');
    print('DART light bg-lo ${h6(l.bgLo)}');
    print('DART light surface ${h6(l.surface)}');
    print('DART light surface-hi ${h6(l.surfaceHi)}');
    print('DART light surface-lo ${h6(l.surfaceLo)}');
    print('DART light well ${h6(l.well)}');
    print('DART light well-hi ${h6(l.wellHi)}');
    print('DART light well-lo ${h6(l.wellLo)}');
    print('DART light fg ${h6(l.fg)}');
    print('DART light muted ${h6(l.muted)}');
    print('DART light on-bg ${h6(l.onBg)}');
    print('DART light on-bg-dim ${h6(l.onBgDim)}');
    print('DART light accent ${h6(l.accent)}');
    print('DART light accent-ink ${h6(l.accentInk)}');
    print('DART light success ${h6(l.success)}');
    print('DART light danger ${h6(l.danger)}');
    print('DART light warn ${h6(l.warn)}');
    print('DART light lv-ok ${h6(l.lvOk)}');
    print('DART light viz-1 ${h6(l.viz[0])}');
    print('DART light viz-5 ${h6(l.viz[4])}');
    print('DART light stage ${h6(l.stage)}');
    final d = NeuTokens.dark;
    print('DART dark  bg ${h6(d.bg)}');
    print('DART dark  bg-hi ${h6(d.bgHi)}');
    print('DART dark  surface ${h6(d.surface)}');
    print('DART dark  well ${h6(d.well)}');
    print('DART dark  fg ${h6(d.fg)}');
    print('DART dark  muted ${h6(d.muted)}');
    print('DART dark  accent ${h6(d.accent)}');
    print('DART dark  accent-ink ${h6(d.accentInk)}');
    print('DART dark  success ${h6(d.success)}');
    print('DART dark  danger ${h6(d.danger)}');
    print('DART dark  stage ${h6(d.stage)}');
  });
}
