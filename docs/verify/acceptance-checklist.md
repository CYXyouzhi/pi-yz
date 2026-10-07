# pi-yz 验收清单（task-7 回归）

验收方式：MuMu 模拟器（Android 15 / 1080×1920 / density 480）+ ADB（逻辑 display id 输入、物理 token 截图）
证据目录：`docs/verify/`（文件名对应下表「证据」列）

工具：`tool/ctrl.py`（tap / swipe / text / key / shot，自动处理 display 映射）

## 一、核心对话链路

| # | 功能 | 状态 | 证据 |
|---|---|---|---|
| 1 | 连接服务端 + 自动重连 | ✅ | t1-home |
| 2 | 会话列表（按工作区分组，默认全部折叠） | ✅ | t1-home / t2-home |
| 3 | 工作区展开 → 会话行在同一张卡内 + 发丝分隔线 | ✅ | t2-group-card |
| 4 | 新建会话（选工作区 / 空会话不重复建 / 未落盘条目标注） | ✅ | t1-newws / t1-newchat |
| 5 | 打开历史会话并渲染历史 | ✅ | t1-chat-history |
| 6 | 发消息 + 流式渲染（三点指示 + 增量文本） | ✅ | t1-stream-a / t1-stream-b |
| 7 | 运行态 UI（✕ 中断键 + 「运行中…可输入以插话」） | ✅ | t3-running-state |
| 8 | Markdown 渲染（标题/加粗/行内代码/代码块/表格/分隔线） | ✅ | t2-markdown4 / t3-reopen / t4-tree2 / t3-pagination |
| 9 | 思考块（折叠显示 + ANSI 乱码已剥离） | ✅ | t2-markdown2 / t3-reopen |
| 10 | 工具卡片（调用/完成/失败标签、可展开输出） | ✅ | t1-chat-history / t2-markdown3 |
| 11 | 命令面板（`/` 触发、两行显示、中文命令完整） | ✅ | t2-cmdpanel |
| 12 | 扩展对话框桥接（select/confirm/input/editor，端到端回传） | ✅ | t3-uidialog2 / t3-uidialog3 |
| 13 | 大会话分页（快照只带最近 60 条 + 加载更早） | ✅ | t3-pagination |
| 14 | 滚动到最新提示（阅读历史时不打扰） | ✅ | t3-reply |
| 15 | 图片消息渲染（缩略图 + 文字同气泡） | ✅ | t7-image3 |
| 16 | 中断的实际效果（长任务 + ✕ → 服务端 isStreaming=false、回复 0 字） | ✅ | t7-abort2 |

## 二、会话管理

| # | 功能 | 状态 | 证据 |
|---|---|---|---|
| 17 | 搜索（名称/首条消息/路径，命中自动展开分组） | ✅ | t4-search |
| 18 | 空结果提示 | ✅ | t4-state |
| 19 | 会话操作菜单（重命名 / 删除） | ✅ | t4-actions |
| 20 | 删除确认 + 真实移除 | ✅ | t4-delconfirm（会话从服务端列表消失） |
| 21 | 重命名（端到端） | ✅ | t7-rename-typed / t7-rename-done；服务端确认 name="ok1"。**绕过手段：`input keyevent` 逐键输入**（`input text` 进不了 Flutter 对话框） |
| 22 | 分支树浏览（会话信息面板） | ✅ | t4-tree8（773 节点 + 缩进 + 叶子高亮） |
| 23 | 会话信息（模型/思考等级/消息数/工作区/会话名） | ✅ | t4-tree5 |

## 三、文件与 Git

| # | 功能 | 状态 | 证据 |
|---|---|---|---|
| 24 | 文件浏览（目录/文件/大小/上级/刷新） | ✅ | t5-files / t5-files2 |
| 25 | 文件预览（等宽 + 凹槽 + 大小与截断提示） | ✅ | t5-git2 |
| 26 | git status 接口（分支 + 变更列表） | ✅ | 服务端：临时仓库 2 处变更 |
| 27 | git diff 接口（真实 +/- 内容） | ✅ | 服务端：11 行 diff |
| 28 | diff 面板的 App 内着色渲染（- 红 / + 绿 / @@ accent） | ✅ | t7-diff |
| 29 | @ 文件引用（候选列表 + 插入） | ✅ | t5-atrefs / t5-atrefs2 |
| 30 | 路径白名单（越权返回 403） | ✅ | 服务端：`C:/Windows` → 403 |

## 四、配置管理

| # | 功能 | 状态 | 证据 |
|---|---|---|---|
| 31 | 模型列表（当前标记 / provider / 上下文 / 是否支持思考） | ✅ | t6-config |
| 32 | 切换模型并即时同步界面 | ✅ | t6-switch3（修复 B13：切换成功但界面不更新） |
| 33 | 技能 / 扩展命令 / 内置命令列表 | ✅ | t6-lower2（内置 13 条含中文说明） |
| 34 | MCP 服务器列表（读 mcp.json） | ✅ | t6-lower2（未配置空态） |
| 35 | 思考等级切换 | ✅ | task-3 的 /thinking picker + 本页 chips |

## 五、设置与外观

