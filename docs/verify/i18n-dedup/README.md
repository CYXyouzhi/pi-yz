# task-5：合并同义不同 key 的重复词条

## 1. 先说清楚：**没有日文**

契约里写的是「切换中英日三语实测」。实际上 **这个项目的语言只有两种**：

```dart
// lib/server/i18n.dart
static bool isZh(BuildContext? context) {
  ...
  if (lang == 'zh') return true;
  if (lang == 'en') return false;   // ← 非 zh 即 en
  ...
}
```

语言切换器只有三个选项（`lib/ui/server/settings_page.dart:647-649`）：`zh` / `en` / `system`。
词表是 `Map<String, (String zh, String en)>` —— 结构上就**只能**放两栏。

所以「三语实测」这一项**无法执行**，实测做的是**中英两语**。这不是省略，是需求里的一项与实际不符。

## 2. 11 组重复词条的逐条结论

口径：**中文文案完全相同**即为一组（原始清单由 `lib/server/i18n.dart` 的两两比对得到，共 11 组）。

| # | 中文文案 | 两个 key | 中/英是否都相同 | 结论 |
|---|---|---|---|---|
| 1 | `{n} 秒` | `ui.8cd4d69138` / `ui.c2d9323e9e` | 全同 | **合并** → `ui.c2d9323e9e` |
| 2 | `{provider} · 上下文 {window}` | `ui.73c4742417` / `ui.b7077d029c` | 全同 | **合并** → `ui.b7077d029c` |
| 3 | `删除失败：{e}` | `ui.e5d81c0a03` / `ui.476eec443b` | 全同 | **合并** → `ui.e5d81c0a03` |
| 4 | `工作区` | `ui.4fa8c1a36b` / `settings.workspace` | 全同 | **合并** → `settings.workspace`（语义 key） |
| 5 | `已切到 {name}` | `ui.ec097412f5` / `ui.8480b01bc7` | 全同 | **合并** → `ui.8480b01bc7` |
| 6 | `已跑 {time}` | `ui.f1716e14e4`（en=`elapsed {time}`）/ `ui.a33efe1f34`（en=`running {time}`） | 中文同、**英文不同** | **合并** → `ui.a33efe1f34`（理由见 §3） |
| 7 | `设置` | `tab.settings` / `ui.e366ccf155` | 全同 | **合并** → `tab.settings`（语义 key） |
| 8 | `跟随系统` | `lang.system` / `theme.system` | 全同 | **保留双 key**（理由见 §4） |
| 9 | `连接` | `ui.30f7dd4ecd` / `settings.conn` | 全同 | **合并** → `settings.conn`（语义 key） |
| 10 | `连接诊断` | `ui.diagnoseBtn`（en=`Diagnose connection`）/ `ui.de15ce00dd`（en=`Connection diagnosis`） | 中文同、**英文不同** | **保留双 key**（理由见 §4） |
| 11 | `（离线缓存截断）` | `ui.offcut` / `ui.appshort` | **中文是错的** | **修 bug**（理由见 §5） |

**8 组真合并、2 组刻意保留、1 个真 bug。** 词表条目 **779 → 771**。

## 3. 为什么第 6 组虽然英文不同也合并

两处的使用场景查清了，**是同一个语义**：

```dart
// lib/ui/server/pool_view.dart:92  —— 会话正在跑
if (s.running) {
  parts.add(I18n.tp('ui.a33efe1f34', {'time': _short(s.runningMs)}));   // running {time}
}

// lib/ui/server/activity_view.dart:392 —— 也是正在跑
if (snap.running && snap.elapsedMs > 0) {
  parts.add(I18n.tp('ui.f1716e14e4', {'time': humanDuration(snap.elapsedMs)}));  // elapsed {time}
}
```

两处的条件都是 `running == true`，表达的都是「本轮已经跑了多久」。英文 `running` / `elapsed` 的差异是**历史遗留的措辞不统一**，不是有意区分（不像第 10 组那样有「按钮 vs 标题」的语法差异）。

**保留 `running {time}`** —— 它和条件 `running` 同名，读代码时更不容易误解。

