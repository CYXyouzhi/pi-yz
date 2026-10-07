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

## 目录

```
lib/          Flutter 客户端。ui/ 是界面，server/ 是通信与状态
server/       Node 服务端。把 pi 的 SDK 包成 HTTP + SSE
pi-plugin/    两个 pi 扩展：/yz（起服务端）、额度兜底
docs/         verify/ 是每轮改动的验证证据，audit/ 是质量体检清单
tool/         开发脚本（模拟器、截图、i18n 审计、门禁）
test/         Flutter 测试
```

## 跑起来

需要电脑上已经装了 pi。

最省事的办法是在 pi 里敲：

```
/yz
```

它会拉起服务端，并把手机上要填的三样东西打在屏幕上。

不想开 pi 也可以，有个独立的命令行入口：

```bash
pi-yz              # 后台起服务，同样打印地址和 token
pi-yz status       # 看状态
pi-yz stop         # 停
pi-yz doctor       # 自检
```

`pi-yz` 是个转发脚本，实现在 `pi-plugin/bin/pi-yz.mjs`，跟 `/yz` 共用同一份
进程控制逻辑（`pi-plugin/lib/ctl.mjs`）——两边各写一套的话，"命令行说在跑、
pi 里说没跑"这类分歧迟早会出现。

再不行就手动起：

```bash
cd server && node index.mjs --host 0.0.0.0
```

服务端会打印一个脱敏的 token，完整值在 `server/.token`（自动生成，重启复用，
已在 `.gitignore` 里）。手机 App 里填地址、端口、token 就能连。

装 App：

```bash
flutter build apk --release
```

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
flutter test                               # 169 个用例（含 3 个 golden 基线）
flutter test --exclude-tags golden         # 166 个，跳过 golden
cd server && node --test test/*.test.mjs   # 20 个
node --test pi-plugin/test/ctl-status.test.mjs  # 7 个
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

能用。但有几处已知不够好：

- `chat_page.dart` 还有 3374 行，是最大的一块
- `docs/verify/` 里的记录改过名，早先的原始证据已不存在
- 平板、横屏、320dp 老机型没验证过，只覆盖 360~450dp 竖屏

## 许可

[MIT](LICENSE)