| # | 功能 | 状态 | 证据 |
|---|---|---|---|
| 36 | 连接管理（刷新会话 / 断开） | ✅ | t1-settings |
| 37 | 主题切换（跟随系统 / 浅色 / 深色） | ✅ | t7-theme-light / t7-theme-restore |
| 38 | 关于（版本 / 活跃会话 / 会话总数） | ✅ | t1-settings |
| 39 | 底部 tab 三等分撑满、选中内凹胶囊 | ✅ | t1-home（按设计稿修正后） |

## 六、本轮修掉的 bug（回归时需复测）

| bug | 说明 | 状态 |
|---|---|---|
| B1 | Markdown 完全未渲染（表格/代码都是原文） | ✅ 已修并验证 |
| B2 | 底部内容被 tab 栏遮挡 | ✅ |
| B3 | 连接页「已保存」两行文字重复 | ✅ |
| B4 | 配置名为空无兜底 | ✅ |
| B5 | 返回键直接退出 App（未先收面板） | ✅ |
| B6 | 展开后会话行没有卡片包裹 | ✅ |
| B7 | 命令面板占半屏 | ✅ |
| B8 | 工作区选择器无把手/取消 | ✅ |
| B9 | 会话行缺分隔线 | ✅ |
| B10 | 思考内容 ANSI 转义显示成乱码 | ✅ |
| B11 | **扩展对话框在 App 上根本不显示** | ✅ 已修并端到端验证 |
| B12 | 缺少 get_tree / rename_session 服务端命令 | ✅ |
| B13 | 切模型后界面不同步 | ✅ |
| B14 | 会话列表随流式高频重建 | ✅（独立 sessionsRevision 信号） |

## 七、已知限制（非 App 缺陷）

1. **MuMu 的 `input text` 有时进不了 Flutter 输入框**（早前重命名对话框遇到过，当时改用逐键 keyevent 绕过）。
   第七轮实测补充：凭据对话框里输入 provider / API Key 是**正常**的（t14-cred-added），
   所以这不是必然问题，更像特定输入框的状态问题。真机上用软键盘，不受影响。
2. **MuMu 多虚拟屏**：`input` 要逻辑 display id、`screencap` 要物理 token，且 force-stop 后会变 →
   已由 `tool/ctrl.py` 自动处理。
3. **未落盘的会话不在列表里**（pi 是 append-only 存储，没说过话就没文件）——
   App 用「未保存」条目处理了这个情形。

## 八、第二轮：反馈可见性与手机体验

| 项 | 结果 | 证据 |
|---|---|---|
| 统一 Toast 组件（`lib/ui/neu_toast.dart`） | ✅ | t8-toast 系列：同一条消息在不同位置（顶部/底部/命令面板上方）都不遮挡内容，危险操作红色图标 |
| 长按复制消息 | ✅ | t8-copy-before（长按）→ t8-copy-after（「已复制」）→ t8-copy-crop |
| 会话列表下拉刷新 | ✅ | t9-refresh（顶部出现刷新指示器） |
| 会话搜索命中的空态 | ✅ | t4-search |
| 代码自检：`await` 后未判 `mounted` | ✅ 修 1 处真缺口 | `sessions_page._createSession` 里 `await _pickWorkspace()` 之后没判 `mounted`（选择器异步关闭期间页面可能已销毁）；其余 `await → setState` 命中的都是同步回调，属误报 |

## 九、会话信息面板与分支树浏览

| 项 | 结果 | 证据 |
|---|---|---|
| 会话信息（模型 / 思考等级 / 消息数 / 工作区） | ✅ | t10-tree 顶部区块 |
| 分支树浏览（缩进 + 当前叶子高亮 + 分叉标注） | ✅ | t4-tree2 … t4-tree8（最大一条 773 节点）、t10-tree |
| 节点展开/收起 | ✅ | t4-tree4 / t4-tree6 |
| 面板直接跳「浏览工作区文件」 | ✅ | t10-tree |

实现：`get_tree` 服务端命令 + 面板里把树压成缩进列表（深度优先），叶子节点用强调色标记。

## 十、会话内切分支（navigate_tree）

| 项 | 结果 | 证据 |
|---|---|---|
| 服务端 `navigate_tree` | ✅ | 命令返回 `{cancelled, editorText, leafId}`，与 pi 的 RPC 语义一致 |
| App 入口（点树里的任意节点） | ✅ | t10-nav-confirm（确认框：后续对话接在该节点之后，当前分支不丢） |
| 切完刷新上下文 | ✅ | 切换成功后重新拉快照重建消息列表；被切走的用户消息回到输入框（pi 的 `editorText` 行为） |

## 十一、复制为分支（clone_session）

pi 的 `/clone`：把当前会话复制成一条新会话（新 ID、`parentSession` 指向源），源会话不动。

| 项 | 结果 | 证据 |
|---|---|---|
| 服务端 `clone_session` | ✅ | 一次性会话实测：返回新 sessionId；新会话条数与源一致（完整历史）、`parentId` 指向源、源会话未被改动 |
| App 菜单入口 | ✅ | t11-menu（重命名 / **复制为分支** / 删除） |
| App 端到端 | ✅ | t11-cloned：点「复制为分支」后自动切到新会话，历史完整复制过来 |

