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

| 文件 | 行数（拆前，format 前口径）| 现在 | 状态 |
|---|---|---|---|
| `lib/server/server_types.dart` | 1268 | barrel 15 行 + `types/` 6 文件 | ✅ 完成 |
| `lib/ui/server/settings_page.dart` | 1472 | **472** | ✅ 全部分组抽完（「外观」2026-10-09 抽成 `settings/appearance_section.dart`，见成功经验⑦）|
| `lib/ui/server/config_page.dart` | 1307 | **669** | ✅ 全抽完（MCP 2026-10-09 抽成 `config/mcp_section.dart`，见坑⑨）|
| `lib/ui/server/files_page.dart` | 1059 | 897 | ✅ 完成 |
| `lib/ui/server/sessions_page.dart` | 1316 | 1249 | ✅ 完成 |
| `lib/ui/server/conn_page.dart` | 1300 | 632 | ✅ 完成 |
| `lib/ui/server/chat_page.dart` | 3374 | **1157** | ✅ 完成（余下见 ⑱）|
| `lib/server/server_store.dart` | 1814 | 1953 | 🚫 **不拆**（「唯一状态源」是架构决策的载体，拆它等于动地基）|
| `lib/ui/server/chat/widgets.dart` | 2655 | **26（barrel）** | ✅ 2026-10-09 拆成 9 个文件，调用点 0 改动（见成功经验⑧）|

**行数口径变了，别直接相减**：2026-10-09 全仓 `dart format` 之后，长行被折成多行，
所有文件都涨了 10~30%（例：settings_page 875 → 990，抽掉外观后才到 472；
server_store 1814 → 1953）。所以「拆前」与「现在」两列的差值**不是**重构收益。
收益看的是另一个指标：**改一个分组要动多少行**。

相关提交：`6138d6d`（server_types）、`8424632`（设置页共用件）、`cc33bca`（外观分组）

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

> **2026-10-09 更新**：下面这段是当时写给「抽设置页分组」的，那件事已经做完
> （8 个分组全部抽出，最后一个「外观」的做法见「成功经验⑦」）。
> **现在最大的文件是 `lib/ui/server/chat/widgets.dart`（2655 行）** —— 它是本轮解耦的
> 「抽出物集散地」，里面是十几个互相独立的组件（ChatHeader / ChatComposer / MenuTile /
> ModelChip / 各种 sheet），按同一套约定再分成目录即可。做法参考成功经验⑦。
>
> 另外注意：`docs/` 里所有「行数」记录都是 format 前的旧口径，见上面进度表的说明。

（以下为历史记录）

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

**⑪ chat_page 分批推进有效；抽顶层函数要用另一套边界**

「一块一块做」的节奏确实有效：

| 块 | 行数 | 结果 |
|---|---|---|
| `ChatLoading` | 58 | ✅ `b37943f` —— 两个调用点缩进不同，edit 正好唯一匹配，一次过 |
| `LiveSpeed` | 21 | ✅ `3de70a7` —— 一次过 |
| `ModelChip` | 48 | ✗ 失败（新原因，见下）|

chat_page 3374 → **3158 行**。

**`ModelChip` 这次的失败原因和之前不同**：`modelChipLabel` 是**顶层函数**（顶格写，
无缩进），而我的边界正则 `^  (?://|…)` 要求 **2 空格缩进** —— 它匹配到了**类成员**，
于是边界算到了错误的位置，校验拒绝。

**教训：抽顶层函数要用另一套边界规则**（顶格声明 `^[A-Za-z]`），
`tool/extract_render_method.py` 目前只为「State 里的方法」设计。

**下一轮**：`ModelChip` 与 `modelChipLabel` **手工搬**（脚本的 cut 在这儿会算错边界）。

**⑫ chat_page 走「弹层路线」成功：3374 → 2740 行**

前面三次磨渲染块（`_buildXxx`）全败（`ModelChip` 试了三次）。
改成先抽弹层后，**八个函数一次过**：

| 弹层 | 行数 | 依赖 |
|---|---|---|
| `showUndoSnack` | 14 | 0 |
| `showTurnSummarySheet` | 84 | 0 |
| `showDataSheet` + `formatPayload` | 50 + 16 | 1 |
| `showPickerSheet` | 96 | 1 |
| `askSelect` / `askConfirm` / `askText` | 77 / 27 / 48 | 全 0 |