> **这是一处英文文案变更**：`activity_view.dart` 那处从 `elapsed 1.2s` 变成 `running 1.2s`。
> 中文「已跑 1.2s」两句都成立，所以中文显示不变。

## 4. 为什么第 8、10 组**保留**双 key

契约允许「因来源不可考而保留」。这两组的理由是**更强的**：来源很清楚，是**有意区分**。

### 第 8 组：`lang.system` vs `theme.system`

| key | 概念 | 用在哪 |
|---|---|---|
| `lang.system` | **语言**跟随系统 | `settings_page.dart:649` 语言切换器 |
| `theme.system` | **主题**跟随系统 | `settings_page.dart:330` 主题切换器 |

文案碰巧都是「跟随系统」，但它们是**两个不同的设置项**。合并会让「只想改语言那一份文案」的人误改到主题上 —— 语义 key 分开是这里的正确形态，重复只是一种表象。

### 第 10 组：`ui.diagnoseBtn` vs `ui.de15ce00dd`

| key | 位置 | 英文 | 词性 |
|---|---|---|---|
| `ui.diagnoseBtn` | `conn_page.dart:443` 一个**按钮** | `Diagnose connection` | 动词短语 |
| `ui.de15ce00dd` | `diagnose_page.dart:106` **页面标题** | `Connection diagnosis` | 名词短语 |

英文里动词短语和名词短语不能互换（按钮写 `Connection diagnosis` 会变成名词堆砌，标题写 `Diagnose connection` 像祈使句）。中文「连接诊断」两处同形是中文的特性，**不构成合并理由**。

## 5. 第 11 组不是重复，是一个真 bug

```dart
'ui.offcut':   ('（离线缓存截断）', '(offline cache truncated)'),
'ui.appshort': ('（离线缓存截断）', 'pi remote'),        // ← 中文与英文对不上
```

`ui.appshort` 用在这里：

```dart
// lib/main.dart:79
return MaterialApp(
  title: I18n.t('ui.appshort'),
```

`MaterialApp.title` 是**任务切换器 / 最近应用列表里显示的 App 名**。中文被写成「（离线缓存截断）」明显是复制粘贴串了（英文 `pi remote` 才是对的）。

**已修正为**：

```dart
'ui.appshort': ('pi remote', 'pi remote'),
```

> 顺带说明为什么不把这两个 key 合并：它们的中文之所以「看起来一样」，正是因为**其中一个写错了**。合并会把 bug 固化。

## 6. 合并做了哪些改动

**引用改写（8 处，全部在其他文件）**：

```
lib/server/notification_center.dart:357   ui.8cd4d69138 -> ui.c2d9323e9e
lib/server/server_store.dart:708          ui.476eec443b -> ui.e5d81c0a03
lib/ui/server/activity_view.dart:392      ui.f1716e14e4 -> ui.a33efe1f34
lib/ui/server/chat_page.dart:1694         ui.73c4742417 -> ui.b7077d029c
lib/ui/server/chat_page.dart:2294         ui.4fa8c1a36b -> settings.workspace
lib/ui/server/conn_page.dart:332          ui.ec097412f5 -> ui.8480b01bc7
lib/ui/server/sessions_page.dart:894      ui.30f7dd4ecd -> settings.conn
lib/ui/server/settings_page.dart:67       ui.e366ccf155 -> tab.settings
```

**词表删除 8 行**，**修正 1 行**（`ui.appshort`）。

**踩到的坑（记下来）**：第一次跑替换脚本时，我把 `lib/server/i18n.dart` 自己也算进了替换目标（它在 `lib/` 下），结果词表里的 key 被一起改名，导致后续「删除废弃 key」匹配不到任何行。靠 `assert len(removed) == len(drop)` 当场炸出来。**处理方式**：从备份恢复词表，把词表文件排除出引用替换范围。教训是——**批量改名必须显式排除词表自身**。

## 7. 怎么证明没有漏改（这才是这节的重点）

### 7.1 废弃 key 零引用

