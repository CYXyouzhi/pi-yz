# task-2 · 用户点名的六个缺陷（已完成）

改造目标 `musdn4vd-oqgeny` 的第二项。本项**只保证行为正确**，观感统一留到 UI 阶段（任务㉑㉒）。

证据目录：`docs/verify/ui-rework/task-2/`（修复前 2 张 + 修复后 6 张）。
模拟器：MuMu，App `com.youzhi.pimobile.pi_mobile`，服务端 `10.1.1.195:30142`。

---

## ① 文件浏览「返回上一级」回到真实的上一级

**修复前的问题**：点「上一级」时**先把路径改掉、再去读目录**。一旦读取失败（上一层超出允许范围），
界面就停在「路径变了、列表还是旧的」的半死状态；用户感受就是「返回上一级却没回之前一级」。

**根因两处**：

| 位置 | 原因 |
|---|---|
| `lib/ui/server/files_page.dart` | `_path = _listing!.parent!; await _load();` —— 先改路径再读，失败不回滚 |
| `server/lib/fs.mjs` `listDirectory` | `parent` 只要不是根就返回，**不检查上一层是否还在允许范围内**，于是 App 会给出一个点了必然失败的按钮 |

**改法**：

- App：新增 `_openDir(target)` —— 先读成功，**才**改 `_path`；失败则路径不动并说明「读不到 X（可能超出允许范围）」。
  `_enter`（进子目录）与 `_goUp`（上一级）都走它。
- 服务端：`parent` 只有落在允许范围内才给，否则为 `null`（等于「这里就是顶」）。

**证据**：

- 服务端逐级验证（`/api/files?path=…`）：
  - `C:\Users\you\Desktop` → `parent = C:\Users\you` ✓
  - `C:\Users\you\Desktop\1` → `parent = C:\Users\you\Desktop` ✓（**是真实上一级，不跳级**）
  - `C:\Users\you`（允许范围边界）→ `parent = null` ✓
  - `D:\`（超出范围）→ 拒绝：`路径不在允许范围内` ✓
- 实机：`after-01-up-one-level.png` —— 在 `.od-skills` 里点「上一级」，回到工作区根，目录列表同步换成上一层内容。
- 实机：`after-01-boundary-no-up-button.png` —— 到顶时（工作区根 `E:\OpenDesign\<id>`，其上一层不在允许范围）
  顶栏只有「上传 / 刷新」两个按钮，**不再出现一个点了必然失败的「上一级」**。

**复现步骤**：设置 → 文件浏览 → 进任意子目录 → 点顶栏「上一级」→ 应回到该子目录的父目录且列表正确。

---

## ② 物理返回键：一级退一级，到顶才退出页面

**修复前**：文件页里按返回键，无论在哪一层都**直接退出页面**回到设置。

**改法**：`files_page.dart` 的 `build` 外层加 `PopScope`：

```dart
canPop: _listing?.parent == null,          // 还有上一层 → 不许 pop
onPopInvokedWithResult: (didPop, _) { if (!didPop) _goUp(); },
```

**证据**：`after-02-back-goes-up.png` —— 在 `.od-skills` 里按一次返回键，落到工作区根（**没有退出页面**）；
到了顶（`parent == null`）再按返回才退出。

**复现步骤**：文件浏览 → 进子目录 → 按系统返回键 → 应上一级；到顶后再按才退出。

---

## ③ 斜杠命令：能出来、不截断、数字不说谎

**修复前的三个问题**：

1. **没打开会话时输入 `/` 什么也不显示** —— `ServerStore.refreshCommandsIfNeeded()` 写好了却**从没被调用**
   （它自己的注释还写着「配置页在没有打开任何会话时也调它」），而 `commands` 只在开会话时才会拉。
2. 命令名与说明被截断：面板写死 `maxHeight: 200`，说明 `maxLines: 2 + ellipsis`。
3. `.take(12)` 把列表砍到 12 条：**第 13 条以后永远选不到**，而底部计数还写「共 12 个」——假信息。

**改法**：

- `connect()` 成功后调一次 `refreshCommandsIfNeeded()`；输入 `/` 或点 ⌘ 时再兜一次。
- 面板高度跟屏幕走（屏高 45%，夹在 180–400px）；说明不再截断；命令名一行**可横向滑动**（长扩展命令名能滑着读完）。
- 去掉 `.take(12)`；底部计数改真话：`共 N 个` / `匹配 M / 共 N 个`。

**证据**：`before-03-commands-blank.png`（输入 `/` 后面板一片空白）
→ `after-03-commands-list.png`（列出 `/skill:edge-tts`、`/skill:animate`…，说明完整，底部 **「共 40 个 · 上下滑动看全部」**）。

**复现步骤**：会话页（不必打开会话）→ 输入 `/` → 应列出全部命令并可滑动；计数与实际条目数一致。

---

## ④ 滚动：进度条常驻 + 「回到底部」不再时灵时不灵

**修复前**：`_nearBottom` 是**只在 build 时算一次**的 getter，而滚动不会触发 build ——
所以「回到底部」按钮的出现/消失取决于别的重建时机，用户感受就是「时灵时不灵」；另外**根本没有滚动进度条**。

**改法**：

- `initState` 里 `_scroll.addListener(_onScroll)`；`_onScroll` 维护「是否贴底」（留 80px 容差，避免底部附近抖动闪烁）
  与滚动进度（用 `ValueNotifier<double>` 驱动进度条，避免每帧重建整个列表）。
- 列表顶部加一条 2.5px 细进度条（能滚时常驻）；`_scrollToBottom` 改为 `animateTo`（220ms）。

**证据**：`after-04-progress-and-jump.png`（顶部进度条 + 右下「回到底部」按钮同时出现）。

**程序化抽样（不靠肉眼）**：循环 10 轮「点回底按钮 → 应消失 → 上滑离开底部 → 应出现」，
按按钮所在区域亮度判定（27.0 = 无按钮 / 48.5 = 有按钮）：

```
轮次  点按钮后（应无）  上滑后（应有）
  1..10   27.0 无✓        48.5 有✓    全部 OK
