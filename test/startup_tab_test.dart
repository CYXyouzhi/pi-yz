// 启动落点守卫：打开 App 必须停在「开始」tab。
//
// 来自用户反馈的真 bug：启动自动恢复上次会话时顺手把 tab 切到了「会话」，
// 于是每次冷启动都落在会话页 —— 而 `_tab` 的初值明明是 0（开始页）。
//
// 为什么是**源码级**测试（而不是 widget 测试）：要复现原 bug 得造出
// 「已保存 profile + 连得上 + 恢复了 lastSession」三件事同时成立，
// 等于 mock 整个 HTTP 层；而这个 bug 的形态是「多了一次自动赋值」，
// 静态检查一眼就能覆盖，也不会因为 UI 重构失效（同 fold_gating_test 的理由）。
//
// 守两条不变式：
//   1. `_tab` 初值 = 0（开始页）
//   2. 挂到 store 上的监听器**不许改** `_tab` —— store 状态变化（自动连上、
//      恢复会话、会话跑完…）都不替用户切页
//
// 允许改 `_tab` 的地方只有「用户动作」：点底部 tab、点会话行、点通知、
// 连接页连上后跳转。它们都是回调参数，不是 store 监听器，所以不会被这里拦。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 从 [open] 位置（一个 `{`）开始做括号配对，返回函数体文本。
///
/// 不做完整解析：只要跳过字符串字面量与注释，够用且不会因为格式变化失效。
String _balancedBody(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == "'" || c == '"') {
      final quote = c;
      i++;
      while (i < src.length && src[i] != quote) {
        if (src[i] == r'\') i++;
        i++;
      }
      continue;
    }
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  return src.substring(open);
}

/// 取具名方法的函数体（从方法名后的第一个 `{` 起算）。
String _bodyOf(String src, String name) {
  final at = RegExp('(?:void|Future<void>|bool|int)\\s+$name\\s*\\(').firstMatch(src);
  expect(at, isNotNull, reason: 'main.dart 里找不到方法 $name()');
  final open = src.indexOf('{', at!.end);
  return _balancedBody(src, open);
}

void main() {
  final src = File('lib/main.dart').readAsStringSync();

  test('启动落在「开始」tab：_tab 初值必须是 0', () {
    expect(
      RegExp(r'int\s+_tab\s*=\s*0\s*;').hasMatch(src),
      isTrue,
      reason: '把 _tab 初值改成 1 就等于「打开 App 直接进会话页」——用户反馈过这个行为。',
    );
  });

  test('store 监听器不许改 _tab（不替用户切 tab）', () {
    final listeners = RegExp(r'_serverStore\.addListener\(\s*([^)]*?)\s*\)')
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toList();

    for (final raw in listeners) {
      // 闭包形式没法按名字审查 —— 与其放过，不如要求写成具名方法
      expect(
        RegExp(r'^[A-Za-z_]\w*$').hasMatch(raw),
        isTrue,
        reason: 'addListener 的实参请用具名方法（当前是 `$raw`），否则这条守卫查不到它改了什么。',
      );
      final body = _bodyOf(src, raw);
      expect(
        body.contains('_tab'),
        isFalse,
        reason: 'store 监听器 $raw() 改了 _tab —— 启动自动恢复会话时会把用户拽去会话页。'
            '要跳页请走用户动作（点 tab / 点会话行 / 点通知 / 连接页连上）。',
      );
    }
  });
}
