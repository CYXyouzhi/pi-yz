# 大文件拆分：进度与约定

面向：接手这件事的下一轮对话（含压缩后的我自己）。

## 为什么要拆

`chat_page.dart` 3374 行、`server_store.dart` 1814 行 —— 改一处要在几千行里翻，
容易漏。起因是主人原话：「把该拆的都拆一下，不然容易出问题」。

## 拆法（已定：A 路线）

**重构成无状态组件**，不用 `part` 分文件。

理由：`part` 只是搬家，类的复杂度不变；抽成组件才是真解耦（可传参、可单测、可复用）。
代价是每个组件要设计传参并改调用点，工作量大 —— 已知情并接受。

**状态归属约定**（这是抽分组时的关键决策）：

> **状态留在父级 State**，子组件只收 `open` + `onToggle`。

以设置页为例：8 个分组共用一个 `Set<String> _expanded`，抽出去的组件不自己持有它，
只接收「我展开了吗」和「点了要干什么」。这样改动最小，也不用动嵌套逻辑
（「外观」分组里还嵌着三个子分组）。

## 进度

| 文件 | 行数（拆前）| 状态 |
|---|---|---|
| `lib/server/server_types.dart` | 1268 | ✅ 完成 |
| `lib/ui/server/settings_page.dart` | 1472 | ✅ 875 行（8 个分组抽了 7 个；「外观」未能抽出，原因见「踩过的坑⑤」）|
| `lib/ui/server/config_page.dart` | 1307 | ✅ 811 行（6 个分组抽了 5 个；MCP 分组未抽）|
| `lib/ui/server/files_page.dart` | 1059 | ✅ 645 行（6 个组件 + 2 个工具函数 + 2 个底部面板）|
| `lib/ui/server/sessions_page.dart` | 1316 | ✅ 1103 行（5 个组件已抽；`_buildSessionRow`/`_buildGroup` 是雷区，不抽）|
| `lib/ui/server/conn_page.dart` | 1300 | ✅ 1209 行（3 个组件已抽；`_remoteCard` 待手工加参数）|
| `lib/ui/server/chat_page.dart` | 3374 | 🚧 3374 → 3237 行（4 个组件已抽；余下待续）|
| `lib/server/server_store.dart` | 1814 | 🚫 **不动**（「唯一状态源」是架构决策的载体，拆它等于动地基）|

相关提交：`6138d6d`（server_types）、`8424632`（设置页共用件）

## 已完成的两步做了什么

### 1. `server_types.dart`：barrel 拆法（纯数据，零风险）

41 个类 → 按领域拆 6 个文件，**原文件保留为 barrel（只 export）**，
于是 16 个 `import 'server_types.dart'` 的调用方一行不用改。

```
lib/server/server_types.dart      15 行（barrel）
lib/server/types/messages.dart   220 行  PiText/PiThinking/PiToolCall/PiImage/PiUsage/PiMessage
lib/server/types/session.dart    213 行  ServerSession/ModelInfo/SessionSnapshot/ServerEvent/CommandResponse
lib/server/types/files.dart      213 行  FileEntry/DirListing/FileText/Git*/FileRef/RawFileData/WorktreeInfo/ExportMarkdown
lib/server/types/usage.dart      287 行  SessionStats/HealthInfo/Usage*
lib/server/types/config.dart     244 行  McpServerInfo/CredentialInfo/Pi*PackageInfo/Auth*/ProviderInfo/LoginStatus
lib/server/types/pool.dart       224 行  PoolSession/Disk*/RemoteState
```

分组依据是先跑的依赖分析：30 个类零依赖，另 10 个的依赖都落在同一领域内
（`PiUsage→PiText`、`DiskUsage→DiskGroup→DiskSession`），没有交叉。

**这个方案对纯 DTO 很合适，但只适用于纯数据文件** —— 页面文件没法这么做。

### 2. `settings_page.dart`：抽出共用件，解开后续的死结

抽分组的第一个障碍是共用件：`_section`（读 `_expanded` + 调 `setState`）
和 `_infoRow`（纯渲染但挂在 State 上）。不先解决它们，任何分组都抽不动。

```
lib/ui/server/settings/widgets.dart   97 行
  · SettingsSection —— 无状态的折叠标题壳，收 open + onToggle
  · InfoRow         —— 「标签 —— 值」一行
```

