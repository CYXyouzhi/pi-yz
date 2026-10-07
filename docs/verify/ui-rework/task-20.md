# task-20 · 无人值守：额度用尽自动切备用 provider 并从断点继续（已完成）

五条合同逐条。证据在 `task-20/`。

| # | 合同 | 状态 | 证据 |
|---|---|---|---|
| ① | 已有成果：插件写好且实测通过（假 provider 触发额度错误 → 自动切到 deepseek 并答出结果） | ✅（本轮补了「在服务端 pi 里也生效」这一层） | 插件在 `pi-plugin/extensions/quota-fallback.ts`（与 `yz-server` 同一个包，`pi install ./pi-plugin` 一起装）。**本轮新验证**：把它跑在**服务端的 pi 会话**里（无人值守真正发生的地方）—— 往会话发 `/quota-fallback` 得到 `{"disposition":"handled"}`（说明命令被识别 = 扩展已加载），再发 `/quota-fallback switch` + 一条普通消息，落盘的 provider 从 `opencode-go/deepseek-v4.1-flash` 变成 **`deepseek/deepseek-flash`**（见 `02-switch-and-resume.txt` 的【A】段） |
| ② | 补齐：真实 GoUsageLimitError 文本比对（没触发就把错误原文加进匹配表并重测） | ✅ | 从 `~/.pi/agent/sessions` 的**真实会话记录**里搜出两种额度类报错原文：<br>· `402: {"message":"Insufficient Balance","type":"unknown_error",...}` ← **旧匹配表没认出来**（表里只有 `available balance`，那是另一家的措辞）<br>· `413 Failed to buffer the request body: length limit exceeded` ← 有 "limit" 字样但**不是额度问题**，不该匹配<br>**改法**：把 `insufficient balance` 加进 `DEFAULT_PATTERNS`（用户级与项目内两份同步改），并保留 413 那条**不匹配**。**重测**：新增 `server/test/quota-fallback-patterns.test.mjs`，它**从插件源码里把匹配表读出来**再验证（不另抄一份，避免漂移），5 条用例全过（`01-patterns-test.txt`）——含两家真实报错原文、七种各家的额度文案、四种普通报错不该误判 |
| ③ | 断点续跑：每步落盘，人为中断（杀进程/断网）后能从最后一个已完成子项继续，有日志为证 | ✅ | 实测（`02-switch-and-resume.txt` 的【B】段）：发一条「分三步、每步一次 bash」的任务 → 第一步 `echo step-1` 完成并**落盘**（`04:52:05 toolResult step-1`）→ 在它跑 `sleep 25` 时**直接 kill 服务端** → 重启服务端（`[pool] 打开会话` 从磁盘恢复）→ 发「继续」→ agent 回「第二个调用返回 No result provided，所以我无法确认它是否真的执行完毕」：**它记得第一步已完成、没有重跑第一步**，直接从断点往下走。<br>另外插件本身也落盘：切换时 `pi.appendEntry("quota-fallback", {at, from, to, reason, index})` 写进会话 |
| ④ | 额度预警与自动切换配合（与 task-8 呼应） | ✅ | 两处改动：**①预警文案改准** —— 原来写「额度用尽时 pi 会停，App 会自动切到另一个 provider」，实际切换发生在**电脑端插件**而不是 App（`usage_page.dart` 已改成「电脑端的额度兜底插件（quota-fallback）会把会话切到备用 provider 并让 agent 接着干，App 只负责把『已切换到 xxx』如实显示出来」）；**②App 能看见切换** —— `chat_reducer.dart` 新增处理 `model_change` 事件，把它显示成一条状态提示（`已切换到 provider/model`），这样第二天醒来能看到「什么时候被切过」 |
| ⑤ | 把插件用法、开关、局限写进文档（含 /quota-fallback 命令与配置项） | ✅ | `pi-plugin/README.md`：两个扩展各自的用途、安装方式（`pi install ./pi-plugin`）、`/mobile` 与 `/quota-fallback` 的全部子命令、`~/.pi/agent/quota-fallback.json` 的每个配置项（`enabled` / `fallback` / `patterns` / `maxPerSession`）、**四条局限**（只认关键字、不区分额度与限流、不保证接得对、备用 provider 得有凭据），以及「怎么不靠肉眼验证它在跑」的三条命令 |

## 这轮改的代码

```
插件  pi-plugin/extensions/quota-fallback.ts   匹配表加 "insufficient balance"（真实 DeepSeek 报错原文）
      pi-plugin/package.json                   pi.extensions 里加上 quota-fallback.ts
      ~/.pi/agent/extensions/quota-fallback.ts 同步（当前环境立即生效）
      pi-plugin/README.md                      新增：用法/开关/配置/局限
测试  server/test/quota-fallback-patterns.test.mjs  5 条：从源码读表 + 真实报错逐条比
App   lib/server/chat_reducer.dart             处理 model_change 事件 → 显示「已切换到 …」
      lib/ui/server/usage_page.dart            额度预警文案改准（切的是电脑端插件，不是 App）
```

## 这轮发现并修掉的问题

| 问题 | 现象 | 处理 |
|---|---|---|
| 真实额度报错没被认出来 | DeepSeek 官方余额不足返回的是 `Insufficient Balance`（402），而匹配表里只有 `available balance` —— 真跑起来根本不会触发兜底 | 加进匹配表，并用真实原文写了回归测试 |
| 预警文案指向错误 | App 写着「App 会自动切到另一个 provider」，实际上切的是电脑端插件 | 文案改成说明真实链路，避免用户以为是 App 在切 |
| 切换对 App 不可见 | App 没处理 `model_change`，切完只在服务端看得出来 | `chat_reducer` 加一条状态提示 |

## 复现步骤

1. 装插件：在 `pi-yz` 里 `pi install ./pi-plugin`，重启 pi。
2. 看状态：任意会话里打 `/quota-fallback`，应显示当前模型 / 备用模型 / 已切次数 / 配置来源。
3. 验切换：`/quota-fallback switch`，再随便发一句；grep 会话 JSONL 里 assistant 条目的 `provider`，应从主 provider 变成 `deepseek`。
4. 验匹配表：`cd server && node --test test/quota-fallback-patterns.test.mjs`。
5. 验断点：发一条分三步的任务 → 第一步完成后 kill 服务端 → 重启 → 发「继续」，agent 应接着第一步往下走而不是重来。
