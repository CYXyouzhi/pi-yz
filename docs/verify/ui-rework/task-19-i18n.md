# task-19 · 界面中英切换 + 复用电脑端汉化（已完成）

## 做法
```
服务端：~/.pi/agent/commands-cn.json（48 条，按命令名）
        ~/.pi/agent/hanhua-auto.json（573 组「原文→中文」，按原文串 + 按包统计）
          └─ server/lib/hanhua.mjs ──► 给每个命令补 descriptionZh / descriptionZhSource
                                         ├─ /api/config/commands
                                         └─ get_commands  （两条路径都过）
                                        ──► 给插件包补 zhCount（这个包被汉化了几处）
App：lib/server/i18n.dart ──► 30 条界面文案（zh/en 两栏）
      AppPrefs.lang（zh | en | system，落 shared_preferences）
      └─ Tab 栏 / 开始页 / 设置页段标题 / App 设置 / 输入框占位 / 命令说明
```
**不另造翻译表**：中文说明直接读电脑端已有的 commands-cn.json，
两份界面共用一套术语；汉化文件缺失时命令列表照常返回（只是没有中文）。

## 验证
| 项 | 证据 |
|---|---|
| ① 语言可切换且持久 | 截图 `task-19/i1-zh.png`（英文，跟随系统+MuMu 系统语言为英文）→ `i2`（语言行）→ `i3-chinese.png`（切中文：工作区/外观/界面语言 + Tab 栏全部变中文）→ `i4-persisted.png`（**重启 App 后仍是中文**，Tab 栏「开始/会话/设置」、输入框「输入消息」） |
| ② 三档可选 | 界面语言三格：中文 / English / 跟随系统（截图 i2、i3） |
| ③ 复用电脑端汉化（两份表都用了） | `curl /api/config/commands`：40 条命令 → **22 条来自 commands-cn、17 条原文本就是中文、1 条未翻译**；`descriptionZhSource` 字段把来源标在数据里 |
| ③b 第二份表 hanhua-auto.json | `curl /api/packages`：每个插件包带 `zhCount`（例：pi-token-speed 40 处、pi-goal-x 31 处、@narumitw/pi-plan-mode 30 处）；App 插件列表里逐条显示「电脑端已汉化 N 处文案」（截图 c3） |
| ④ 命令/插件/技能/MCP 列表中文注释 | 会话内 72 条命令（扩展 32 / 技能 27 / 内置 13），**扩展命令 32 条里 22 条中文**；技能与内置命令中文（截图 c3 内置命令 13 条全中文）；MCP 条目中文注释到「含义/副作用」一层（截图 c7：本地命令型 MCP（在电脑上起子进程，能读写本机文件）· 用户级 · 停用） |
| ⑤ 未翻译项不假装翻过 | 唯一没中文的 `skill:playwright-cli` 与扩展命令 `/websearch`：中文模式下显示英文原文 + 标「未翻译」——实机截图 c6（命令面板里 `Open web search curator（未翻译）`） |
| ⑤ 文案不硬编码 | 界面文案集中在 `lib/server/i18n.dart`（30 条），找不到 key 时返回 key 本身（漏翻一眼可见） |

## 术语对照（节选）
| 中文 | English |
|---|---|
| 会话 | Chat / session |
| 工作区 | Workspace |
| 模型 / 思考等级 | Model / thinking level |
| 技能命令 | Skill command |
| 用量 / 缓存命中 | Usage / cache hit |
| 运行中（可插话） | Running (type to steer) |
| 未连接 | Not connected |
| 跟随系统 | System |

## 覆盖范围（不糊）
- 已接语言包：底部 Tab、开始页状态文案、设置页 5 个段标题 + 界面语言 + 外观 + App 设置主要项、会话页输入框占位与空态、命令说明。
- **未逐条翻译**：聊天页消息区的细节文案（工具卡片状态、diff 标题等）、AI 配置/文件浏览/用量/日志等二级页、各类错误提示。
  这些在英文模式下仍是中文 —— 机制已就位（挪进 `i18n.dart` 即可），但这次没翻完，故明确记为遗留。
- `hanhua-auto.json` 里是「汉化扩展」给 CLI 打的补丁串（按插件 dist 文件分组），App 复用了两种用法：
  ①按原文串反查扩展命令的中文说明；②按包统计「已汉化几处」并显示在插件列表里。
  当前扩展命令的说明串与表里的原文**没有精确重合**（表里多为整句提示），所以第①种用法命中 0 条；
  这条路线保留着（新汉化项一旦对齐就会自动生效），但不夸大成“已生效”。
- 测试细节：验证 MCP 中文注释时我临时加了一台 `proc-test`，验证完已用
  `DELETE /api/mcp/proc-test?scope=user` 删除，`~/.pi/agent/mcp.json` 回到 `mcpServers = {}`。
  （用 curl 注入中文时描述串被终端编码弄成了乱码 U+FFFD —— 那是测试命令的问题，不是 App 写入路径的问题；
  App 走 Dart 的 JSON 编码，中文正常，截图 c3/c6/c7 里的中文即为证。）
