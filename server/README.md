# pi-yz-server

把电脑上的 pi 包成 HTTP + SSE，让 pi-yz 手机端连过来操作。

代码只依赖 Node 内置模块，外加一个运行时依赖（pi 的 SDK）。

## 前置

- **Node ≥ 22.19**：这是 pi 的 SDK 要求的（服务端自己只用到 `import.meta.resolve`，门槛是依赖带来的）
- pi 的 SDK：`npm install` 会自动装 `@earendil-works/pi-coding-agent`
- **pi 本体 + 已登录**：见下面的「先装 pi」—— 少了它，服务端能起来、手机能连上，
  但建会话会失败

## 先装 pi

服务端只是 pi 的**遥控器** —— 真正干活的 pi 得先装好、并且有可用模型：

```bash
# 装（两条任选；一键脚本会自动处理 Node 版本）
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
# 或者：curl -fsSL https://pi.dev/install.sh | sh
# Windows：powershell -c "irm https://pi.dev/install.ps1 | iex"

pi        # 进 pi 后跑 /login：连订阅，或填一家服务商的 API key
```

验证配好了没：

```bash
pi auth   # 打印凭据 / 检查服务商是否就绪
```

**这一步不做会怎样**：服务端照样启动、打印 token 和配对码，手机也能连上 ——
但发消息时报错，而且看不出根因。这类问题最难查，所以放在最前面说。

## 安装

```bash
cd server
npm install
```

### 复用本机已装的 pi（开发机上省 400MB+）

如果这台机器上本来就装了 pi，可以让 `server/node_modules` 指向它，不重复下载：

```cmd
:: Windows（需要管理员 cmd）
mklink /J node_modules E:\pi-agent\node_modules
```

```bash
# Linux / macOS
ln -s ~/.pi/node_modules node_modules
```

分发到别的机器时**不需要**这条，正常 `npm install` 就行 —— 代码里没有对具体路径的假设。

## 启动

| 平台 | 命令 |
|---|---|
| Windows | 双击 `start.cmd` |
| Linux / macOS | `bash start.sh` |
| 手动（哪都一样） | `node index.mjs --host 0.0.0.0` |

`--host 0.0.0.0` 的意思是「监听所有网卡」。不加就只有本机能连。

> **Windows 第一次启动会弹防火墙授权 —— 要允许**，否则手机连不进来。

### 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `--host` | `127.0.0.1` | 手机要连就必须传 `0.0.0.0` |
| `--port` | `30142` | |
| `--token` | 自动生成 | 不传时首次启动生成 192 bit 随机 token，写进 `.token`，之后复用 |
| `--default-cwd` | 无 | 新建会话的默认工作目录。不传时建会话必须自带 `cwd` |
| `--no-pair` | 关 | 加了这个就不开配对窗口（只有手动指定 token 才配得上） |
| `--tunnel` | 关 | 启动时开一条 SSH 反向隧道（localhost.run），异地也能连 |
| `--help` | | 打印用法 |

## token 在哪

```bash
cat .token      # Linux / macOS
type .token     # Windows
```

`.token` **不进版本库**（`.gitignore`）也**不在分发包里**（`package.json` 的 `files` 白名单）。

## 手机怎么连

1. 查电脑的局域网地址：`ipconfig`（Windows）/ `ifconfig`（macOS/Linux），
   找 `192.168.x.x` 或 `10.x.x.x` 那一行
2. App → 连接 → 新增：填地址、端口 `30142`、token

**更省事的做法是用配对**：服务端启动时会打印一个 6 位配对码，
在 App 里点「配对」输进去就自动拿到 token —— 不用手抄那串随机串。

配对这套东西的安全设计（为什么不干脆把 token 广播出去）：

- token **绝不进广播** —— 广播是给整个局域网看的，等于公开
- 配对码只在**你显式开窗**之后才存在，默认只开 5 分钟
- 窗口一关码立刻失效；配对成功也立刻关（一次性）
- 有失败限速：单 IP 连续失败会冷却，全局失败到阈值**直接关窗**
  （后者挡的是换 IP 的分布式爆破 —— 窗口都没了，再多 IP 也没用）

## 异地使用（远程访问）

两种方式，在 App 的「远程访问」页操作：

| 方式 | 需要什么 | 说明 |
|---|---|---|
| localhost.run | 无 | 走 SSH 反向隧道，服务端自己就能开（`--tunnel`） |
| Cloudflare | `cloudflared` 二进制 | 更快更稳。仓库**不含**它（53MB），从 Cloudflare 官方下载后放到 `server/bin/cloudflared.exe` |

## 排错

| 现象 | 通常是 |
|---|---|
| 手机连不上、一直转圈 | 忘了 `--host 0.0.0.0`；防火墙没放行；或手机与电脑不在同一网段 |
| 提示 401 | token 不对（两边要完全一致，注意别多复制了空格） |
| 端口被占用 | 已经有一个实例在跑；改 `--port` 或先关掉旧的 |
| 配对码输了总失败 | 窗口过期（默认 5 分钟）或失败太多次被冷却 —— 重新开窗 |
| Windows 中文乱码 | `start.cmd` 里已经 `chcp 65001`；手动跑请在 UTF-8 终端里 |

## 测试

```bash
npm test        # node --test test/
```

## 分发

```bash
npm pack        # 产出 pi-yz-server-0.2.0.tgz
```

产物是**纯源码包**，不含 `node_modules`、`.token`、日志和 cloudflared 二进制。
对面拿到之后 `npm install && npm start` 就能跑。
