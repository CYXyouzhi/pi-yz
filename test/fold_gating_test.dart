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
    if (args.isEmpty) continue;
    // `_section` 现在有两种签名，都要认：
    //   · 页面里：`_section(t, <TITLE>, ...)` —— 第一个参数是 NeuTokens
    //   · 组件里：`_section(<TITLE>, ...)`    —— t 由组件自己 context.neu 取，不传了
    // 所以先看第一个参数是不是 `t`，再决定 title 取第几个。
    final titleIndex = args[0].trim() == 't' ? 1 : 0;
    if (args.length <= titleIndex) continue;
    // `stateKey:` 常和说明性注释挤在同一个片段里（注释行也是换行分隔的），
    // 所以这里用正则找，而不是看片段开头。
    final tail = args.skip(titleIndex + 1).join(',');
    final keyMatch = RegExp("stateKey:\\s*('[^']*'|\"[^\"]*\")")
        .firstMatch(tail);
    final stateKey = keyMatch?.group(1);
    calls.add((title: args[titleIndex].trim(), stateKey: stateKey));
  }
  return calls;
}

/// 取出组件里 `NeuSection(title: <KEY>, ...)` 的 title。
///
/// 重构后「分组头」从页面的 `_section(<KEY>, ...)` 搬进了组件的 `NeuSection(...)` ——
/// 两者是同一件事（都画标题 + 箭头 + onToggle），所以「承诺可折叠」的扫描
/// 必须把组件文件也覆盖到，否则守卫会形同虚设。
///
/// 排除 `class NeuSection` 的定义与构造函数声明（那不是调用）。
List<String> neuSectionTitles(String src) {
  final out = <String>[];
  for (final m in RegExp(r'NeuSection\(').allMatches(src)) {
    final before = src.substring(0, m.start);
    final lineStart = before.lastIndexOf('\n') + 1;
    final line = src.substring(lineStart, m.start);
    if (line.contains('class ') || line.contains('const ')) continue;
    final args = argumentsOf(src, m.end - 1);
    final arg = args.firstWhere(
      (a) => a.trimLeft().startsWith('title:'),
      orElse: () => '',
    );
    if (arg.isEmpty) continue;
    final title = arg.trim().substring('title:'.length).trim();
    // 只收能静态比对的键（`I18n.t('...')` 或 `'...'`）。
    // 传变量（如 `title: title`）的组件由它自己对内负责配对 —— 静态测试
    // 无法知道运行时会传什么进来，硬管只会误报。
    if (!RegExp(r"^(I18n\.t\('.*'|'.*')").hasMatch(title)) continue;
    out.add(title);
  }
  return out;
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
  // 两种写法都要认：
  //   · 页面里直接查父级 Set：`_expanded.contains(<KEY>)`
  //   · 组件里收的是回调：`isOpen(<KEY>)`
  //     （外观分组搬进 settings/appearance_section.dart 之后用的就是这种，
  //      门控跟着一起搬走了 —— 所以搜索范围也必须包含组件文件）
  final pattern = RegExp(
    r'(?:_expanded\.contains|isOpen)\(\s*' + RegExp.escape(key) + r'\s*,?\s*\)',
  );
  return pattern.hasMatch(src);
}

/// 显式 `stateKey: 'x'` 的取值。
List<String> stateKeys(String src) =>
    RegExp("stateKey:\\s*('[^']*'|\"[^\"]*\")")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toList();

/// 每个页面与为它抽出的组件文件 —— 「分组头」现在住在各自的组件文件里。
///
/// 必须**成对**：组件里的 `NeuSection(title: KEY)` 承诺可折叠，
/// 对应的门控 `_expanded.contains(KEY)` 只在该页面的源码里。
/// 拿 A 页的组件去 B 页找门控必然找不到，所以不能写成一个大列表。
const pages = <String, ({String page, List<String> companions})>{
  '设置页': (
    page: 'lib/ui/server/settings_page.dart',
    companions: [
      'lib/ui/server/settings/widgets.dart',
      // 外观分组 2026-10-09 从页面搬到了这里：门控也一并搬成了 `isOpen(...)`
      'lib/ui/server/settings/appearance_section.dart',
    ],
  ),
  '连接页': (
    page: 'lib/ui/server/conn_page.dart',
    companions: ['lib/ui/server/conn/widgets.dart'],
  ),
  'AI 配置页': (
    page: 'lib/ui/server/config_page.dart',
    companions: ['lib/ui/server/config/widgets.dart'],
  ),
};