`settings_page.dart` 里的 `_section` 保留为薄包装（继续读 `_expanded` + `setState`），
所以 8 个调用点一行没改 —— 等分组真正抽出去时再用真正的 `SettingsSection`。

## 下一步（从这里继续）

**`settings_page.dart` 的 8 个分组**，按这个模式抽：

```dart
// lib/ui/server/settings/<name>_section.dart
class XxxSection extends StatelessWidget {
  const XxxSection({
    super.key,
    required this.store,        // 需要的数据
    required this.open,         // 我展开了吗（父级给）
    required this.onToggle,     // 点了要干什么（父级给）
    // …这个分组特有的回调，例如 onOpenConn / onThemeModeChanged
  });
  // 无状态：不持有任何字段，只渲染
}
```

分组的行号与标题（**改前**的行号，抽出后要重新定位）：

| 行 | i18n key | 说明 |
|---|---|---|
| 81 | `settings.conn` | 连接 |
| 208 | `settings.workspace` | 工作区（含「文件浏览」「存储占用」，AI 配置已提到顶层）|
| 360 | `settings.appearance` | 外观 —— **里面嵌了三个子分组** |
| 406 | `ui.066ae8d7d6` | （外观的子分组）|
| 468 | `ui.5660bcd256` | （外观的子分组）|
| 686 | `settings.language` | （外观的子分组，语言）|
| 738 | `settings.app` | App 设置（约 240 行，最大的一块）|
| 981 | `settings.about` | 关于 |

其余 helper：`_prefLabel`、`_notifToggle`、`_prefChips`、`_prefRow`、`_pickStuckSeconds`、
`_testNotification`、`_pickDefaultWorkspace`、`_pickDefaultModel`、`_clearLocalData`
—— 都可以按同样思路抽成无状态组件 + 顶层函数。

## 硬约束（每步都不能破）

1. **纯重构，不改行为** —— 用户看到的东西必须一模一样
2. **每个文件完成后跑全量门禁**：`flutter analyze`（期望 0 issue）+ `flutter test`（期望 169 全过）
   —— 不许攒到最后一起验证
3. **不许弄坏现有测试**；新增测试可以，但要单独提交
4. **不碰 `server_store.dart`**
5. **中文注释**；改判定逻辑的地方要写清「为什么」，不只写「做了什么」

## 踩过的坑（下轮别再踩）

**① 顶层函数不是类**

拆 `server_types.dart` 时，脚本按 `class` 切分，把**顶层函数** `parseTimestamp`
随机归进了 `pool.dart`，而 `messages.dart` 的 `PiMessage` 要用它 —— 编译才暴露。
**教训**：切分前先 `grep` 一遍非 class 的顶层声明。

**② barrel 会留下悬空的文档注释**

`ServerSession` 的 `///` 注释被切分时留在了 barrel，变成悬空的 library doc comment
（analyze 报 `dangling_library_doc_comments`）。
**教训**：切完后检查每个类的文档注释有没有跟着走。

**③ 删 unused import 的脚本别再犯**

我在 Python 里写了 `//` 注释（那是 Dart 的），又把脚本里带反斜杠的字符串塞进
bash heredoc 被吃掉转义 —— 都浪费了一轮。
**教训**：复杂转义就写成脚本文件再跑（这条 `AGENTS.md` 里本来就有）。
现成工具：`tool/fix-unused-imports.py`。

**④ 抽样验证不能省**

我曾写个检测器报「26 个方法完全不依赖状态」，抽样一看全是错的 ——
检测器只认字段的**声明形式**，漏了 `late`/通过 widget 赋值的成员（`_store`、`_runStartedAt`）。
**教训**：机械扫描的结论必须抽样核实，别直接拿去用。

**⑤ 抽「外观」分组反复失败四次，最后放弃**

`settings_page.dart` 里其余 7 个分组都抽成了，只剩「外观」（367 行，内含三个嵌套子分组）卡住。
用「提取区间 → 包 class 外壳 → 替换调用点」的脚本反复试，每次都坏：

1. 区间边界用 `SizedBox(height: NeuSpace.n20)` 找 —— 但外观**内部就有多个**这个标记，
   于是切早/切晚；有一次把后面的 `AppSection`、`AboutSection` 调用也卷进了组件。