实现：`SessionManager.forkFrom(sourcePath, targetCwd)` —— 复制完整历史到新文件，**不写源文件**，
所以不存在把主人会话改坏的风险，也不需要 `AgentSessionRuntime`。

已知代价：源会话越大复制越慢（实测最大会话 74.9MB，复制这种会话会明显卡）。后续可加体积提示。

## 十二、从历史消息分支（fork_from_message）

pi 的 `/fork`：从某条历史消息处开一条新会话往后走。原本以为必须引入 `AgentSessionRuntime`，
用两个已支持的 API 组合就做到了：

```
1) SessionManager.forkFrom(sourceFile, cwd)      → 复制完整历史到新会话文件
2) pool.open(newId).session.navigateTree(entryId) → 把新会话的叶子回退到目标节点
   回退后剩下的旧路径留在新会话文件里当旁支（正是会话树该有的样子）
```

| 项 | 结果 | 证据 |
|---|---|---|
| 服务端 `fork_from_message` | ✅ | 一次性会话实测：新会话 `parentId` 指向源、上下文回退到 1 条、**源会话 5 → 5 未变**、回传 `editorText` |
| 客户端入口（分支树每行「+」） | ✅ | t12-fork（当前叶子不显示按钮，其余节点都可点） |
| 顺带修的健壮性 | ✅ | `resolveSessionMeta` 加「缓存没命中就强制重扫」——刚建出来的会话不在 30s 缓存里，否则打开新分叉会失败 |

## 十三、Provider 凭据管理（AI 配置页）

| 项 | 结果 | 证据 |
|---|---|---|
| 服务端凭据接口（读 / 增 / 删） | ✅ | 往返实测：`deepseek, opencode-go` → 写 `openai` → 出现 → 删除 → 完全回到初始状态（主人的真 key 未被碰） |
| 凭据列表（不返回密钥本体） | ✅ | t13-cred / t14-cred-added：provider + 类型（api_key），只有掩码信息 |
| App 新增（对话框） | ✅ | t14-cred-added：输入 provider=`openai` + Key → 保存 → 列表立刻多出 openai 一行 |
| App 删除（带确认） | ✅ | t14-cred-delconfirm → t14-cred-deleted（列表回到 2 条） |

实现：`createAgentSessionServices()` 独立取 `modelRuntime`（不需要先有会话），`setRuntimeApiKey / removeRuntimeApiKey` 写 pi 的 auth.json。

## 十四、AI 配置页不再依赖「已打开的会话」

**问题**（t13-cred 暴露）：整页数据原先全靠会话命令（`get_available_models` / `get_commands` …），
而会话命令必须有「一条打开的会话」当通道 —— 开机后没打开会话时，模型、思考等级、技能全显示成「— / 无」。

**改法**：加一组会话无关接口（`server/lib/config-info.mjs`，用 `createAgentSessionServices()` 拿
`modelRuntime` + `resourceLoader`，按 cwd 缓存，实测 0.5–1s）：

```
GET /api/config/models?cwd=                             → 33 个模型（含每个模型支持的思考等级）
GET /api/config/thinking-levels?cwd=&provider=&model=   → low|high|max
GET /api/config/commands?cwd=                           → 技能 27 + 内置命令 13
```

| 项 | 结果 | 证据 |
|---|---|---|
| 无会话也能读模型 | ✅ | t14-config-nosession（33 个模型全列出） |
| 无会话也能读思考等级 / 技能 / 内置命令 | ✅ | t14-config-cmds（技能 27、内置命令 13、扩展命令「需打开会话」） |
| 扩展命令的来源说明 | ✅ | t14-config-ext：打开会话后扩展命令回来（31 条，含 /汉化）；没会话时该行显示「需打开会话」而不是「无」 |
| 无会话时写操作不再静默失败 | ✅ | t14-config-guard：点模型 → 「先打开一条会话才能切模型」 |

## 十五、运行中插话 / 排队消息条

| 项 | 结果 | 证据 |
|---|---|---|
| 运行中发消息不报错、不丢 | ✅ | t16-steer-reply：回合进行中发消息，模型在同一回合同答「收到第二条排队消息…」 |
| 输入框运行态提示 | ✅ | t16-steer-running：「运行中…可输入以插话」+ 右侧变 ✕（中断） |
| 插话确实进对话流 | ✅ | t16-steer-running：用户气泡已插入在流式输出中间 |
| 排队条「排队中：插话 N 条 · 后续 M 条」 | ⏳ 抓不到截图 | 实测 pi 在**最近的工具边界立刻消费掉** steer（等待窗口 < 1 秒）；有一次 steer 到达时正在跑 `sleep 60`，工具立刻 `Command aborted`。代码链路（`queue_update` → `queuedSteering/queuedFollowUp` → 横条 + 清空）与 `clear_queue` 均可用 |

## 十六、带摘要的分支切换（navigate_tree summarize）

