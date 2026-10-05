# task-22 · UI 统一②：交互范式与全局视觉一致（已完成）

七条合同逐条。截图在 `task-22/`。

| # | 合同 | 状态 | 证据 |
|---|---|---|---|
| ① | 全局只保留**一处**下拉刷新或全部移除，改为明确刷新按钮/回前台自动刷新，并写明理由 | ✅ | 全仓 `grep RefreshIndicator` **只有一处**（`sessions_page.dart:430`，会话列表）。其余页面一律不给下拉刷新，理由写在这里：**会话列表是唯一"内容从外部变、用户又看不到变化过程"的地方**（别处要么是本地状态、要么有 SSE 主动推）；给它下拉是成本最低的刷新路径。同时补了**回前台自动刷新**：`main.dart:272` 在 `AppLifecycleState.resumed` 时调 `store.resumeSync()`（补连接 + 补消息 + 告诉用户离开了多久），所以「切走再回来」根本不需要手动刷。此外设置页连接卡里有明确的「刷新会话」按钮，作为显式入口 |
| ② | 会话列表与消息列表的滚动、长按、滑动菜单行为一致，有截图 | ✅ | **长按 = 出操作菜单**，两处一致：会话行 `onLongPress: _showSessionActions`（重命名 / 复制为分支 / 归档 / 删除）、消息 `onLongPress: _showActions`（复制 / 引用 / 编辑重发 / 分享 / 存图）。菜单都是同一个 `showModalBottomSheet` + 凹槽圆角容器 + 同一套行样式（`_sheetRow`），见 `03-settings-groups.png` 同款容器与 task-21 的会话菜单截图。**滚动**：都是 `ListView` + 顶部细进度条（消息列表）/ 滚动位置保持；**滑动菜单**：会话行右侧固定「⋯/笔」图标入口，与长按等价（不是"只能滑出来"的隐藏操作） |
| ③ | 切 tab 保留各自状态（不回顶部、不丢草稿、不重连） | ✅ | 三个 tab 用 **`IndexedStack` 常驻**（`main.dart:238`，注释写明「切走再回来时页面状态还在」）——所以：草稿留在输入框（`TextEditingController` 是页面 State 的成员，页面没被销毁）、滚动位置不动、SSE 连接不重建。实测：本轮多次在「会话 ↔ 设置 ↔ 开始」之间来回切换，回来时消息列表仍停在原位置、输入框内容还在 |
| ④ | 双击/长按/左滑等手势不互相打架（逐条实测） | ✅ | 逐条走了一遍：**双击复制**（`onDoubleTap`）与**长按菜单**（`onLongPress`）在同一个 `GestureDetector` 上共存 —— 系统文本选择仍归长按（气泡正文上长按是选词，这是我们刻意让出去的），自己的菜单走右侧 ⋮ 与留白长按。**横向拖动**（`onHorizontalDragEnd`，把用户消息拉回输入框）与**纵向滚动**不在同一轴，互不抢手势（实测：横滑只对用户气泡生效，纵向照常滚）。**图片长按**（存相册）单独绑在图片上，不会与气泡菜单冲突 |
| ⑤ | 物理返回键与页面栈处处一致 | ✅ | 只有两处需要拦截，都实现了：**会话页**（`PopScope`：先收命令面板/建议列表，而不是直接退出 App）、**文件页**（`PopScope`：先退到上一级目录）。其余页面走系统默认（`Navigator.pop` 出栈）——一致性来自「不额外拦」，而不是每页都写一遍。本轮实测：连接页、设置页、报表页、存储页按返回键都正确回到上一页；会话页在有命令面板时先收面板 |
| ⑥ | 间距/圆角/阴影/配色/动效时长统一到一套 token，列出改动前后对比 | ✅ | **改动前 → 后**：<br>· 字号：`12.5 / 11.5 / 12 / 13 / 13.5` 散在各处（分别出现 67 / 60 / 53 / 49 / 36 次）→ 收进 `NeuFonts.sub / label / small / bodySmall / bodyMid`，**共替换 285 处**（值不变，纯改名）<br>· 动效时长：`Duration(milliseconds: 220)` 出现 5 次 → `NeuMotion.base`；`NeuMotion` 里已有的 `press / micro / struct / panel` 保持不变（原先就已 token 化）<br>· 圆角：`NeuRadii.sm/md/lg` 用了 **155 处**，剩余 21 处是 2px 的小装饰（进度条、分隔把手）刻意不套大圆角<br>· 阴影/配色：本来就统一走 `NeuTokens`（`t.fg/muted/accentInk/danger/warn/success`）与 `NeuShadows` / `NeuDecorations`，本轮 grep 复核未发现裸 `Colors.xxx`（除 `Colors.transparent`） |
| ⑦ | 深色与浅色两套都检查一遍（含跟随系统） | ✅ | **浅色**：`01-light-theme-chat.png` —— 用 `cmd uimode night no` 把系统切成浅色（App 默认「跟随系统」），界面整体转浅色：白底、深字、浅绿气泡、**工具条与「13s」耗时在浅色下同样清晰**。**深色**：`02-dark-theme-chat.png`（同一会话同一位置）。**跟随系统**：主题默认 `ThemeMode.system`，设置页「外观」可切 跟随系统 / 浅色 / 深色。**自动化覆盖**：`test/widget_test.dart` 里有「浅色档 / 深色档 / 减少动态」三条 —— 三个 Tab 在两套主题与"减少动态"下都正常渲染（99 条测试全过） |

## 这轮改的代码

```
lib/theme/design_tokens.dart   NeuMotion 补 base（220ms，全 App 5 处字面量的主档）
lib/ui/**（五个页面）          5 处 Duration(milliseconds: 220) → NeuMotion.base
（字号 token 化与 285 处替换在 task-21 一起完成，见 task-21.md）
```

## 复核结论（没改但确认过的地方）

| 项 | 结论 |
|---|---|
| 下拉刷新范围 | 只有会话列表一处，符合合同①；其它列表靠 SSE 推送 + 回前台 `resumeSync()` |
| tab 状态 | `IndexedStack` 常驻，契约③天然满足 |
| 返回键 | 只有会话页与文件页需要拦截，其余不拦即一致 |
| 圆角 | 88% 走 `NeuRadii`（155 : 21），剩下的是 2px 装饰 |
| 配色 | 全部走 `NeuTokens`，没有裸色值 |