2. 尾部括号重建错位：`return Column` 的收尾和 class 的收尾混在一起，补几次都不对。
3. 改用「下一个方法定义」作边界 —— 正则匹配到了**注释行**与**参数换行**，
   只摘到 1 行签名，方法体还留在原处（编译器报 unused_element）。
4. 最后从 `git show HEAD:` 取原方法时行号对不上（HEAD 与我以为的版本不同），
   取到 575 行，把 `_pickDefaultWorkspace` / `_pickDefaultModel` 也塞进组件，
   组件文件被撑到 1011 行。

**教训**：
· 388 行、含嵌套子分组的搬运，**脚本化的收益抵不过出错成本**。
  应该改用「逐块手工搬」（每次 30~60 行，搬完立刻 analyze）。
· 区间边界不要用「某个标记的行号」（可能有多处），要用**语义上唯一**的锚点
  （如「下一块的开头」）。
· **同一个操作失败两次以上就该换方法** —— 这次试了四次，浪费很多轮次。
· 失败时及时 `git checkout` 回到干净点，比在现场修补更省事
  （我修补过两次，都越修越乱）。

**⑥ 用脚本抽分组：能用，但要挑对象**

为配置页写了 `tool/extract_config_section.py`（自动推导参数 + 替换调用点），
确实省了打字 —— 5 个分组抽完，文件从 1307 降到 811 行。但它的失效边界很清楚：

  · **最后一个分组**不能抽 —— 它后面没有下一个 `_section` 可作终点，
    脚本的兜底逻辑撞出负数区间，产出空文件（第一次跑 MCP 分组就是这样）。
  · 改成用「children 的收尾」兜底后能跑，但**含嵌套子分组或回调较多**时
    又会把边界算偏，产出结构错误的文件（第二次跑 MCP，报 expected_class_member）。
  · 方法**引用**（`onTap: _loginProvider,` 不带括号）不会被 `_foo(` 替换命中 ——
    改了三轮才发现。
  · 生成的字段声明**漏类型**，analyze 会报几十条 info 级问题
    （strict_top_level_inference + 在 dynamic 上访问成员）。

**结论**：这类脚本适合「单个、无嵌套、回调少」的分组；碰到嵌套或最后一个分组，
**手工搬更快**。而且跑完必须逐项核对（实参名、回调、类型、import），
analyze 干净之前都不算完成。

**两次失败都及时 checkout 回退了** —— 这比在现场修补省事得多（修补过一次，越修越乱）。

**⑦ sessions_page 失败六次仍未完成 —— 这个文件只能用脑，不能用脚本**

`sessions_page.dart`（1316 行）试了五次，每次都在同一个坑里打转，最后全部回退：

  · **方法签名是多行的**：
    ```
    Widget _buildGroup(
      NeuTokens t,
      String cwd,
      ...
    ) {
    ```
    第一版脚本按「去掉 body 的第 1 行」剥签名 → 参数列表残留进组件 →
    报 103 个 expected_class_member / already defined。
    改成按「签名结束的 `) {`」定位后单这个方法能过了（SessionRow / SessionGroup 实测干净）。
  · **同文件里多个 class 的构造签名文本完全相同**（SessionRow 与 SessionGroup 都有
    `required this.onOpen, required this.onLongPress`），我用 `str.replace` 加字段时
    命中了错的那个 → 报 67 个「All final variables must be initialized」。
  · 脚本自己还引入两处：多加一个 `return`（原方法体本来就有）、
    `setState` 要改走回调、`widget.onXxx` 要加参数。

**结论：这个文件应当手工搬。** 它有四个特征叠在一起，脚本「猜」的成本高于人「看」的成本：
  1. 方法签名多行；
  2. 多个 class 结构高度相似（替换会命中错的那个）；
  3. 方法体内混着 `setState`、`widget.xxx`、跨方法调用三类需要逐个判断的引用；
  4. 单个方法 58~94 行，手工搬也不算太长。

**下次的做法**：一次只搬一个方法，用 edit 工具（精确匹配，不匹配就拒绝），
搬完立刻 analyze；先读 30 行看清引用类型，再决定传参还是回调。