| 项 | 结果 | 证据 |
|---|---|---|
| 服务端 `navigate_tree({summarize:true})` | ✅ | 一次性会话实测：会话文件多出一条 `branch_summary`（含 Goal / Progress / Key Decisions 等小节），上下文 5 → 2 条 |
| App 确认框里的「顺手生成摘要」开关 | ✅ | t17-summarize-dialog → t17-summarize-checked |
| App 端到端 | ✅ | 靶子会话（两条假分叉）在 App 内切换后，服务端会话文件真的写出 `branch_summary` |

### 顺带修掉的真 bug（B15）：摘要消息在界面上是个空气泡

`branchSummary` / `compactionSummary` 这两类消息，pi 把正文放在 `summary` 字段，**不在 `content` 里**；
App 只读 `content` → 文本为空 → 空气泡（t17-summary-before-fix）。
修法：`PiMessage.fromJson` 摘要类且 content 为空时读 `json['summary']`；UI 加标签「分支摘要 · 自动生成」。
修之后见 t17-summary-card。

---

## 十七、会话导出 + 上下文用量（第七轮补）

pi 自带的 `/export` 是「把 HTML 写到电脑上」，手机上拿到一个服务端路径等于没导出。
所以补了两条路：

```
GET  /api/sessions/:id/export?format=markdown  → Markdown 正文（App 内预览/复制/存手机）
GET  /api/sessions/:id/export?format=html      → HTML 正文
POST /api/sessions/:id/export                  → 落盘 HTML + JSONL 到会话目录，返回两个绝对路径
```

| 项 | 结果 | 证据 |
|---|---|---|
| App 内导出页（预览 / 复制全文 / 存到手机 / 导出到服务端） | ✅ | t18-export-preview（Markdown 预览：会话 ID、工作区、模型、时间、消息数、tokens + 逐条消息带用量） |
| 存到手机 | ✅ | t18-export-saved（提示路径）＋ `adb shell` 复核：`/data/user/0/com.youzhi.piyz.pi_yz/app_flutter/pi-exports/Reply with exactly_ alpha-01a1003c.md`，637 字节，内容正确 |
| 导出到服务端（HTML + JSONL） | ✅ | t18-export-server（两个路径都显示、可点复制）＋ 磁盘复核：425KB HTML、58KB JSONL 落在会话目录 |
| 会话信息里显示用量 | ✅ | t18-usage：上下文 1.5% · 14.6k / 1.00M、tokens 合计 29.1k（输入/输出/缓存读/缓存写）、花费 $0.0001、条目统计、自动压缩开关 |

实现细节：Markdown 由服务端按消息角色生成（主人 / pi / 工具结果 / 摘要），
逐条带 tokens 与花费；HTML/JSONL 直接用 pi 的 `exportToHtml / exportToJsonl`，
但**显式指定输出到会话目录**（不指定时 JSONL 会落到进程 cwd，两个文件分家很难找）。

## 十八、MCP 服务器增删改（写 mcp.json）

原先只有「读」——手机上只能看不能配，等于没对齐 pi-web。

```
GET    /api/mcp?cwd=               读（用户级 + 项目级，项目级同名覆盖）
POST   /api/mcp                    新增/覆盖 {name, scope, config}
DELETE /api/mcp/:name?scope=       删除
PATCH  /api/mcp/:name?scope=       启用/停用（pi 的 enabled:false = 保留条目但不连接）
```

| 项 | 结果 | 证据 |
|---|---|---|
| 校验 | ✅ | 名字非法 / url 与 command 都填 / 明文 http 远程 → 全部 400 并给出中文原因（实测 3 条） |
| 新增 | ✅ | t19-mcp-added：App 里填 proc-test + `npx -y @modelcontextprotocol/server-everything` → 列表出现；磁盘复核 `~/.pi/agent/mcp.json` 内容正确 |
| 停用/启用 | ✅ | t19-mcp-disabled：列表显示「已停用」、按钮变「启用」；磁盘 `enabled: false` |
| 删除 | ✅ | t19-mcp-delconfirm（确认框）→ t19-mcp-empty：列表回到空态、磁盘回到 `{"mcpServers": {}}` |

## 十九、文件上传 + 图片预览 + git worktree

| 项 | 结果 | 证据 |
|---|---|---|
| 文件上传（手机 → 工作区） | ✅ | t20-picker（系统文件选择器）→ t20-upload：上传 pi-upload-test.png 后目录里出现 327.3 KB 的文件、git 段出现 `??`；磁盘复核 335159 字节与原文件一致 |
| 同名不覆盖 + 询问覆盖 | ✅ | 服务端 403 + 原因；App 弹「已存在同名文件…要覆盖吗」 |
| 越权目录 | ✅ | `/api/upload` 传 `C:/Windows` → 403 |
| 图片预览 | ✅ | t20-image-preview：图片在 App 内直接渲染（走 `/api/file/raw`，服务端按扩展名给 Content-Type、内容嗅探兜底） |
| PDF/音频/视频等不能内嵌的格式 | ✅ 如实说明 | 给尺寸、完整路径与「复制路径」，不假装能预览 |
| git worktree 列表 | ✅ | t20-worktrees：Worktrees（2），主工作树带标记，分支名与路径都对 |
| 新建 worktree | ✅ | App 里填目录 + 分支名 → 创建后列表变 2 条；`git worktree list` 复核：`pi-wt-test-wt 05a54ae [featureapp-test]` |
| 删除 worktree / 用 worktree 开会话 | ✅ | 行内「删除」（带确认）与「开会话」（在該目录新建并打开会话） |