chat_page **3374 → 2740 行**（减 634 / 19%），新建 `chat/sheets.dart`。

**为什么弹层好抽**：它们是独立函数 —— 有明确的 `) async {` 与收尾 `}`，
边界是语法结构本身；而渲染块嵌在 build 的表达式里，边界靠缩进猜。

**`_modelRow` 失败（唯一没成的）**：签名是
`NeuTokens t, BuildContext sheetContext, StateSetter setSheetState` ——
用了 `StateSetter`，说明它要在弹层内部重建自己。
**这类「和调用方共享可变状态」的方法不能简单搬成无状态组件，跳过。**

**脚本的两个新坑**（处理多行签名时）：
  · 签名多行时，按「单行 `(…) async {`」写的正则匹配不上；要先在 `) async {` 处切开。
  · 正则要用 `re.search` 而非 `re.match`（签名前有 2 空格缩进）。
  · 参数是**命名参数块**（`{required String a, …}`）时，插入 `context` 要写成
    `context, {` 配 `}) async {` —— 我第一版把 `{` 另起一行，语法错。

**下一轮**：chat_page 剩下的弹层里 `_showInputMenu`（180 行 / 7 依赖）与
`_showSessionInfo`（265 行 / 6 依赖）依赖偏多；15 个渲染块一直不顺。
建议先分类「能抽的」与「不该动的」，再决定继续与否。

**⑬ chat_page 继续推进：3374 → 2496 行（减 26%）**

本段又抽了四个：

| 抽出的 | 行数 | 依赖 | 备注 |
|---|---|---|---|
| `showUiDialog` | 39 | 1 | 原本依赖 4 个，底层抽走后只剩 1 |
| `UndoBar` | 26 | 1 | 边界正则修好后一次过 |
| `FileRefs` | 43 | 2 | 一次过 |
| `Suggestions` + `slashPanelMaxHeight` | 140 + 4 | 2 | 大块但依赖少 |

**两条新经验**：

**1. 分步抽有复利 —— 先抽底层，再抽上层。**
`showUiDialog` 一开始依赖 4 个（三个 `_askXxx` + `_store`）。等那三个 `_askXxx`
先抽出去之后，它自己只剩 1 个依赖，一次就过。若一上来就带着四个依赖搬，风险大得多。

**2. 搬家时用 re-export 保持外部引用有效。**
`slashPanelMaxHeight`（4 行纯函数）被两个测试引用
（`slash_panel_height_test` / `slash_panel_golden_test`）。我把它搬进 `chat/widgets.dart`
后，在 `chat_page.dart` 里加了一行
`export 'chat/widgets.dart' show slashPanelMaxHeight;`
把它 re-export 回去 —— **两个测试一行都不用改**。
比「追着改一堆引用点」稳，尤其是测试断言的正是这个函数的行为。

**3. 行数多不等于难抽，依赖数才是关键。**
`Suggestions` 有 140 行却一次过（只依赖 2 个）；
`_modelRow` 只有 55 行却没成（用了 `StateSetter`，结构上不该搬）。

**⑭ 批量替换命中「不该改的地方」—— 第 5 次，而且每次表现都不同**

抽 `_buildTurnFooter` + `_footerAction` 时又栽在同一类坑上：
用 `t.replace('_store', 'store')` 把组件里的 `_store` 改成参数名，
**结果连 import 路径里的 `server_store.dart` 也改了**（`_store` 是 `server_store` 的子串），
变成 `serverstore.dart`，analyze 报 16 个错。修好 import 后又冒出 4 个
（字段声明没加上、`FooterAction` 的调用形式是位置参数而组件收的是命名参数）。已回退。

**这是同类错误的第 5 次**，前四次分别在 settings / sessions / conn / chat：

