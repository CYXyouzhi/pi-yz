// 折叠分组的「真能折」守卫。
//
// 这条测试来自审计抓到的一个真 bug：连接页的「快速连接」「已保存」当时
// 只调了 `_section(...)`（会画标题 + 箭头 + onToggle），**内容却无条件渲染** ——
// 于是点标题只会翻转箭头，块根本折不起来。
//
// 两者必须成对：
//   _section(t, <KEY>, ...)          ← 承诺「这块可折叠」的视觉信号
//   if (_expanded.contains(<KEY>))   ← 兑现它
//
// 键在 `_section` 里默认取 title 表达式，也可以用 `stateKey:` 显式给
// （带计数的标题必须显式给，否则计数一变展开状态就丢）。所以这里两边都收。
//
// 这是**源码级**的结构测试，不是 widget 测试：单页 widget 测试要 mock 整个
// Store，成本高且容易只覆盖一个页面；而这类 bug 的形态是「漏写配对」，
// 静态检查能一次覆盖三个页面、也不会因为 UI 重构就失效。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 按第一层逗号切出调用参数（跳过字符串字面量与嵌套括号）。
List<String> argumentsOf(String src, int openParen) {
  final args = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  String? quote;
  for (var i = openParen; i < src.length; i++) {
    final c = src[i];
    if (quote != null) {
      if (c == r'\') {
        buf.write(c);
        if (i + 1 < src.length) {
          buf.write(src[i + 1]);
          i++;
        }
        continue;
      }
      if (c == quote) quote = null;
      buf.write(c);
    } else if (c == "'" || c == '"') {
      quote = c;
      buf.write(c);
    } else if (c == '(') {
      depth++;
      if (depth > 1) buf.write(c);
    } else if (c == ')') {
      depth--;
      if (depth == 0) {
        args.add(buf.toString());
        return args;
      }
      buf.write(c);
    } else if (c == ',' && depth == 1) {
      args.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  return args;
}

/// 取出每个 `_section(...)` 调用的**第二个**位置参数（title），以及可能存在的
/// `stateKey:` 取值。
///
/// 第一个位置参数是 `NeuTokens t`（`Widget _section(NeuTokens t, String title, ...)`），
/// 所以不能直接拿第一个。
///
/// 排除定义处（`Widget _section(`）与注释里顺口提到的那种。
List<({String title, String? stateKey})> sectionCalls(String src) {
  final calls = <({String title, String? stateKey})>[];
  final re = RegExp(r'_section\(');
  for (final m in re.allMatches(src)) {
    final before = src.substring(0, m.start);
    if (RegExp(r'Widget\s+$').hasMatch(before)) continue;
    final lineStart = before.lastIndexOf('\n') + 1;
    if (src.substring(lineStart, m.start).trimLeft().startsWith('//')) continue;

    final args = argumentsOf(src, m.end - 1);
    if (args.length < 2) continue;
    // `stateKey:` 常和说明性注释挤在同一个片段里（注释行也是换行分隔的），
    // 所以这里用正则找，而不是看片段开头。
    final tail = args.skip(2).join(',');
    final keyMatch = RegExp("stateKey:\\s*('[^']*'|\"[^\"]*\")").firstMatch(tail);
    final stateKey = keyMatch?.group(1);
    calls.add((title: args[1].trim(), stateKey: stateKey));
  }
  return calls;
}

/// 源码里是否存在 `_expanded.contains(<key>)` 形式的门控。
///
/// 用正则而不是 `contains`：真实写法常常是跨行的 ——
///
/// ```dart
/// if (_expanded.contains(
///   I18n.t('settings.conn', context: context),
/// )) ...[
/// ```
///
/// 直接 `contains` 会因为换行和结尾逗号而漏判（第一版就漏了，把设置页
/// 五个本来有门控的分组全报成了缺失）。
bool hasGate(String src, String key) {
  final pattern = RegExp(
    r'_expanded\.contains\(\s*' + RegExp.escape(key) + r'\s*,?\s*\)',
  );
  return pattern.hasMatch(src);
}

/// 显式 `stateKey: 'x'` 的取值。
List<String> stateKeys(String src) => RegExp(
      "stateKey:\\s*('[^']*'|\"[^\"]*\")",
    ).allMatches(src).map((m) => m.group(1)!).toList();

void main() {
  const pages = <String, String>{
    '设置页': 'lib/ui/server/settings_page.dart',
    '连接页': 'lib/ui/server/conn_page.dart',
    'AI 配置页': 'lib/ui/server/config_page.dart',
  };

  pages.forEach((label, path) {
    group('$label（$path）', () {
      late String src;

      setUpAll(() {
        src = File(path).readAsStringSync();
      });

      test('每个 _section 的键都出现在 _expanded.contains(...) 里', () {
        final calls = sectionCalls(src);
        expect(calls, isNotEmpty, reason: '一个 _section 都没解析到，说明解析逻辑失效了');

        final missing = <String>[];
        for (final call in calls) {
          // 显式给了 stateKey 的分组，门控键就是 stateKey、与标题无关
          // （标题里带计数，不能拿来当键），交给下面那条测试管。
          if (call.stateKey != null) continue;
          if (!hasGate(src, call.title)) missing.add(call.title);
        }

        expect(
          missing,
          isEmpty,
          reason: '这些分组的标题会画箭头、却没有配套的折叠判断，'
              '点下去只会翻箭头、内容收不起来：\n  ${missing.join('\n  ')}',
        );
      });

      test('显式 stateKey 也要有配套的折叠判断', () {
        for (final key in stateKeys(src)) {
          expect(
            hasGate(src, key),
            isTrue,
            reason: 'stateKey: $key 没有对应的 _expanded.contains($key)',
          );
        }
      });
    });
  });

  test('连接页的三个分组确实被门控（审计点名的那两个 + 手动配置）', () {
    final src = File('lib/ui/server/conn_page.dart').readAsStringSync();
    for (final key in [
      "I18n.t('conn.groupQuick')",
      "I18n.t('ui.f8dfedcd8a')",
      "I18n.t('conn.groupManual')",
    ]) {
      expect(hasGate(src, key), isTrue,
          reason: '$key 的内容没有包在 if (_expanded.contains(...)) 里');
    }
  });
}