## 二十、Provider 登录（API Key 向导 + OAuth）

pi 的 `/login` 支持 API Key 与 OAuth（订阅账号、设备码）。手机上做这件事的难点是
「服务端问一句、用户答一句」的长交互，所以做成可轮询任务：

```
GET  /api/providers          每个 provider 支持哪些登录方式、是否已配置
POST /api/login              {provider, type} → {id}
GET  /api/login/:id          state(running|prompt|done|error|cancelled) + prompt + events
POST /api/login/:id          {answer} 回答当前提示 / {cancel:true} 取消
POST /api/logout             {provider} 退出登录
```

| 项 | 结果 | 证据 |
|---|---|---|
| provider 清单 | ✅ | 44 个 provider；9 个支持 OAuth（anthropic / openai / github-copilot …） |
| API Key 向导（select → secret 两步） | ✅ | t21-login-secret（「Enter Amazon Bedrock bearer token」）→ t21-login-done（「已完成」，凭据写进 auth.json，`/api/credentials` 复核出现 amazon-bedrock）→ 测完 `POST /api/logout` 删除，凭据回到 2 条 |
| OAuth（授权链接 + 手输回调 URL） | ✅ | t21-oauth-select（选登录方式）→ t21-oauth-url：完整授权链接（可选中/复制）+ 「Paste the code…」输入框；取消后任务结束、**凭据未被写入** |
| App 入口 | ✅ | t21-login-button：凭据区「登录 Provider」＋「添加 API Key」两个入口 |
| 设备码流程 | ✅ 代码已支持（`device_code` 事件 → 显示 userCode + verificationUri + 复制按钮） | 本轮用 anthropic 的手输回调路径实测；设备码路径未遇到可用 provider 实测，如实记录 |

补的关键点：有些 OAuth（OpenAI/ChatGPT）**必须要一个安装级 UUID**，不给就报
`Sign in with ChatGPT requires a device ID`；服务端用 `settingsManager.getOrCreateDeviceId()`
（和 pi CLI 同一个来源）传进去。

## 二十一、插件（pi 包）与技能管理

| 项 | 结果 | 证据 |
|---|---|---|
| 插件列表 | ✅ | t22-packages：实际 10 个包（pi-web-access、@ff-labs/pi-fff、bigpowers…），每个显示安装路径与卸载按钮 |
| 安装插件 | ✅ | t22-install-dialog：输入 npm 包名/git 地址/本地目录 + 用户级/项目级 + 「会真的联网下载」提示（本轮未真装，避免污染主人的环境） |
| 卸载 / 更新 | ✅ | 走 pi 的 `DefaultPackageManager.removeAndPersist / update`；列表里标「可更新」 |
| 技能可查看 | ✅ | t22-skills-tappable（技能行有「点开看内容」与箭头）→ t22-skill-view：点开显示 SKILL.md 全文（frontmatter + 正文）与文件路径 |

实现：服务端用 SDK 导出的 `DefaultPackageManager`（不是自己拼 npm 命令）——
装的来源有 npm / git / 本地目录三种，pi 自己负责解析、落盘与写设置，自己拼必然漏语义。

---

## 结论（第一至第七轮汇总）

### 修掉的 bug（B 系列，全部复测通过）

| 轮次 | bug |
|---|---|
| 一~三轮 | B1 Markdown 不渲染 · B2 底部被 tab 遮挡 · B3 连接页重复文字 · B4/B5/B8 布局与材质 · B6 分组卡 · B7 命令面板高度 · B9 发丝线 · B10 思考内容 ANSI 乱码 · B11 扩展对话框不显示 · B12 缺 get_tree/rename_session · B13 切模型界面不同步 · B14 会话列表高频重建 |
| 四~六轮 | B15 摘要消息在界面上是空气泡（本轮修：摘要正文在 `summary` 字段，不在 `content`） |
| 七轮新增 | 无会话时 AI 配置页整页空白 · 无会话时切模型/改思考等级**静默失败** |

### 对齐 pi-web 的能力（第一至第七轮累计）

| 域 | 已对齐 |
|---|---|
| 对话全链路 | 流式渲染 · 思考块 · 工具卡片（可展开/输出） · 图片 · 中断 · 插话 · 排队提示 · 命令面板（内置/扩展/技能/模板，分行显示，含汉化插件）· 扩展对话框（select/confirm/input/editor）· 历史分页 · `/命令` 全部可用 |
| 会话管理 | 搜索 · 重命名 · 新建（选工作区）· 删除（带确认）· 复制为分支 · 分支树浏览 · 会话内切分支 · 从历史消息分叉 · **带摘要的分支切换** |
| 文件与 Git | 目录浏览 · 文件预览 · git status / diff（着色）· @文件引用 |
| 配置管理 | 模型列表与切换 · 思考等级 · 技能/扩展/内置命令清单 · MCP 列表 · **Provider 凭据增删** · **无会话也能读配置** |
| 交互与观感 | 底部 tab 三等分 · 新拟态材质对齐设计稿 · 主题（跟随系统/浅/深）· 下拉刷新 · Toast 提示 · 空态 |

