# pi-mobile 电脑端插件

这个目录是一个 pi 插件包，装一次能得到两样东西：

| 扩展 | 干什么 |
|---|---|
| `extensions/mobile-server.ts` | 把 pi-mobile 的电脑端服务做成 pi 命令：`/yz start` 起服务、`stop` 停、`status` 看状态、`doctor` 自检、`token` 换 token |
| `extensions/quota-fallback.ts` | **额度兜底**：主 provider 因额度/计费失败时，自动切到备用 provider，并让 agent 接着把没干完的活干完（无人值守） |

两者共用 `lib/ctl.mjs` —— 真正的进程控制逻辑写在那里（纯 Node，不依赖 pi 的 API），
所以它既能被 pi 命令调用，也能被 `pi-yz` 命令行和测试直接调用。
两边各写一套的后果是「命令行说在跑、pi 里说没跑」这类分歧会悄悄长出来。

## 安装

```bash
pi install ./pi-plugin          # 在 pi-mobile 仓库里执行
```

装完重启 pi（或在 pi 里 `/reload`）。文件直接放到 `~/.pi/agent/extensions/` 下也能生效（pi 启动时自动加载该目录）。

命令行的 `pi-yz` 是另一个入口，需要在 PATH 里放个转发脚本：
`~/.pi/agent/bin/pi-yz.cmd`（cmd / PowerShell）和 `~/.pi/agent/bin/pi-yz`（Git Bash），
两者都只负责把参数转给 `pi-plugin/bin/pi-yz.mjs`，项目挪位置时改转发脚本里的 `PI_YZ_HOME` 即可。

## 两种入口，同一套实现

```
pi 里                     终端里（不依赖 pi 主进程）
─────────────────────     ──────────────────────────────────
/yz                        pi-yz              后台启动 + 打印手机要填的三行
/yz start [端口]           pi-yz start [端口]  同上
/yz stop                   pi-yz stop         停服务
/yz                        pi-yz status       看状态（谁拉起的、在不在跑）
/yz doctor                 pi-yz doctor       自检
/yz token <t>              pi-yz token <t>    换 token
                           pi-yz logs [行数]  看日志尾部
```

两种入口**共用同一份 ctl.mjs**，所以「谁拉起的、在不在跑」的判断不会打架。

**启动时机是手动的** —— 不做「pi 启动就自动拉起」：服务什么时候在跑完全由你决定，
不会在你不知情时躺着一个进程。

## quota-fallback

### 它做什么

主 provider 返回额度类错误时（DeepSeek 的 `Insufficient Balance`、opencode-go 的 `GoUsageLimitError`、
OpenAI 的 `insufficient_quota` 等），插件会：

1. **立刻换模型**（`setModel` → 默认 `deepseek/deepseek-flash`），下一条请求就用备用 provider；
2. **落一条审计记录**到会话里（`appendEntry`，含时间、从哪个模型切到哪个、命中的关键字、第几次切换）；
3. **排一条 followUp 消息**，让 pi 自己再跑一轮，从断掉的地方接着干 —— 不需要人点任何东西。

### 命令

```
/quota-fallback           看状态（当前模型、备用模型、本会话已切次数、配置来源、匹配关键字）
/quota-fallback on|off    本次会话临时开关
/quota-fallback switch    立刻手动切到备用模型（验证切换链路用）
/quota-fallback reload    重新读配置文件
```

### 配置

`~/.pi/agent/quota-fallback.json`（不存在就用内置默认）：

```json
{
  "enabled": true,
  "fallback": { "provider": "deepseek", "model": "deepseek-flash" },
  "patterns": ["GoUsageLimitError", "insufficient balance", "insufficient_quota"],
  "maxPerSession": 3
}
```

- `patterns` 是**小写包含**匹配（大小写不敏感）。不写就用内置表；写了自己那份就**完全替代**内置表。
- `maxPerSession` 是防横跳上限：备用模型也失败时会一直切来切去，超过就不切了，只在界面上报一句。
- **不会自动切回**主 provider：切走之后本次会话就用备用模型。想切回去用 `/model <provider>/<model>`。

### 局限（必须知道）

- **只认关键字**：服务商改了错误文案就可能漏判（拿不准的错误原文先 grep 会话记录，
  再把关键字加进 `patterns` —— 这轮就是这么补上 `insufficient balance` 的）。
- **不区分「额度」与「限流」**：命中就切，宁可多切一次也不让人半夜卡着。
- **不保证接着干得对**：它只是把「从哪儿开始」写进 followUp，
  真正判断断点的是 agent 自己（会话记录里已经落盘的部分就是它的依据）。
- **备用 provider 得有凭据**：没配 DeepSeek 的 key 时，切换会失败并在界面上报出来。

### 怎么验证它在跑（不靠肉眼看界面）

```bash
# 1) 命令能被识别（说明插件加载了）
curl -X POST http://127.0.0.1:30142/api/sessions/<id>/command \
  -H "Authorization: Bearer <token>" -H "Content-Type: application/json" \
  -d '{"id":"q","type":"prompt","message":"/quota-fallback"}'
# → {"data":{"disposition":"handled"}}

# 2) 切换真的生效（看下一轮的 provider 落盘）
curl ... -d '{"id":"q2","type":"prompt","message":"/quota-fallback switch"}'
curl ... -d '{"id":"q3","type":"prompt","message":"只回复两个字：收到"}'
# 然后 grep 该会话 JSONL 里 assistant 条目的 provider 字段：应从 opencode-go 变成 deepseek

# 3) 匹配表本身
cd server && node --test test/quota-fallback-patterns.test.mjs
```