| 次数 | 表现 | 文件 |
|---|---|---|
| 1 | `str.replace` 命中同文件另一个结构相似的 class | settings_page |
| 2 | 同上（`SessionRow` / `SessionGroup` 构造签名相同）| sessions_page |
| 3 | 同上（`RemoteCard` 的字段加到了 `CmdRow` 上）| conn_page |
| 4 | `re.sub(r'model')` 过度替换，`chat.model` → `chat.chat.model` | chat_page |
| 5 | `replace('_store', 'store')` 误伤 import 路径 `server_store.dart` | chat_page |

**结论（第 3 次记）**：

> **不做事后批量替换。**
> 要么生成组件时就把名字取对（最省事）；
> 要么把替换限定在**明确的行区间 / class 范围**内；
> 要么用 edit 工具（它不匹配就拒绝，不会静默改错）。

五次里有四次都是「本可以避免」的 —— 名字在生成时取对就行，根本不用回头替换。

**⑮ 关键突破：用脚本的 rename 代替全文件 replace**

第 5 次「批量替换误伤」的**正解**找到了。

**做法**：不做事后全文件 `replace`，改用**脚本自带的 rename 参数**。它有两个好处：

1. **只作用于方法体** —— 根本不碰 import 行，所以 `server_store.dart` 不会被误伤；
2. 用 `re.escape(a) + ` 词边界 —— `_store` 不会匹配到 `server_store` 里的那截。

用这个做法，两个之前失败的目标**一次就过**：

| 目标 | 行数 | 上一轮为什么失败 |
|---|---|---|
| `TurnFooter` + `FooterAction` | 40 + 21 | `replace('_store','store')` 把 import 路径 `server_store.dart` 改成了 `serverstore.dart`（16 个错）|
| `PendingImages` | 52 | 内部两处 `setState` 要转成回调 |

**内部逻辑的改动一律用 edit** —— 它要求精确匹配、不匹配就拒绝，不会静默改错地方。

**本轮 chat_page**：2496 → **2395 行**（累计 3374 → 2395，减 979 / 29%）。

**还有一条**：`chat.model` 这类**字段路径**不要用 `model` 去改（会命中 `chat.model`）
—— 正确做法是**在生成组件时就把参数名设计对**（收 `chat` 而不是 `model`），
压根不给事后替换的机会。

**⑯ chat_page 收在 2344 行（减 31%）；_treeRows 失败**

本轮又抽了三个「纯函数 / 小组件」：`InfoLine`（19 行）、`countTree`（10 行）、
`formatTokens`（6 行）。它们都是 `_showSessionInfo` 的依赖，按「分步抽有复利」先搬走。

**chat_page：3374 → 2344 行**（减 1030 / 31%）。

**`_treeRows`（96 行，递归）失败**。它比之前所有目标都多两层麻烦：
  · 签名多行（4 个参数）；
  · **递归** —— 内部要再调自己，`context` 得一路往下传；
  · 我给它加 `context` 参数，同时组件里又写了 `final t = context.neu;`，
    而签名里本来就有 `NeuTokens t` —— 重复声明；
  · 页面的两处调用点，我的替换只命中了一处。

报错混着三种（`extra_positional_arguments` / `missing_required_argument` /
`argument_type_not_assignable`），来回修两轮没清干净，**回退**。

**建议下一轮**：这类「递归 + 多参数 + 签名多行」的方法**手工搬**，别用脚本 ——
脚本对它的隐式假设太多（不是 State 方法、参数要对齐、内部递归调用不能漏改）。

**⑰ conn_page 完成：1300 → 692 行（减 47%）**

六个文件里减得最多的一个。**根因是一个 363 行的 build 方法** ——
其它页面都没有超长 build，它却有。拆掉 build 里的 5 块 + `_remoteCard`（208 行）就下来了。

**两条最有价值的经验（都来自这个文件）**

**1. 依赖数不能靠正则数，要读代码。**
`_remoteCard` 正则数出 **23 个依赖**，读代码只有 **8 个** ——
正则把块外出现的 `_xxx` 也算进来了。
`sessions_page` 的「已保存的服务器」块同样：正则 13 个，实际 8 个。
**如果信了正则，这两块都会因为「依赖太多」被判不值得拆 ——
而它们恰恰是各自文件里最大的块。**