**教训**：五次失败里我每次改的都是**不同的点**，但每次「改完 analyze 仍有几十条」就回退 ——
其实从第三次起就该换方法了。**同一个文件失败两次，就该停下来改用手工。**

**⑦ 补充：六次尝试的完整记录与结论**

（上一节写了前五次的四个原因。第六次是手工替换 `_buildRow` 的 switch 分支时踩的 ——
那一段分支密集，`EmptyStateView(store: _store),` 与相邻分支对不上，报 46 个结构错误。）

**未能完全归因的一点**：过程中换行符出现过不一致 —— 我的脚本写文件用 LF，
而读入的可能是 CRLF，`cat -A` 一度看到行尾 `^M$`。但回退后确认原始文件是 LF，
所以**不能断定 CRLF 是那些「替换没生效」的原因**。唯一能说的：脚本读写时统一换行符
是无害的好习惯，值得加。

**结论：这个文件应当手工做，不要用脚本。** 它有四个特征叠在一起：
  1. 方法签名多行；
  2. 多个 class 结构高度相似（`str.replace` 会命中错的那个）；
  3. 方法体混着 `setState`、`widget.xxx`、跨方法调用、switch 表达式四类需要逐个判断的东西；
  4. 单个方法 58~94 行，手工搬也不算太长。

**最重要的教训不是技术性的**：六次失败里，每次我改的都是**不同的点**，
但每次都「改完 analyze 仍有几十条」就回退。**从第三次起就该换方法了** ——
这六轮的成本远超「一开始就手工搬」。下次遇到同类情况：
同一个文件失败两次，立刻停手换方法。

**⑦ 补充二：第七次（换新方法后，四次成功一次卡住）**

第六次之后我换了方法：**提取用脚本、改调用点用 edit 工具**（edit 要求精确匹配，
不匹配就拒绝 —— 不会像 `str.replace` 那样命中错的地方）。这个方法**先成功了四次**：

  EmptyStateView → ConnCard → ArchiveEntryRow + NewSessionRow → SessionSearchBar

`flutter analyze` 每次都是零问题，文件从 1316 降到 1099 行。**说明方法是有效的。**

第五次抽 `_buildSessionRow` 时出现结构错误：
`sessions_page.dart:691 - Expected to find ';'`，并级联出 36 个错误
（其中 `Undefined name 'context' / '_store' / 'mounted'` 都是它的副作用 ——
解析器把后面的方法当成了类外的东西）。

**没定位成功**：691 行本身看着正常（`_EmptyRow() => EmptyStateView(store: _store),`），
`EmptyStateView` 的定义也正常。怀疑与 `_buildRow` 那个 **switch 表达式**的分支结构有关
（9 个分支、含 Dart 3 的 object pattern `_GroupRow(:final cwd, ...)`）。

**下一轮的建议**：把 `_buildRow`（约 56 行、9 个 switch 分支）**跳过不抽** ——
少减 56 行，但避开这个雷区。其余独立方法继续用「脚本提取 + edit 改调用点」的做法。

**⑦ 补充三：第 8 次 —— 新方法一次成功抽出 5 个，但 `_buildSessionRow` 是雷区**

第 7 次换的方法（**提取用脚本，改调用点用 edit 工具**）确实有效：
**一次成功抽出 5 个组件**，1316 → 1103 行，analyze 零问题，已提交（`9e040f9`）。

```
sessions/widgets.dart（新建）
  EmptyStateView / ConnCard / ArchiveEntryRow / NewSessionRow / SessionSearchBar
```

但抽 `_buildSessionRow` **两次都撞上同一个错**：
`sessions_page.dart:691 - Expected to find ';'`，级联 37 个错误。

**查不出来**：691 行本身完全正常（`_EmptyRow() => EmptyStateView(store: _store),`），
`SessionRow` 与 `EmptyStateView` 的定义也都正常，`_buildSessionRow` 也没有残留引用。
像是**误报位置**，真病灶在别处 —— 两轮都没定位到。

**结论：`_buildSessionRow` 与依赖它的 `_buildGroup` 一起列为雷区，不抽。**
少减约 121 行，但避开两次都栽的地方。

**sessions_page 的现状**：1316 → **1103 行**（减 213），5 个组件已抽出并提交。
未达 800，差的就是那两个雷区方法 —— 但它已经比原状好，不值得再耗轮次。