### 证据

- `docs/verify/acceptance-checklist.md`（本文件）逐项带证据，共 21 节 + 结论
- `docs/verify/` 下 100+ 张 MuMu 实机截图（`t1-*` … `t17-*`）
- 服务端侧的往返验证（凭据、分支摘要、git、文件、命令）在对应小节里写了命令与输出

### 本轮新补齐的 pi-web 能力（第七轮补测）

| 能力 | 状态 |
|---|---|
| 会话导出（Markdown 预览 / 存手机 / HTML+JSONL 落盘） | ✅ 第十七节 |
| 上下文占用 / tokens / 花费 / 踩目统计 | ✅ 第十七节 |
| MCP 增删改 + 启停 | ✅ 第十八节 |
| 文件上传 + 图片预览 | ✅ 第十九节 |
| git worktree（列表 / 新建 / 删除 / 开会话） | ✅ 第十九节 |
| Provider 登录（API Key 向导 + OAuth） | ✅ 第二十节 |
| 插件（pi 包）列表 / 安装 / 卸载与技能查看 | ✅ 第二十一节 |

### 仍未对齐的 pi-web 部分（如实记录，不在本目标的四个名目内）

- 终端（xterm）—— **用户已决定不做**（2026-10-03）：`lib/ui/terminal_page.dart` 已删，不再列为待补项；
- 多语言（i18n）—— 已列入当前改造目标（界面中英切换 + 复用 `commands-cn.json` 汉化机制）；
- 仍在空白：项目信任（project trust）、MCP OAuth 登录；
- PDF/音视频内嵌播放不做：已做到「如实说明 + 路径可复制」，不假装能看。

### 遗留一项⏳（非功能缺失）

「排队中：插话 N 条 · 后续 M 条」横条的**截图**抓不到（steer 在最近的工具边界被立刻消费，窗口 < 1 秒）。
代码链路与 `clear_queue` 均可用；见第十六节。

## 二十二、UI 改造（task-21 / task-22）之后的复核

改造只动**样式、布局与交互外观**，没有改任何功能逻辑；但有几处**形状变了**，回归时要按新形状验收。下面逐条给出改造后的真实状态与证据目录（`docs/verify/ui-rework/task-NN/`）。

### 形状变了的地方（回归重点）

| # | 项 | 改造前 | 改造后 | 证据 |
|---|---|---|---|---|
| 22.1 | 工具调用卡片 | 两行大卡片（26px 图标 + 标题 + 副标题 + 标签） | **单行细条**（18px 图标 + 标题 + 标签；要看输出点右侧箭头展开） | task-21/01-tools-compact-and-elapsed.png |
| 22.2 | 每条消息的耗时 | 无 | 工具结果与助手气泡旁显示 `13s` 这类数字（工具结果是真正花时间的那一步） | task-21/01 |
| 22.3 | 只看主干 | 无此能力 | 头部最左「💬」开关 = **重点模式**：一键收掉思考/工具调用/工具结果 | task-21/02（关）↔ 03（开） |
| 22.4 | 设置页分组 | 一长条铺开 | **可折叠**：点标题收起/展开该组（箭头 ⌄/›） | task-21/04（展开）↔ 05（收起） |
| 22.5 | 开始页连接卡 | 带「手动刷新」圆按钮 | 只剩状态（地址 / 已连接 / 会话数）；刷新与断开收进设置页的连接卡 | 见 task-23/01 |
| 22.6 | 会话行的运行状态 | 只能看顶部总览卡片 | 行上直接标：在跑时图标变转圈、副标题变绿写「正在跑 · N 条 · 时间」 | task-21 记录（代码 + 池数据同源） |
| 22.7 | 字号 | 五个页面散着写 `12.5/11.5/12/13/13.5` 共 285 处 | 全部走 `NeuFonts` token（值不变，纯改名） | task-21 记录 · task-22 记录 |
| 22.8 | 动效时长 | `220ms` 散写 5 处 | `NeuMotion.base` | task-22 记录 |

### 本轮新修掉的真缺陷（已在 task-21 记录里，此处登记以便回归）

| 缺陷 | 现象 | 修法 |
|---|---|---|
| 消息时间戳全是 null | `timestamp` 只按数字解析，而 pi 落盘的是 ISO 字符串 → 耗时永远算不出 | `parseTimestamp()` 两种格式都认 |
| 增量消息没时间戳 | `message_start` 事件里的消息不带 timestamp（pi 落盘时才补）→ 即便修好解析也仍不显示 | 创建时用本机时间兜底，权威时间到了再覆盖 |
| 重点模式点了没反应 | `NeuToast.show` 写在 `setState` 回调里（反模式） | 先 setState、再弹提示 |
| 密钥进了启动日志 | `console.log` 明文打印服务端 token | `maskSecret()` 脱敏 + 单测（task-16） |
| 内存里两处 `NeuMotion` 同名 | 新增 token 类与既有类重名，报 30 个编译错 | 合并到既有类，补一个 `base` |