**2. `if (_expanded.contains(...)) ...[` 这类块的范围不能靠注释判断。**
「快速连接」组的注释下面紧跟「连接诊断」，但诊断按钮**也属于这一组**，
`],` 在更后面。第一次替换漏了 62 行、analyze 报 16 个错。
**正确做法**：找那个 10 空格缩进的收尾 `],`。

**一个测试适配（重要）**

`test/fold_gating_test.dart` 是审计 bug 留下的守卫（分组头画了箭头、
内容却无条件渲染 ⇒ 点下去只会翻箭头）。重构把分组头从页面的 `_section(KEY)`
搬进了组件的 `NeuSection(title: KEY)`，守卫就扫不到东西、**形同虚设**了。

改法：**「承诺可折叠」扫页面 + 该页对应的组件**，
而**门控 `_expanded.contains(KEY)` 仍只认页面**（展开状态在页面的 State 里）。两个细节：
  · 组件与页面必须**成对** —— 否则拿 A 页的组件去 B 页找门控，必然误报一片；
  · 只认**能静态比对的键**（`I18n.t('...')` / `'...'`），传变量的（`title: title`）
    由组件自己负责 —— 静态测试管不了运行时会传什么进来。

**Dart 类型坑**：`_ownRemote` 是 `TextEditingController`（控制器由页面持有并 dispose，
组件只读它的值）；`_saveOwnAddress` 返回 `Future<void>`，回调类型得写
`Future<void> Function(String)`，不能偷懒写成 `ValueChanged<String>`。

**⑱ chat_page 完成：3374 → 1082 行（减 68%）**

六个文件里最长的一个，也是拆得最多的一个（移出 2268 行）。
`chat/widgets.dart` 从小长到大 —— 所有抽出的东西都落在它和 `sheets.dart` 里。

抽出的东西：
  · **弹层 → 顶层函数**：showModelSwitcherSheet / showInputMenuSheet /
    showSessionInfoSheet / confirmForkDialog / confirmNavigateDialog（+ 早先的 sheets.dart 各函数）
  · **渲染块 → StatelessWidget**：ChatHeader / ChatMessageArea / ChatComposer / ModelChip /
    MenuTile / InfoLine / ScrollProgressBar / ScrollToBottomButton / ChatNoticeRow /
    QueuedMessagesRow / SessionRow / SessionGroupCard …
  · **纯函数 → 顶层**：countTree / formatTokens / decodeKey / modelChipLabel / treeRows / relativeTime

**为什么停在 1082 行（离 800 还差 282）—— 这是路线的自然终点，不是没拆完**

按 objective 的约定「状态仍留在父级 State」，剩下的**不该**再抽：

  1. **`build`（133 行）** 已经**纯粹是组件编排** —— 每一行都是一个组件调用，
     自身没有可抽的东西。（把整个 Column 抽成一层壳只会多一层间接，不减少耦合。）
  2. **State 的行为方法（约 700 行 / 51 个）** —— `_send`（59）/ `_onKeyBarKey`（62）/
     `_navigateTo`（81）/ `_pickFile`（39）/ `_pickImage`（31）/ `_syncUsagePolling`（27）…
     这些是**逻辑**不是**界面**：它们读写 State 字段、调 store、处理键盘与文件选择。
     按无状态组件的定义，它们没有「props」可传 —— 硬抽出去只能变成空壳加一堆回调，
     比留在页面更难读（`_modelRow` 的 StateSetter 那次已经验证过一遍）。
  3. **字段声明与监听注册**（约 200 行）—— 同样是 State 自己的东西。

要再往下压，需要换路线（比如引入状态管理库把行为也搬走），
那超出本次「无状态组件化」的范围，也会动到「server_store 是唯一状态源」这条地基。

**⑲ 真机（MuMu）测试抓到的 bug：折叠头点了没反应**

**现象**（装到 MuMu 上点几下就出来）：连接页「快速连接」「已保存的服务器」、
AI 配置页「思考等级」「技能与命令」「pi 插件」—— 点折叠头**完全没反应**。

**根因是重构时引入的**：`_expanded` 这个 Set 存的是**翻译后的标题**
（原 `_section(t, title, ...)` 里的 `title`，也就是 `I18n.t(key)` 的返回值），
**不是 i18n key 本身**。把分组头抽进组件时，onToggle 被写成了：

    const k = 'conn.groupQuick';      // ← key 名
    _expanded.add(k);

