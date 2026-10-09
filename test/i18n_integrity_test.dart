// 文案完整性：代码里引用的每个 key 都必须真的在词表里，且中英两侧可用。
//
// 为什么这三条值得单独守：
//
//  1. `I18n.t()` 找不到 key 时**返回 key 本身**（刻意设计，让漏翻一眼可见），
//     于是漏登记的表现是界面上出现 `ui.8cd4d69138` 这种字符串 —— 用户看得到，
//     但它属于运行时行为，`grep` 代码 grep 不出来，只能靠测试挡。
//  2. 这轮合并了 8 组重复词条（把引用从废弃 key 改到保留 key），正是最容易
//     漏改引用的场景。
//  3. 带 `{占位符}` 的文案如果中英两侧占位符不一致，`tp()` 会留下没被替换的
//     `{time}` 或直接抛错 —— 这类问题只在特定文案上复现，肉眼审词表很容易漏。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/i18n.dart';

/// 扫出 `lib/` 下所有**字面量**文案 key（同时覆盖 `t('k')` 与 `tp('k', {...})`）。
///
/// 动态取用的 key（例如语言切换器的 `I18n.t(option.$2)` 实际取 `lang.zh`）扫不到，
/// 所以这个集合是「至少要被登记」的下界，不是全集 —— 这也是第二条断言（集合非空）
/// 存在的原因：正则失效时它会立刻失败，而不是静默地一个都没扫到。
Set<String> collectReferencedKeys() {
  final re = RegExp(r"I18n\.t(?:p)?\(\s*'([^']+)'");
  final out = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // 词表文件自身不算「引用」
    if (entity.uri.pathSegments.last == 'i18n.dart') continue;
    for (final m in re.allMatches(entity.readAsStringSync())) {
      out.add(m.group(1)!);
    }
  }
  return out;
}

void main() {
  test('代码里引用的每个文案 key 都在词表里（否则界面会显示 key 原文）', () {
    final known = I18n.debugKeys.toSet();
    final referenced = collectReferencedKeys();

    // 扫描本身要有效。若正则在某次重构后失配，这个断言会先炸，
    // 而不是让下面那条「missing 为空」变成永远成立的假绿灯。
    expect(
      referenced.length,
      greaterThan(100),
      reason: '只扫到 ${referenced.length} 个 key，扫描逻辑可能已失效',
    );

    final missing = referenced.where((k) => !known.contains(k)).toList()
      ..sort();

    expect(missing, isEmpty, reason: '这些 key 没有登记，运行时会原样显示成 key 字符串：$missing');
  });

  test('中英两侧的空格化占位符必须一致', () {
    final placeholder = RegExp(r'\{(\w+)\}');
    final mismatched = <String>[];

    I18n.debugStrings.forEach((key, v) {
      final zh = placeholder.allMatches(v.$1).map((m) => m.group(1)!).toSet();
      final en = placeholder.allMatches(v.$2).map((m) => m.group(1)!).toSet();
      if (!setEquals(zh, en)) {
        mismatched.add(
          '$key: zh=${zh.toList()..sort()} en=${en.toList()..sort()}',
        );
      }
    });

    expect(
      mismatched,
      isEmpty,
      reason: '占位符不一致会让 tp() 替换不完整或抛错：\n${mismatched.join('\n')}',
    );
  });

  test('没有中栏或英栏为空的条目（不假装翻过）', () {
    final empty = <String>[];
    I18n.debugStrings.forEach((key, v) {
      if (v.$1.trim().isEmpty) empty.add('$key 的中文为空');
      if (v.$2.trim().isEmpty) empty.add('$key 的英文为空');
    });

    expect(empty, isEmpty, reason: empty.join('；'));
  });

  test('报告：词表里存在但代码未引用的条目（冗余，不断言）', () {
    // 只打印，不失败：有些 key 是动态取用的（`I18n.t(option.$2)` → `lang.zh`），
    // 静态扫描看不见它们，断言会把误报当真错。留着是为了合并词条时能看见线索。
    final known = I18n.debugKeys.toSet();
    final referenced = collectReferencedKeys();
    final unused = known.difference(referenced).toList()..sort();

    printOnFailure('未引用的 key: ${unused.join(', ')}');
    // 这条永远成立，只是为了让测试名出现在报告里
    expect(known.length, greaterThan(100));
  });
}
