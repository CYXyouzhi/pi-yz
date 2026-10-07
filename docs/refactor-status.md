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
| `lib/ui/server/config_page.dart` | 1307 | ⬜ 未开始 |
| `lib/ui/server/files_page.dart` | 1059 | ⬜ 未开始 |
| `lib/ui/server/sessions_page.dart` | 1316 | ⬜ 未开始 |
| `lib/ui/server/conn_page.dart` | 1300 | ⬜ 未开始 |
| `lib/ui/server/chat_page.dart` | 3374 | ⬜ 未开始（最痛也最难，放最后）|
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

**结果**：`settings_page.dart` 停在 **875 行**（原 1472，减 597 行 / 40%），未达 800 目标。
差的就是「外观」这 367 行。它仍作为整体留在页面里 —— 至少是**自洽**的
（三个子分组都在它内部），不是散落状态。