10 轮里不符的次数：0
```

**复现步骤**：打开消息多的会话 → 上滑 → 顶部进度条移动且右下出现回底按钮 → 点它 → 按钮消失（已到底）。

---

## ⑤ 「未保存的新建会话」不再单独占一行

**修复前**：`_buildRows()` 里有一整段：插入 `_SectionRow('未保存')` + `_PendingRow()`。
而 `_buildRow` 的 switch 里**根本没有 `_PendingRow` 分支** —— 于是界面上只留下一个孤零零的「未保存」标题，
下面什么都没有（更让人以为丢了东西）。它本来只是新建会话过程中的极短中间态。

**改法**：删掉该分组、删掉 `_PendingRow` 类与 `_buildPendingRow()`（`pendingSession` 状态本身保留在 store 里，
只是不再渲染）。

**证据**：`after-06-conn-card-clean.png`（开始页无「未保存」分组）。
**诚实说明**：这一条的「修复前」截图**没能抓到** —— `pendingSession` 是新建会话过程中的瞬态，窗口很短，
靠手点复现不稳定。因此以「代码位置 + 修复后不再出现该分组」为证，不假装有前图。

---

## ⑥ 开始页连接卡右下角的圆按钮去掉

**修复前**：连接卡右下有个圆形「刷新会话」按钮（`IconId.sync` → `loadSessions(refresh: true)`），
与下拉刷新、进页自动刷新重复，还挤在连接卡角上（用户点名它是多余的）。

**改法**：删掉该按钮（刷新入口留到 UI 阶段统一决定形态，见任务㉒）。

**证据**：`before-06-conn-card-sync.png`（右下有圆按钮）→ `after-06-conn-card-clean.png`（没有）。

---

## 本项收口自检

| 项 | 结果 |
|---|---|
| `flutter analyze` | No issues found!（0 issue） |
| `flutter test` | 25/25 通过 |
| 服务端语法 | `node --check server/lib/fs.mjs` 通过 |
| 实机 | MuMu 上逐条走查，证据见 `task-2/` |
| 新增的额外修复 | 命令列表 12 条硬上限（顺带发现，已去掉） |

<!-- 开源前把用户名统一写成 you，其余内容未改（本文件是验证记录，不歪曲证据）。 -->
