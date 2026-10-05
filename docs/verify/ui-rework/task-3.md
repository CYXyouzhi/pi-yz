# task-3 · 我普查出的同类缺陷：截断、不可滚、editorText、草稿丢失（已完成）

证据目录：`docs/verify/ui-rework/task-3/`（10 张实机截图）。
真机环境：MuMu，App `com.youzhi.pimobile.pi_mobile`，服务端 `10.1.1.195:30142`。

---

## ① 设置 / AI 配置的内容不再被截断

**改法**（`lib/ui/server/config_page.dart`，5 处 `maxLines: 1 + ellipsis` 放开）：

| 位置 | 原来 | 现在 |
|---|---|---|
| 当前模型行 | `maxLines: 1` → 「DeepSeek V4.1 Flash · opencode-go」被截掉 provider | 2 行，provider 一定看得见 |
| 包名 | 1 行截断 | 2 行 |
| 包安装路径 | 1 行截断（路径是本行唯一有用信息，截了等于没给） | 3 行 |
| MCP 名 | 1 行 | 2 行 |
| 模型列表里的模型名 | 1 行（「LongCat 2.5 Preview Free」装不下） | 2 行 |
| 命令清单左侧命令名 | 固定 140px + 1 行截断 | 168px + 2 行（`/skill:impeccable-design-polish-…` 这类长命令名能读全） |

**证据**：`after-01-config-readable.png`（模型列表逐条完整：模型名两行、第二行给 provider / 上下文 / 是否支持思考）。

---

## ② 会话信息面板超屏时可滚动

**修复前**：整张面板是 `Column(mainAxisSize: min)`，**只有「分支树」那一小块在 SingleChildScrollView 里**。
「用量」区一多（加了上下文/tokens/花费/条目/自动压缩之后）就把下面的按钮和分支树顶出屏幕，而面板本身滑不动 ——
实测三指上推都不动，分支树根本够不到。

**改法**：整张面板套一层 `SingleChildScrollView`，内部原来的 `Flexible + 内层滚动` 改成普通 Column。

**证据**：`after-02-info-sheet-scrollable.png` —— 两次上滑后停在分支树深处（assistant / toolResult 节点带「+」分叉按钮），
这些内容在修复前完全够不到。

---

## ③ 切分支 / 分叉后 editorText 可靠回到输入框

**改法**：`ServerStore.pendingEditorText` 接住 `navigate_tree` / `fork_from_message` 回传的 `editorText`；
`chat_page._applyPendingEditorText()` 在切换后写进输入框并把光标移到末尾。

**证据链（完整走了一遍）**：

1. `after-03-switch-confirm.png` —— 分支树点第一个用户节点，确认弹窗：后续对话接在「Reply with exactly: alpha」之后。
2. `after-03-editor-text-in-input.png` —— 切换完成后：**输入框里就是「Reply with exactly: alpha」**（editorText 回来了）。
3. `after-03-resend-continues-branch.png` —— 直接把这条发出去：会话继续在新分支上跑，列表显示「已载入 2 条」（user alpha + assistant alpha）。
   落盘 JSONL 为证：条目数 8 → 11，末尾依次是 `system` → `user | Reply with exactly: alpha` → `assistant | alpha`。

### 顺带查清的一件事（不是 bug，写下来免得下次误判）

切到**用户消息节点**后，App 头部显示「已载入 0 条」、消息区回到「开始对话」空态。
一开始我以为是 bug，直接问服务端 `get_messages`：**服务端自己也只返回 1 条（只有 system）**。
结论：这是 pi 的语义 —— 导航到一条用户消息等于「把那条消息取回编辑器准备重发」，
它就从上下文里弹出去、交给 `editorText`。所以那 0 条是**正确**的，App 只是如实显示。

---

## ④ 切 tab / 切页 / 退回列表后输入草稿不丢

**修复前**：外壳用 `AnimatedSwitcher` + 每个 Tab 一个 `ValueKey(_tab)`，切走 = 页面被销毁，输入框内容随之消失。

**改法（两层保底）**：

1. `lib/main.dart`：三个 Tab 改用 `IndexedStack` 常驻，切走不再销毁页面（顺带保住滚动位置、展开状态、命令面板）。
   代价：Tab 之间没有转场动画 —— 手机端 Tab 切换本来也不需要，动效统一留到 UI 阶段（任务㉒）。
2. `ServerStore` 加草稿表：`draftFor(sessionId)` / `saveDraft(sessionId, text)`，输入框每次变化就存；
   换会话时自动把输入框换成该会话的草稿。页面即使被重建也不丢。

**证据**：`after-04-draft-typed.png`（输入 draft-keep-123）→ 切到「开始」→ 切回「会话」
→ `after-04-draft-survives-tab.png`（文字还在）。

---

## ⑤ 底部弹层在窄屏不漏内容

**改法**：3 处 `showModalBottomSheet` 之前没开 `isScrollControlled`（默认最高只到半屏），
在小屏手机上内容会被切掉、且不可滚。三处（chat_page 的按钮选项面板、files_page 的文件说明面板、
sessions_page 的会话操作菜单）都补上 `isScrollControlled: true`。

**诚实说明**：本项没有「修复前/修复后」的实机对比图 —— MuMu 的分辨率是 1080×1920，
在这块屏上三处弹层原本也装得下，不是我能在模拟器上稳定复现的漏内容场景。
因此以**代码层证据**为准（三处开关已开 + 弹层内容本身可滚），
②那张滚动图算是同一机制在真机上的佐证。这一条我不假装有前图。

---

## ⑥ 加载 / 错误态一致，失败有重试入口

**修复前**：全项目 `重试|retry` 在界面层**零命中** —— 失败只有一句红字，没有可走的路。

**改法（四处，都先补连接再重载）**：

| 位置 | 做了什么 |
|---|---|
| `ServerStore.ensureConnected()` | 新增：断线时用记着的地址再连一次（没有这一步，「重试」只会再失败一次，因为 store 根本没有客户端） |
| AI 配置页 | 四条子接口都空且不在加载中 → 顶部红条「没能读到配置（可能未连接或服务端异常）」+「重试」 |
| 开始页会话列表 | 错误文案下面加「重试」 |
| 文件浏览页 | 错误文案下面加「重试」 |
| 会话页 | 拉不到会话时给「重新载入」（走 `ensureConnected` + `openSession`） |

**证据（真造了一次故障，不是看图猜）**：

1. `after-06-files-error-retry.png` —— 停掉服务端后打开文件浏览：红字 + 「重试」按钮。
2. `after-06-config-error-retry.png` —— 同一状态下进 AI 配置：顶部红条 + 「重试」。
3. `after-06-retry-recovered.png` —— **重新启动服务端后点「重试」**：模型列表整片回来了（连接也自动补上）。

顺带一个已经成立的好行为：断线时设置页的连接卡给的是**具体原因**「无法连接 10.1.1.195:30142（Connection refused）」，
不是笼统的「连接失败」。

---

## 本项收口自检

| 项 | 结果 |
|---|---|
| `flutter analyze` | No issues found! |
| `flutter test` | 25/25 通过 |
| 实机 | MuMu 上逐条走查，证据见 `task-3/`（10 张） |
| 数据还原 | 测试用的分支会话已删除，服务端会话总数回到 **244** |
| 附带发现 | `navigate_tree` 到用户节点后消息为 0 是 pi 的语义（见 ③），不是缺陷 |