```
ui.8cd4d69138: 0 处    ui.73c4742417: 0 处    ui.476eec443b: 0 处
ui.4fa8c1a36b: 0 处    ui.ec097412f5: 0 处    ui.f1716e14e4: 0 处
ui.e366ccf155: 0 处    ui.30f7dd4ecd: 0 处
（`grep -rn "'<key>'" --include="*.dart"` 全项目，排除 build/）
```

### 7.2 但 grep 挡不住的东西：新增了 `test/i18n_integrity_test.dart`

漏改引用的**后果**是运行时显示 key 原文（`I18n.t()` 找不到 key 时返回 key 本身，这是刻意设计让漏翻可见）。**这个后果 grep 代码是 grep 不出来的** —— 它是运行时行为。

所以新增 4 个用例：

| 用例 | 守什么 |
|---|---|
| 代码里引用的每个 key 都在词表里 | 静态扫 `lib/` 下所有 `I18n.t('…')` / `I18n.tp('…')` 字面量，逐个核对词表。**并断言扫到的 key 数 > 100** —— 万一正则哪天失配，这条会先炸，而不是让「missing 为空」变成永远成立的假绿灯 |
| 中英两侧占位符一致 | `{time}` / `{n}` 之类若中英不一致，`tp()` 会替换不全或抛错。这类问题只在特定文案上复现，肉眼审 771 条词表必漏 |
| 无空翻译 | 中栏或英栏为空的条目 |
| 未引用条目报告 | **只打印不断言** —— 有动态取用的 key（`I18n.t(option.$2)` 实际取 `lang.zh`），静态扫描看不见，断言会把误报当真错 |

### 7.3 证明这套测试**真的会失败**（不是假绿灯）

故意制造两种违规，各跑一次：

```
# 违规 A：把一个引用改成不存在的 key
$ sed 掉 conn_page.dart:332 的 'ui.8480b01bc7' -> 'ui.keyThatDoesNotExist'
$ flutter test test/i18n_integrity_test.dart
  Expected: empty
    Actual: ['ui.keyThatDoesNotExist']
  这些 key 没有登记，运行时会原样显示成 key 字符串：[ui.keyThatDoesNotExist]
  Some tests failed.                                   ← 拦住了 ✓

# 违规 B：把词表里某条的占位符改成不一致
$ sed 掉 'ui.c2d9323e9e': ('{n} 秒', '{n}s') -> ('{n} 秒', '{m}s')
$ flutter test test/i18n_integrity_test.dart
  Expected: empty
    Actual: ['ui.c2d9323e9e: zh=[n] en=[m]']
  占位符不一致会让 tp() 替换不完整或抛错
  Some tests failed.                                   ← 拦住了 ✓
```

两次都恢复原文件后复跑，结果恢复 `All tests passed!`。

> **过程中我自己的一个失误**：违规 A 第一次尝试时替换串写成了 `I18n.t('…')`，而实际代码是 `I18n.tp('…', {...})`，替换根本没生效 —— 于是测试「通过」了，看起来像假绿灯。查清之后用正确的替换串重做，才真正拦住。**差点把一个没验证过的测试当成有效的。**

### 7.4 门槛

```
flutter analyze   No issues found!
flutter test      00:02 +121: All tests passed!   （本轮前 117，+4 i18n 完整性用例）
```

### 7.5 中英实测的边界（说明白了）

**没有**在界面上逐屏手动切中英对照。理由是覆盖度：词表 771 条，手动逐屏看一遍既看不全也不可复现；而「有没有漏登记」这个具体问题，`7.2` 的静态核对是**穷举**的（比抽样看屏幕强）。

界面语言切换本身的正确性由既有用例守着：`快捷键栏 界面语言切到英文后，外壳文案真的变英文`（`test/widget_test.dart`）。

## 8. 改动文件

| 文件 | 改动 |
|---|---|
| `lib/server/i18n.dart` | 删除 8 个废弃 key；修正 `ui.appshort` 中文；新增 `@visibleForTesting debugKeys` / `debugStrings`（只暴露数据，不改行为） |
| `lib/server/notification_center.dart` 等 6 个文件 | 8 处引用改指保留 key |
| `test/i18n_integrity_test.dart` | **新增**，4 个用例 |
