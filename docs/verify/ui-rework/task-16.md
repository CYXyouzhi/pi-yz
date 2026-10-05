# task-16 · 统计报表与安全（已完成）

四条合同逐条。实机截图在 `task-16/`，与 JSONL 的独立对照数据在 `task-16/07-jsonl-compare.txt`。

| # | 合同 | 状态 | 证据 |
|---|---|---|---|
| ① | 报表页：按天与按工作区看 token/花费趋势（数据来自落盘 usage，注明口径），有截图 | ✅ | 报表页在「会话信息 → 用量明细」。**按天**：`01-usage-byday.png` —— 「按天趋势（最近 10 天）」，每天一行 = 日期 + 相对横条 + `588.15M · $10.944`；**按工作区**：`02-usage-byworkspace.png` —— 每个工作区一行 = 名字 + tokens + 花费 + 「51 条会话 · 1096 轮 · D:\powershell」；**口径**写在页面里：`05-usage-page-header.png` 顶部「数字来自落盘会话记录，不是估算」，趋势区块下方「口径：按每条 assistant 落盘条目的 usage 累加，日期取该条目的时间戳；tokens = 输入 + 输出 + 缓存读 + 缓存写」 |
| ② | 报表数字与 JSONL 对得上（抽查对比写进验证记录） | ✅ | 见 `07-jsonl-compare.txt`（脚本**不复用服务端代码**，自己逐行读 JSONL）。**抽查一 · 单会话逐字段**：会话 `01a0cb77`，独立复算 `tokens=246,008 / cost=0.004050 / turns=16`，服务端 `246,008 / 0.004050 / 16` —— **三项都是 0 差异**。**抽查二 · 按天全量**：会话集合用 `/api/sessions` 的 id 列表对齐后，25 天里 **24 天逐字节一致**；唯一差异在 `2026-08-29`（老会话批量区），差 `-25,527`，占总量 **0.0010%**，且方向单一（两次读取之间那批老会话的条目边界），不影响可用性 |
| ③ | 敏感信息不落日志（API Key、token 脱敏），有代码与截图证据 | ✅ | **代码**：新增 `server/lib/secrets.mjs`（`maskSecret` / `redact`），服务端启动日志改成 `token     : pimo…26（12 位，已脱敏）`（原文见 `06-server-log-redacted.txt`，改之前这里是**完整 token 明文** —— 这是本轮修掉的一个真实泄漏点）。**测试**：`server/test/secrets.test.mjs` 5 条（短串全遮、长串只留头 4 尾 2、原串不出现在结果里、redact 能替换整段文本里的密钥、太短的串不动），`node --test` 全过；App 侧 `test/secrets_test.dart` 4 条钉住 `maskToken`。**实机**：`03-diag-token-masked.png` —— 诊断页「当前连接参数」里 `token  pi********26` |
| ④ | 复制/分享/截图不泄露密钥 | ✅ | **截图**：`04-conn-token-obscured.png` —— 连接表单里 token 一栏是 `••••••••••`（`obscure: true`），截图拿不到明文；诊断页同样脱敏（见 ③）。**导出/分享**：会话导出（Markdown/HTML/JSONL）与消息分享只带会话正文，`export_page.dart` 与分享路径里不含 token（代码检索确认）。**顺带修准**：`maskToken` 原来对「长度 ≤4」一律给 4 个星，会让 3 位 token 看起来像 4 位，改成按真实长度打星（`test/diagnose_test.dart` 同步更新） |

## 这轮加的代码

```
服务端 server/lib/usage.mjs         usageSummary 增加 byWorkspace（工作区 / tokens / 花费 / 轮数 / 会话数）
      server/lib/secrets.mjs        新增：maskSecret / redact
      server/index.mjs              /api/usage 支持 ?days=；启动日志 token 改脱敏
      server/test/secrets.test.mjs  5 条单测（node --test）
App   lib/server/server_types.dart  UsageSummary 增加 byDay / byWorkspace
      lib/ui/server/usage_page.dart 「按天趋势（最近 10 天）」（含横条）与「按工作区」两个区块
      lib/server/diagnose.dart      maskToken 短串规则与服务端对齐
测试  test/secrets_test.dart        4 条：空值 / 短串全遮 / 长串留头尾 / 原串不出现
```

## 这轮修掉的真实泄漏点

| 问题 | 现象 | 修法 |
|---|---|---|
| 启动日志明文打印 token | `server/index.mjs` 启动时 `console.log(\`  token     : ${TOKEN}\`)` —— 启动日志是最常被截图、贴群、贴 issue 的东西，等于把钥匙一起贴出去 | 改成 `maskSecret(TOKEN)`，并把脱敏函数单独成文件、配单测（这类 bug 写错了不会报错，只会静默泄漏） |
| `maskToken` 谎报长度 | 长度 ≤4 时固定返回 `'****'`，3 位 token 看起来像 4 位 | 按真实长度打星；与服务端 `maskSecret` 同一套规则 |

## 复现步骤（MuMu 上自己再看一遍）

1. 会话页 → 顶部 `ⓘ` → 会话信息 sheet → 往下滚到「用量明细（逐轮 tokens / 速度 / 成本）」→ 进报表页。
2. 报表页往下滚：先看到「按 provider」，再是「**按天趋势（最近 10 天）**」和「**按工作区**」。
3. 设置 → 连接 → 点连接卡进连接页：`token` 一栏是掩码（`••••••••••`），截图看不到明文。
4. 连接页底部「连接诊断」→ 诊断页「当前连接参数」里 token 显示成 `pi********26`。
5. 电脑端重启服务端，看启动日志第一段：`token     : pimo…26（12 位，已脱敏）`，没有明文。
6. 想自己核对数字：`curl "http://127.0.0.1:30142/api/usage?days=45" -H "Authorization: Bearer <token>"`，与 `07-jsonl-compare.txt` 里同一套方法自己算一遍。