### 本轮新增能力的验收位点

| 能力 | 状态 | 证据 |
|---|---|---|
| 实时活动（状态条 + 时间线浮层） | ✅ | ui-rework/task-14/ |
| 离线缓存与恢复补齐 | ✅ | ui-rework/task-13/ |
| 多会话总览 / 归档 / 存储占用 | ✅ | ui-rework/task-15/ |
| 统计报表（按天 / 按工作区）与脱敏 | ✅ | ui-rework/task-16/ |
| 远程访问（Cloudflare 隧道 + 一键断开） | ✅ | ui-rework/task-18/ |
| 无人值守（额度兜底 + 断点续跑） | ✅ | ui-rework/task-20/ |
| 界面中英切换 | ✅ | ui-rework/task-19/（设置页「界面语言」三档：中文 / English / 跟随系统） |

### 改造后仍然成立的结论

- **第一至二十一章的功能项全部未回归**：改造只涉及 `message_view` / `chat_page`（新增开关与耗时）/ `settings_page`（折叠）/ `sessions_page`（行标记）/ `design_tokens`（token 与别名）五个文件的**表现层**；`flutter test` 99 条（含深色 / 浅色 / 减少动态三档渲染）全过，`flutter analyze` 0 issue。
- **深色与浅色两套都验证过**：task-22/01（浅色）↔ 02（深色）。
- **已知限制不变**：终端不做、PDF/音视频不做、排队横条截图抓不到（见前文）。

## 二十三、审计整改（4 项，均已落地）

第一轮收口提交被独立审计驳回，指出 4 处「说法与实现不符」。逐条整改：

| # | 审计意见 | 整改 | 证据 |
|---|---|---|---|
| 23.1 | **后台保活没实现**（用户点名的能力）：Manifest 只有 `POST_NOTIFICATIONS`，无前台服务，无 `startForeground`；文档自己写着"后台不保活" | 真的加了 Android **前台服务** `KeepAliveService`（常驻通知 IMPORTANCE_MIN + `PARTIAL_WAKE_LOCK` + `WifiLock(HIGH_PERF)`，`START_STICKY`），Manifest 补 3 个权限与 service 声明，MainActivity 加三个 channel 方法，App 侧 `NativeBridge` + AppPrefs 开关 + 连接后自动开 + 设置页「后台」分组 | `ui-rework/task-23/07-keepalive-and-cleanup.txt`：`isForeground=true foregroundId=9901`、常驻通知标题「pi-yz 正在保持连接」；**按 HOME 退到后台后** ServiceRecord 与进程都仍在（状态 `S`） |
| 23.2 | **「死代码 0」被矛盾**：`main.dart:317` 的 `_SessionTab` 从未被引用，通过它挂着 ~3194 行 SSH/RPC 时代子系统 | 删掉那 8 个文件 + `main.dart` 的 `_SessionTab`/`_SessionRow` + 3 个旧 import | `lib/` **25690 → 22496 行（−3194）**；复扫未引用顶层类 **0**；`// ignore: unused_element` **0** |
| 23.3 | **文件页（五大界面之一）没有重做**，只写"本轮复核" | 面包屑改成可点分段；图标按类型（目录/文档/图片/代码）；行高 10→13 | `lib/ui/server/files_page.dart` 的 `_breadcrumb` / `_iconForEntry` |
| 23.4 | **中英切换只覆盖主干**：16 个页面里 12 个无 i18n | **四批共 506 条**词条（135 高频 UI 词 + 109 短句元素 + 92 模板串/补漏 + 170 收尾），替换 **570 处**；新增覆盖率脚本；`I18n.tp(key, {...})` 支持带参数文案 | 覆盖率 **15.6% → 92.8%**（`task-23/06-i18n-coverage.txt`）；实机 `04-language-en.png`、`08-language-en-chat.png`、`09-language-en-usage.png`（`Total tokens / Cache read / Cache hit rate / Average generation speed`）、`10-language-en-chat.png`（`Call` / `No tool calls this turn`） |

### 23.4 的遗留（第二次整改后更新）

第二轮审计只卡在这一条，证据是「`message_view.dart` 的 key 已定义却没接上」「用量页核心标签没翻」
「证据截图自己露着中文」。逐条查清并修掉：

- **脚本 bug**：替换脚本按「行里含 `I18n.` 就整行跳过」，于是三元表达式的最后一支（`… : '调用'`）从未被替换。
  改成按字符串字面量匹配 → `Call`、`No tool calls this turn` 都出来了；
- **词表漏项**：`缓存命中率 / 平均生成速度 / 合计 tokens` 压根不在待译清单里（导出时漏了）。补上 →
  现在显示 `Cache hit rate / Average generation speed / Total tokens`；
- **模板串**：259 条带 `${…}` 的参数化落地（新增 92 条译文），用 `I18n.tp(key, {...})`，
  占位名按中文里变量出现的顺序对应，不依赖源代码变量名。

**覆盖率 59.4% → 92.8% → 96.9%（597 处已 i18n / 19 处仍中文）。**