而判定处是 `_expanded.contains(I18n.t('conn.groupQuick'))`（翻译值）。
两个字符串不相等 —— 每次点击都在 add 一个永远查不到的值，状态永远不变。
**共 4 处**：conn_page 2 处、config_page 3 处（其中一处原本就写对了）。

**为什么 169 个测试全过却漏掉了**：`fold_gating_test.dart` 只检查
「每个分组头都有配套的 `_expanded.contains(...)`」。两边**确实出现了同一个 key**，
但它不检查**喂给 `_expanded` 的是不是同一个值**。

**补的测试**（同文件）：扫描 `const/final X = '<字面量>'` 且 X 随后被交给
`_expanded.add/remove/contains` 的写法。这条测试**当场又抓出 config_page 那 3 处** ——
说明它不是在补一个特例，而是真能发现同类问题。

**教训（这轮最重要的一条）**：
**静态测试全过 ≠ 没坏。** 「两边都写了同一个 i18n key、但喂给状态的不是同一个值」
这类错误，纯静态检查极难覆盖（164 个用例 + 5 条 fold 守卫都没抓到），
而真机点一遍几秒就暴露。所以「装到模拟器上手动点」不是走形式 ——
它抓到了自动化测试漏掉的真回归。

**结果**：`settings_page.dart` 停在 **875 行**（原 1472，减 597 行 / 40%），未达 800 目标。
差的就是「外观」这 367 行。它仍作为整体留在页面里 —— 至少是**自洽**的
（三个子分组都在它内部），不是散落状态。

---

## 成功经验⑧：2655 行的 chat/widgets.dart 拆成 9 个文件，调用点 0 改动

目标文件：`lib/ui/server/chat/widgets.dart`（2655 行、34 个顶层声明、被 40 多处 import）。
分 5 批搬完（`60d9064` / `bc33654` / `1e5d48b` / `c794239` / `fac3f02`），中途仓库**始终可编译**。

**① 先跑依赖分析，再决定分文件**
用一个脚本列出每个顶层声明「用到谁 / 被谁用」，一眼就能分出层次：
叶子（ChatActivityBar…）→ 一层（ChatHeader→LiveSpeed、ModelChip→modelChipLabel）→
弹层（showSessionInfoSheet→InfoLine/countTree/formatTokens/treeRows）。
按这个顺序搬，能最大限度避免循环 import。

**② 「渐进式 barrel」是关键手法**
`widgets.dart` 一边搬出一边 `export` 搬走的声明 —— 于是 40 多个调用点
（含 `chat_page.dart`、`slash_panel_*_test`、`model_chip_label_test`）**一行都不用改**。
注意 `export` 只影响「导入本文件的人」：本文件自己要用某个符号，仍要单独 `import`，
所以中间状态下 import 与 export 两段并存。
到最后一批时把 import 全删光，它就变成一份 26 行的纯 barrel（只剩索引注释 + export）。

**③ 用 analyze 报错驱动补 import，不要先猜**
每批流程：提取 → 给新文件加一个「能想到的最全」的 import 头 → `flutter analyze` →
按报错增删。比先读完 400 行代码再推断 import 快得多，也不容易漏。

**④ 顺手删掉随搬家失效的 import**
analyze 会报 `unused_import`；每批搬完都清一次，否则最后要一次面对十几个。

**⑤ 真机复验挑「代表性交互」**，不用全测：
这次验了消息区（含 Markdown 表格）、输入区、快捷键栏、输入菜单弹层 —— 四个分别来自
message_area / composer / key_bar / sheets，足够覆盖各新文件的代表性代码路径。

---

## 成功经验⑦：「外观」422 行 + 三层嵌套子分组，怎么一次搬成（前一轮）

「踩过的坑⑤」记的是**失败四次**，这里是它的解法。五条，按重要性排：

