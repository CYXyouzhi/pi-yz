# pi-mobile 电脑端插件

这个目录是一个 pi 插件包，装一次能得到两样东西：

| 扩展 | 干什么 |
|---|---|
| `extensions/mobile-server.ts` | 把 pi-mobile 的电脑端服务做成 pi 命令：`/mobile start` 起服务、`stop` 停、`status` 看状态、`token` 看配对码、`doctor` 自检 |
| `extensions/quota-fallback.ts` | **额度兜底**：主 provider 因额度/计费失败时，自动切到备用 provider，并让 agent 接着把没干完的活干完（无人值守） |

## 安装

```bash
pi install ./pi-plugin          # 在 pi-mobile 仓库里执行
```

装完重启 pi（或在 pi 里 `/reload`）。文件直接放到 `~/.pi/agent/extensions/` 下也能生效（pi 启动时自动加载该目录）。

## mobile-server

```
/mobile start        起服务（后台跑，终端打印手机该填的地址与 token）
/mobile stop         停服务
/mobile status       看状态（含活跃会话数、远程入口）
/mobile token        重新配对：打印配对码与新 token
/mobile doctor       自检：端口占用、防火墙、隧道可达性
```

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
