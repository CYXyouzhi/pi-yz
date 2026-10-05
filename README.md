# pi-mobile

把电脑上 [pi](https://github.com/earendil-works/pi) 的能力搬到手机。

手机端是**显示器 + 键盘**，pi 始终跑在你的电脑上 —— 所以 pi 的功能（斜杠命令、
扩展、分支树、主题）**自动完整可用**，客户端不需要逐个适配。

```
┌──────────────────┐   HTTP + SSE    ┌────────────────────┐
│  Flutter 客户端   │ ──────────────▶ │  Node 服务端        │
│  （显示器+键盘）   │ ◀────────────── │  把 pi SDK 包成 HTTP │
└──────────────────┘                 └─────────┬──────────┘
                                               │ 进程内调用
                                        ┌──────▼──────┐
                                        │  pi 的      │
                                        │ AgentSession│
                                        └─────────────┘
```

## 组成

| 目录 | 是什么 |
|---|---|
| `lib/` | Flutter 客户端（约 2.4 万行 Dart） |
| `server/` | Node 服务端（约 5.8 千行 JS）：把 pi 的 SDK 包成 HTTP + SSE |
| `pi-plugin/` | 配套的 pi 扩展 |
| `docs/verify/` | 每一处改动的验证证据（截图、量测脚本、门禁输出） |
| `tool/` | 开发脚本（设备交互、门禁、i18n 审计） |

## 服务端怎么用上 pi

服务端**不是 pi 的一部分**，而是一个独立进程，把 pi 当**库**来用：

```js
import { createAgentSession, SessionManager } from '@earendil-works/pi-coding-agent';

const sessionManager = SessionManager.open(path);
const { session } = await createAgentSession({ sessionManager, cwd });
session.subscribe((event) => { /* 裁剪后经 SSE 推给手机 */ });
```

依赖通过 `server/node_modules` 软链接指向你本机已装的 pi，**不重复下载**。
详见 [`docs/verify/remote-access/`](docs/verify/remote-access/)（连同 token 与隧道的说明）。

## 快速开始

**1. 启动服务端**（需要本机已装 pi）

```bash
cd server
node index.mjs --host 0.0.0.0
```

首次启动会打印监听地址与一个**脱敏**的 token；完整值在 `server/.token`
（自动生成、重启复用，已在 `.gitignore` 里）。想看完整值：`type .token`（Windows）。

**2. 装客户端**

```bash
flutter build apk --release     # 或 flutter run
```

**3. 在 App 里连**：填「地址 + 端口 + token」。局域网直接填电脑的局域网 IP。

## 安全

这个服务端能执行命令、读写文件 —— **它就是你电脑上 pi 的一把钥匙**。默认配置是保守的：

| 机制 | 说明 |
|---|---|
| 默认只监听 `127.0.0.1` | 要局域网访问必须显式加 `--host 0.0.0.0` |
| token 强随机 | 首次启动生成 192 bit 随机值，存在 `.token`，**不随重启变化** |
| token 校验 | 常量时间比较；日志只打脱敏值 |
| 配对码 | 6 位码 + 5 分钟窗口 + 一次性；**单 IP 失败 5 次冷却 60 秒，全局失败 20 次立即关窗** |
| 不做反向代理信任 | 不读 `X-Forwarded-For`（那个头客户端能随便写，信它等于给爆破者一把换 IP 的钥匙）|

**传输注意**：局域网直连是**明文 HTTP**。所以：

- **不要把这个端口暴露到公网**；
- 出门在外建议用 **VPN**（如 Tailscale —— WireGuard 端到端加密、地址固定、自动重连），
  而不是开公共隧道（公共隧道的 TLS 在第三方边缘终止，内容对它可见）；
- 客户端支持**备用地址回落**：主地址填局域网 IP、备用填 VPN IP，出门自动切换。

## 开发

```bash
flutter test                       # 132 个用例
flutter analyze                    # 期望 0 issue
cd server && node --test test/*.test.mjs   # 20 个用例
```

两道脚本门禁（放在 `tool/`）：

| 脚本 | 作用 |
|---|---|
| `evidence_freshness.py` | 截图必须晚于 APK、APK 必须晚于源码 —— 防止拿旧构建的截图当新改动的证据 |
| `touch_targets.py` | 带图标的可点控件不得小于 40dp |

`docs/verify/` 里每一轮改动都留下了：截图、量测脚本、门禁原始输出、以及**已知问题与未解决项**
（包括没有定位成功的 ANR、没有被证伪的手势冲突 —— 都写在文档里，不藏）。

## 许可

待定。