**下一轮直接从步骤 5（conn_page）开始。**

**⑧ conn_page 停在 1209 行；「文本替换命中错 class」第 3 次出现**

步骤 5 的进展：1300 → **1209 行**（减 91），3 个组件已抽出并提交
（`CmdRow` / `TunnelOption` / `OwnToolSection`，见 conn/widgets.dart）。

`_remoteCard`（208 行）没抽成。它依赖 5 个页面成员（store / tunnelPref / ownRemote /
saveOwnAddress / showThreat）与 3 处 setState，加参数时**又一次踩了同一个坑**：
用 `str.replace` 给 `RemoteCard` 加字段，**命中了文件里另一个 class（CmdRow）**，
于是 `CmdRow` 多了三个用不上的字段、`RemoteCard` 一个都没加上。

**这是同一个错误第 3 次出现**（前两次分别在 settings_page 和 sessions_page）。
规律很清楚：

> **当一个文件里有多个结构相似的 class 时，`str.replace` 一定会命中错的那个。**

凡是给某个 class 加字段/参数，**必须先定位到那个 class 的行范围**，只在范围内替换；
或者直接用 edit 工具 —— 它要求精确匹配，不匹配就拒绝，不会静默改错地方。

**下一轮**：`_remoteCard` 用 edit 手工加参数（一个 class 一段，不批量 replace）；
之后是步骤 6（chat_page，3374 行）。

**⑨ chat_page：第一轮就撞上重名**

步骤 6 才开始就踩到两件事，已回退，chat_page 保持 3374 行：

1. **`ActivityBar` 重名** —— `activity_view.dart` 里已经有一个同名类，
   analyze 报「ActivityBar 定义在两个库里」。**抽组件之前应该先 grep 一遍名字是否被占用。**
2. **参数靠猜吃了亏** —— `_buildActivityBar` 实际要用 `snap` / `sessionName` /
   `runStartedAt` / `compact` / `onTap`，我按 `store` + `chat` 猜了一组，
   然后来回补了三轮才接近，最后撞上重名。

**下一轮的做法**：
  · 抽之前 `grep -n "^class " lib/ui/server/*.dart | grep -i <组件名>` 确认不重名，
    重名的加前缀（如 `ChatActivityBar`）；
  · 参数不要猜：先按最小集生成，让 analyze 报「缺哪个」再补 —— 比先猜一组再改快。

**⑩ chat_page 分批推进；批量替换第 4 次改错地方**

**第一批成功**（已提交 `ea9f79a`）：`ChatActivityBar` / `LoadMoreRow` / `OfflineBanner` /
`ChatEmptyState`，3374 → 3237 行。

上一轮记的两条教训都奏效：
  · **先查重名** —— grep 出所有 class 名，发现 `ActivityBar` 被 `activity_view.dart` 占用，
    于是加 `Chat` 前缀。上一轮就是栽在这里。
  · **参数按最小集** —— 只给 `store`（需要 `chat` 的两个再补），让 analyze 报缺什么再补。
    上一轮猜一组来回三轮，这轮一次到位。

**第二批失败**：`ChatLoading` / `LiveSpeed` / `ModelChip` 提取成功（降到 3111 行），
但修 `ModelChip` 时用 `re.sub(r'model(?!Chip)', 'chat.model', ...)` 改引用，
**把不该改的地方也改了**（`chat.model` 被改成 `chat.chat.model`），报 10 个错误。已回退。

**这是同类错误第 4 次**（前三次在 settings / sessions / conn）。规律已经确定：

> **批量替换（`str.replace` / `re.sub`）在有歧义的文件里一定会改错地方。
> 唯一可靠的是 edit 工具 —— 它要求精确匹配，不匹配就拒绝。**

**下一轮**：`ModelChip` 里 `model` → `chat.model` 的改动，用 edit 一次一处地做；
之后继续 `_buildUndoBar` / `_buildPendingImages` / `_buildFileRefs` / `_buildSuggestions` /
`_buildTurnFooter` / `_buildHeader` / `_buildComposer`。

**结果**：`settings_page.dart` 停在 **875 行**（原 1472，减 597 行 / 40%），未达 800 目标。
差的就是「外观」这 367 行。它仍作为整体留在页面里 —— 至少是**自洽**的
（三个子分组都在它内部），不是散落状态。
