# pi-yz

在手机上用你电脑上的 pi。

手机当显示器和键盘，pi 始终跑在电脑上。浏览器里能做的事它都能做——斜杠命令、
扩展、分支树、主题——因为这些能力本来就在 pi 里，客户端不需要为每个功能单独适配。

```
   手机 App              电脑
┌──────────────┐    HTTP    ┌─────────────────┐
│ Flutter 客户端 │ ─────────▶ │ Node 服务端      │
│ 约 2.5 万行    │ ◀───────── │ 约 5 千行        │
└──────────────┘    SSE     └────────┬────────┘
                                     │ 进程内调用
                              ┌──────▼──────┐
                              │ pi 的        │
                              │ AgentSession │
                              └─────────────┘
```

## 快速开始

需要 **Node ≥ 22.19**（这是 pi 的要求，不是我们挑的）与 **pi 本体 + 已登录**。
服务端把 pi 的 SDK 当库调用，**不用开着 pi 界面**。

```bash
# 电脑上（两条命令）
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
pi                    # 进去后跑 /login：连订阅，或填一家服务商的 API key

cd server && npm install && npm start
#                     ↑ 它会打印手机上要填的地址、端口、配对码
```

手机上：从 Releases 下 `arm64-v8a` 那个包装上（不确定架构就下 universal），
再「连接」→「配对」，填电脑上打印的 6 位码。

Windows 上双击 `server/start.cmd` 也行。细节见 [server/README.md](server/README.md)。

## 现在到哪了

进度、已知问题、下一步都记在 [ROADMAP.md](ROADMAP.md) —— 只维护那一个地方，
README 不重复写（两处写同一件事，必然有一处先过期）。

最近一轮做完的：token 改用 Android Keystore 加密存储（含旧数据迁移）、
真机包从 56.5 MiB 降到 21.5 MiB、服务端可以独立分发了、补齐平板与横屏的布局验证。

## 目录

```
lib/          Flutter 客户端。ui/ 是界面，server/ 是通信与状态
server/       Node 服务端。把 pi 的 SDK 包成 HTTP + SSE
docs/         verify/ 是每轮改动的验证证据，audit/ 是质量体检清单
tool/         开发脚本（模拟器、截图、i18n 审计、门禁）
test/         Flutter 测试
```

## 跑起来

电脑上两条命令：

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
pi                     # 跑 /login 登录，然后退出

cd server && npm install && npm start
```

服务端启动后会打印：

```
  监听      : http://0.0.0.0:30142
  局域网地址: 192.168.x.x（手机要连这个）
  配对码    : 491871（5 分钟内有效）
  token     : 0201…f6（脱敏；完整值在 server/.token）
```

`server/.token` 首次启动自动生成、之后重启复用，**不进版本库**。

手机上从 Releases 下 `arm64-v8a` 那个包（不确定架构就下 universal），装好后
「连接」→「配对」填那 6 位码；也可以用 token 手动配。

**不用开着 pi 界面** —— 服务端自己起会话。端口、防火墙、异地使用、排错见
[server/README.md](server/README.md)。

## 关于安全

得说清楚：这个服务端能在你电脑上执行命令、读写文件。**它等同于一把你电脑的钥匙。**

默认配置是保守的：

- 服务端默认只监听 `127.0.0.1`。要局域网访问必须显式加 `--host 0.0.0.0`
- token 是首次启动生成的 192 位随机值，存在 `.token` 里，重启不变（否则手机每次都要重配）
- token 不进局域网广播——广播整个局域网都能收到，那等于公开
- 配对码 6 位、只开 5 分钟、用过即废。单 IP 失败 5 次冷却 60 秒，全局失败 20 次直接关窗
- 不信任 `X-Forwarded-For`（这个头客户端能随便写，信它等于给爆破的人一把换 IP 的钥匙）

局域网直连是**明文 HTTP**，所以：

- 别把这个端口暴露到公网
- 出门在外建议用 VPN（Tailscale 这类，WireGuard 端到端加密、地址固定、自动重连），
  而不是开公共隧道——公共隧道的 TLS 在第三方边缘就终止了，内容对它可见
- 客户端支持备用地址：主地址填局域网 IP、备用填 VPN IP，出门自动切

## 开发

```bash
flutter analyze                            # 期望 0 issue
flutter test                               # 全量（含 golden 基线）
flutter test --exclude-tags golden         # 跳过 golden —— 基线是 Windows 上生成的，
                                           # 其他平台的字体栈不同，像素必然有差异
cd server && node --test                  # 服务端
```

推送到 `main` 或发 PR 时，GitHub Actions 会自动跑上面这几条（见
`.github/workflows/ci.yml`）。CI 跳过 golden——那三张基线是在 Windows 上生成的，
Ubuntu 的字体和图形栈不同，比出来的差异没有意义。golden 在本地跑。

golden 和普通断言测试分工不同：断言回答"布局有没有爆"（溢出会抛异常），
golden 回答"样子变了没有"（颜色、间距、层级）。两者都要有——把一个卡片
提到顶层后它在 360dp 下摘要换行、比旁边高出一截，那属于"没溢出但变了"，
断言全绿，是看图才发现的。

`docs/verify/` 里每轮改动都留了截图、量测脚本、门禁原始输出，以及**没解决的问题**
（比如没定位成功的 ANR、没被证伪的手势冲突——都写在文档里，不藏）。

## 服务端怎么用上 pi

服务端不是 pi 的一部分，它把 pi 当库调用：

```js
import { createAgentSession, SessionManager } from '@earendil-works/pi-coding-agent';

const sessionManager = SessionManager.open(path);
const { session } = await createAgentSession({ sessionManager, cwd });
session.subscribe((event) => { /* 裁剪后经 SSE 推给手机 */ });
```

`server/node_modules` 是指向本机 pi 安装目录的软链接，不重复下载。

pi 的事件流很大——一次 `ls` 对话原始 296 KB，裁剪后约 30 KB。裁剪在服务端做
（`server/lib/wire.mjs`，六条规则，每条都有实测数字），客户端不用管。

## 状态

**能用，主线功能完整。** 详细进度与已知问题在 [ROADMAP.md](ROADMAP.md)，
安全边界在 [SECURITY.md](SECURITY.md)。

最近一次全量验证（2026-10-09）：

| 门禁 | 结果 |
|---|---|
| `flutter analyze` | 0 issue |
| Flutter 用例 | 436 个全过（另有 golden 基线，Windows 上跑） |
| Node 用例 | 27 个全过（服务端 20 + 插件 7） |
| 逻辑层覆盖率（`lib/server` + `lib/services`） | 81.0% |
| 真机 | MuMu / Android 15：token 迁移、平板与横屏、x86_64 release 包均实测通过 |

证据与复现步骤散在 `docs/` 里（[testing.md](docs/testing.md)、
[threat-model.md](docs/threat-model.md)、[apk-size.md](docs/apk-size.md)、
[tablet-landscape.md](docs/tablet-landscape.md)）。

## 许可

[MIT](LICENSE)