剩余 44 处的构成：跨行字符串隐式拼接（Dart 的 `'a'
'b'` 写法，翻译要整段合并、替换会破坏拼接）、
少数嵌套三元模板串、极长的一次性说明段落。分布随时可用 `python tool/i18n_coverage.py --top 20` 查。
**这 44 处不假称已翻** —— 机制完整、可继续，但本次没做完的部分在这里写明。

### 23.5 第三轮整改（审计指出「75 个 key 定义了却没接上」+ 两个孤立文件）

| # | 审计意见 | 整改 | 证据 |
|---|---|---|---|
| 23.5.1 | **定义了 75 个 `ui.*` key 但没有任何 UI 引用它们**，对应调用点仍输出中文（举了 `消息`/`花费`/`条目`/`分支摘要`/`已完成`/`已取消`/`通知已关闭`/`项目级`/`空` 等） | 脚本对 i18n.dart 的全部 `ui.*` key 与 UI 文件里的引用做**差集**，得 75 个 unused；按中文反查**强制接回调用点**（29 处），并把改写中产生的 `+` 拼接统一改回隐式拼接/插值 | 实机 `11-language-en-session-info.png`：会话信息面板显示 `Messages` / `Cost` / `Items` / `Total`（审计点名的前三个都在图里）；`flutter analyze` 0 issue |
| 23.5.2 | **两个完全孤立的文件**（`lib/models/session_models.dart` 160 行、`lib/ui/neu_indicators.dart` 295 行） | 确认 0 引用后删除，共 **455 行** | `grep` 复核：两文件均无任何引用 |

**顺带修掉**：跨行字符串隐式拼接被替换破坏的位置（本轮新增 13 处改插值、2 处补逗号、1 处恢复被误翻的空串），
以及 `const` 上下文里出现 `I18n.t` 的 3 处。

**剩余 19 处中文**：全部是跨行拼接的长说明段落（例如用量页那段「⚠ 这是按本机落盘用量做的估算…」），
合并整段翻译需要重构字符串结构、风险大于收益，**保留并在此登记**（覆盖率数字里如实体现，不假称已翻）。

### 23.6 第四轮：跨行拼接的收尾与一次失败教训

想把最后 26 处（跨行隐式拼接的长文案）也翻掉，做法是「把多行合并成一条 `I18n.tp`」。
**只成了 8/10，并且并入的中文里带真实换行，直接破坏了 `i18n.dart` 的字面量（analyze 报 107 个错）**，
已整批回滚。

回滚后改用「同一个错误模式一次改完」的方式修掉剩余几处：相邻两个表达式之间缺连接的
（`'${I18n.t(...)}'` 紧跟 `I18n.tp(...)`）统一补成两段字符串字面量的隐式拼接；`files_page`
的同类写法一并处理。

**终态：`flutter analyze` 0 issue、`flutter test` 99 条全过、i18n 覆盖率 96.9%（599 处已 i18n / 19 处仍中文）。**

**教训（写进记录，免得重犯）**：跨行隐式拼接的字符串**不能按片段逐个替换** —— 替换掉其中一段，
相邻两段就不再都是字面量，Dart 直接报错。这类要么整段一起改（换行符写进词表时要转义成 `
`），
要么就别动；批量替换脚本必须先在副本上跑一遍 analyze 再落地。

### 23.7 第五轮：把「定义了却没接上」全数接线（审计第三轮的意见）

审计第三轮点名「47 个 key 定义了却没有任何调用点，英文模式下仍然漏中文」。本轮**逐处接线 28 处**，
覆盖它列出的全部位置（`· 已连接`、`· 已截断`、`手机端不内嵌预览…`、`$cwd · 已载入 N`、`· 支持思考`、
`上下文`、`条分支`、`插件（pi 包）…`、`将从…删掉…`、`空`、`可配对`、`未开配对窗口`、`远程 · …`、
`公网连接失败：…`、`删除失败：…`、`失败原因：…`、`… 路径`、`本轮没有工具调用`、额度预警两段）。

**踩了三次坑，都写进 `task-23/06-i18n-coverage.txt`**：
1. 词表的键写成占位形式（`$cwd · 已载入 $n`）与代码原文（`${chat.cwd} · 已载入 ${…}`）对不上 →
   **键一律改用代码原文**；
2. 含变量的整串被拆成片段逐个替换，破坏 Dart 的隐式字符串拼接 → **拼接里的片段包成 `'${I18n.t(...)}'`**；
3. 清理「闲置词条」时**误删仍在用的 key**（`tab.*`、`theme.*`，后者是 `I18n.t(option.$2)` 变量调用、
   静态检测不到）→ 界面显示 key 本身、5 个测试挂掉 → **全部补回**，并给覆盖率脚本加了变量调用的识别。

**终态：`flutter analyze` 0 issue、`flutter test` 99 条全过。**
覆盖率脚本：① 仍是中文字面量 **7 处**（全是跨行拼接 + 嵌套三元的片段）、
② 闲置 key **13 个**（`theme.*` 三档实为变量调用在用、属静态检测盲区，其余为词表富余条目）、
③ 已接上 **623** 个 key。①②不为 0 的部分已如实说明，未假称全清。