**① 边界用括号配对算，不要用「标记行」**
失败过的做法：拿 `SizedBox(height: NeuSpace.n20)`、或「下一个方法定义」当边界 ——
前者在外观块内部就出现多次（切早/切晚），后者会匹配到注释行与参数换行，只摘到一行签名。
这次：从 `if (_expanded.contains(<该分组 key>)) ...[` 那一行起，对 `[` / `]` 做计数直到归零，
终点自动出来。定位那一行时也要**语义唯一**（同时满足「含 `_expanded.contains(`」与
「同一处出现 `settings.appearance`」两个条件），而不是单纯找标题字符串。

**② 搬运时保留一个「同名同形的私有包装」**
失败过的做法：边搬边重排参数（把 `_section(t, KEY, icon:)` 改写成
`SettingsSection(title: KEY, open: ..., onToggle: ...)`），于是尾部括号反复错位。
这次：在新组件里也定义 `_section(title, {icon, summary})`（内部读 `isOpen` / `onToggle`），
**只把第一个参数 `t,` 删掉** —— 其余 420 行一个字不动。调用点因此不用重排，
后续 `dart format` 顺手把缩进对齐。

**③ 依赖面先探清再动手**（一条命令）
`sed -n '起,止p' 文件 | grep -oE '_[a-zA-Z]+' | sort | uniq -c | sort -rn`
这次一次量出：整块只依赖 6 个 State 成员（`_section` / `_expanded` / `_isOpen` / `_toggle` /
`_pickStuckSeconds` / `_testNotification`），且后两个只依赖 `NotificationCenter` 单例、
不碰父级状态 —— 所以能直接跟着搬走，不必往父级加回调。

**④ 守卫要跟着组件一起走**
`fold_gating_test` 三处都要改：`sectionCalls`（组件版 `_section` 少了一个 `t` 参数）、
`hasGate`（门控从 `_expanded.contains` 变成 `isOpen`）、设置页的 companion 列表。
**顺序别反**：先跑测试 → 守卫报「一个分组头都没解析到」→ 再改守卫；
反过来容易把「守卫已失效」当成「守卫通过」。

**⑤ 收尾清单**（`analyze` 会提示，但先知道更好）
删掉页面里完成使命的 `_section` 薄包装；删掉只被这块用到的 import
（这次是 `collapsible_text` / `native_bridge` / `notification_center`）。

**验证顺序**：`dart format` → `flutter analyze`（0 issue）→ `flutter test`（含 3 个 golden 基线，
它们能证明「渲染逐像素没变」）→ **真机复验折叠交互**（外观展开 + 子分组展开各一次）。

结果：`settings_page.dart` 990 → **472 行**，新增 `settings/appearance_section.dart` 544 行（`cc33bca`）。

---

## 踩过的坑⑨：这次抽 MCP 分组踩的两个新坑（2026-10-09）

**① State 的方法搬进 StatelessWidget 后，`context` 与 `mounted` 会凭空消失**
    `_addMcpServer()` / `_removeMcpServer(server)` 原本是 State 的方法，函数体里直接用
    `context` 和 `mounted`（State 自带）。搬进无状态组件后这两样都没有了 —— analyze 一次
    报出 8 处。改法：给方法加 `BuildContext context` 参数并在调用点传进去，
    `mounted` 换成 `context.mounted`。
    **排查提示**：analyze 报 `Undefined name 'context'` 时，先看这段代码是不是从 State 里搬出来的。

**② 花括号配对删块时，务必忽略「命名参数的 `{}`」**
    删页面里那个 `_section(...)` 包装时我用 `{`/`}` 计数找结尾，结果函数签名里的
    `{IconId icon = ..., String? summary, String? stateKey}` 让深度提前归零 —— 只删掉 3 行、
    留下残骸；修残骸时又多删了一行收尾。好在 analyze 立刻报错、问题没有流出去。
    **正确做法**：配对前把参数列表的 `{}` 剔除（一个简单的办法是先跳过「首个 `{` 之前
    的 `(...)` 段」，或只对 `if`/`for` 这类语句做配对），删完立刻跑 analyze 确认。

**顺带一条正面经验**：抽分组时若某个辅助函数**被页面和组件同时需要**（这次是
`_dialogField`），把它提成共享顶层函数（放到该功能的 `widgets.dart`）比「让组件反过来
依赖页面」干净得多 —— 后者会制造循环 import。