void main() {
  pages.forEach((label, spec) {
    group('$label（${spec.page}）', () {
      late String src;

      setUpAll(() {
        src = File(spec.page).readAsStringSync();
      });

      test('每个分组头的键都出现在 _expanded.contains(...) / isOpen(...) 里', () {
        // 「承诺可折叠」现在有三种落点，都要看，否则拆完组件守卫就形同虚设：
        //   · 页面里的 `_section(t, <KEY>, ...)`（老写法，还剩少量）
        //   · 组件里的 `_section(<KEY>, ...)`（搬出去后少了一个 t 参数）
        //   · 组件的 `NeuSection(title: <KEY>, ...)`
        final keys = <String>{};
        final sources = <String, String>{spec.page: src};
        for (final path in spec.companions) {
          if (!File(path).existsSync()) continue;
          sources[path] = File(path).readAsStringSync();
        }
        for (final s in sources.values) {
          for (final call in sectionCalls(s)) {
            // 显式给了 stateKey 的分组，门控键就是 stateKey、与标题无关
            // （标题里带计数，不能拿来当键），交给下面那条测试管。
            if (call.stateKey == null) keys.add(call.title);
          }
          keys.addAll(neuSectionTitles(s));
        }

        expect(keys, isNotEmpty, reason: '一个分组头都没解析到，说明解析逻辑失效了');

        // 门控可能在页面里（`_expanded.contains`），也可能跟着组件一起搬走（`isOpen`）
        final missing = keys
            .where((k) => !sources.values.any((s) => hasGate(s, k)))
            .toList();

        expect(
          missing,
          isEmpty,
          reason:
              '这些分组的标题会画箭头、却没有配套的折叠判断，'
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

  test('交给 _expanded 的键必须是翻译值（I18n.t），不是 i18n key 名', () {
    // 背景（真机测出来的 bug，重构时引入）：
    // `_expanded` 里存的是**翻译后的标题**（`I18n.t(key)` 的返回值），不是 key 本身。
    // 重构时在 onToggle 里写成：
    //
    //   const k = 'conn.groupQuick';
    //   _expanded.add(k);
    //
    // 而判定处写的是 `_expanded.contains(I18n.t('conn.groupQuick'))` —— 两个字符串
    // 不相等，于是**点折叠头完全没反应**（箭头一直不翻）。
    //
    // 上面那条「键与门控配对」的测试抓不到它：两边确实出现了同一个 key，
    // 只是**喂给 _expanded 的不是同一个值**。所以单独加这条。
    final files = <String>[
      ...pages.values.map((s) => s.page),
      ...pages.values.expand((s) => s.companions),
    ];
    for (final path in files) {
      if (!File(path).existsSync()) continue;
      final src = File(path).readAsStringSync();
      for (final m in RegExp(
        r"(?:const|final)\s+(\w+)\s*=\s*'([^']+)'",
      ).allMatches(src)) {
        final name = m.group(1)!;
        final used = RegExp(
          r'_expanded\.(?:add|remove|contains)\(\s*' + name + r'\s*[,)]',
        );
        if (used.hasMatch(src)) {
          fail(
            '$path 里 `$name` 被赋成字面量 "${m.group(2)}" 之后交给了 _expanded —— '
            '_expanded 存的是**翻译值**，应该用 I18n.t(...)。',
          );
        }
      }
    }
  });

  test('连接页的两个分组确实被门控（审计点名的那两个）', () {
    final src = File('lib/ui/server/conn_page.dart').readAsStringSync();
    // conn.groupManual（「手动配置」那块表单）已经不在连接页内联了 ——
    // 它搬进了独立的 ConnEditPage 子页面，所以不再是折叠分组、也不需要门控。
    for (final key in [
      "I18n.t('conn.groupQuick')",
      "I18n.t('ui.f8dfedcd8a')",
    ]) {
      expect(
        hasGate(src, key),
        isTrue,
        reason: '$key 的内容没有包在 if (_expanded.contains(...)) 里',
      );
    }
  });
}
