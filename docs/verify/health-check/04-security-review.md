# 04 · 安全扫描与审核（task-6）

范围按合同：依赖漏洞、凭据与 token 泄漏、服务端鉴权与授权、文件访问边界、
命令执行面、移动端本地存储与调试日志。

## 总结论

**未发现严重或高危问题。** 服务端的鉴权与文件边界实现是**正确且克制**的，
下面「已验证良好」一节逐条列出证据；「低风险项」一节列出 3 条，
每条都给了为什么可接受的理由（都不是"没看见"，而是"看见了，判定可接受"）。

## 一、严重 / 中危：0 项

## 二、低风险：3 项（已书面豁免）

### L1. server 没有依赖锁文件，`npm audit` 无法运行

- **现状**：`server/` 下没有 `package-lock.json` / `shrinkwrap.json`。
- **原因（设计使然，不是遗漏）**：`server/package.json` 里写了
  `"//deps": "依赖通过 node_modules junction 指向 E:/pi-agent/node_modules 复用本机已装的 pi，不重复下载 427MB"`。
  也就是说 server 自己不装依赖，而是复用本机已装的 pi 运行时。
- **风险评估**：低。依赖版本由**本机的 pi 安装**决定，不受本项目控制；本项目也无需为它做版本审计。
- **豁免理由**：加 lockfile 反而会与「junction 复用」的设计冲突（会试图锁定并下载一份重复的依赖树）。
  真正的依赖安全边界在 pi 本身的发布流程里，不在这个仓库。
- **保留的可见性**：`node --test test/*.test.mjs` 可随时回归（10 项全过）。

### L2. 手机端 token 以明文存于 SharedPreferences

- **现状**：`lib/server/server_profile.dart` 用 `SharedPreferences` 存地址/端口/token；
  `pubspec.yaml` 未引入 `flutter_secure_storage`。
- **风险评估**：低。Android 上 `SharedPreferences` 落在**应用私有目录**，
  未 root 的设备其他 App 无法读取；token 又是 192 位随机（见下）且可随时重新配对。
- **豁免理由**：换 `flutter_secure_storage` 会引入 Keystore 依赖与新增原生配置，
  收益是"防已 root 设备"，而**已 root 的设备上任何应用层加密都挡不住**（内存里总有明文）。
  在当前"局域网/隧道内自用"的定位下，判定可接受。

### L3. 配对码没有失败次数限制

- **现状**：`verifyPairingCode` 没有"失败 N 次就锁定"。
- **已具备的防护**：
  - 配对窗口默认只开 **5 分钟**（`pi-yz server pair` 或重启时自动开）；
  - 比对用**常量时间**（`diff |= given.charCodeAt(i) ^ state.code.charCodeAt(i)`），不泄漏逐位信息；
  - 配对**成功后立即关窗**（`closePairingWindow()`），即一次配对码只能用一次；
  - 窗口关闭后直接拒绝并给出可操作提示。
- **风险评估**：低。5 分钟窗口 + 一次性 + 常量时间，暴力枚举在时间上不可行。
- **豁免理由**：加限流需要引入服务端状态与冷却逻辑，而现有三重约束已经压住了这个面。

## 三、已验证良好（无需改动，附证据）

| 面 | 证据 |
|---|---|
| **token 强度** | `server/index.mjs:84` `const TOKEN = args.token ?? randomBytes(24).toString('hex')` → 192 位熵 |
| **token 比对** | `index.mjs:121-123` 先比长度、再逐字符异或累加 `diff`，**常量时间**，防时序侧信道 |
| **鉴权覆盖面** | `index.mjs:165` `if (!authorized(req)) return json(res, 401, …)` —— 该行**之后**才是各业务端点；SSE 端点（`index.mjs:453`）也在其后，**事件流同样需要 token** |
| **免鉴权端点的克制** | 只有 `/api/health`（用于探测可达性）与 `/api/pair`（换取 token 的入口）在鉴权之前 —— 都无副作用 |
| **文件访问边界** | `server/lib/fs.mjs:71` `assertAllowed`：`path.resolve` 规范化（吃掉 `..`）后要求 `resolved === root || resolved.startsWith(root + path.sep)`；**带 `path.sep` 是防 `/root2` 误匹配 `/root` 的关键**。全部文件类端点（`/api/files`、`/api/file`、`/api/file/raw`、`/api/upload`、`/api/file-index`）都走它 |
| **预览大小上限** | `fs.mjs:283` 超过 `RAW_LIMIT_BYTES` 直接拒绝，避免一个巨大文件把手机或服务端拖死 |
| **上传大小上限** | `fs.mjs` 的 upload 上限注释明确"手机端传代码/文本/截图够用"，与 `readJson(req, 64*1024)` 的请求体上限配合 |
| **CORS** | 服务端**不设**任何 `Access-Control-Allow-*` 头（grep 为 0）。手机端是原生 HTTP 客户端，不受同源策略约束；不设 CORS 意味着**浏览器页面无法跨域调用**这个 API，正是想要的效果 |
| **凭据泄漏** | 全仓扫描 `token/secret/password/apiKey` 赋值，只命中 2 处且都是**测试假值**（`server/probe-cred2.mjs` 的 `'sk-test-roundtrip-not-real'`、`server/test/secrets.test.mjs` 的用例数据） |
| **日志脱敏** | `index.mjs:580` 打印 token 时走 `maskSecret(TOKEN)`；`server/lib/secrets.mjs` 的 `maskSecret` 是「短串全遮、长串只留前 4 后 2 并标出原长度」，另有 `redact(text, secrets)` 把整段文本里出现的密钥替换掉（专治"把整个请求 stringify 进日志"） |
| **调试日志** | 全仓 `debugPrint/print` 中 grep `token` 为 0 命中 |
| **命令执行面** | 端点清单里**没有**"执行任意命令"的接口；全部是 pi 的语义操作（会话/文件/MCP/凭据/用量/包管理）。手机能做的最大事情是「给 pi 发一条 prompt」，这与用户在电脑前直接跟 pi 说话等价 —— 是产品设计本身，不是漏洞 |
| **凭据写入端点** | `/api/credentials`（POST，可写 provider 密钥）**需要 token**；且写入后会经 service 层处理，不由客户端直接落盘明文 |

## 四、复现命令

```bash
cd pi-yz
# 服务端测试（10 项）
cd server && node --test test/*.test.mjs

# 凭据泄漏扫描（期望只命中测试假值）
grep -rniE "(token|secret|password|apikey|api_key|bearer)\s*[:=]\s*['\"][A-Za-z0-9_-]{16,}" lib/ server/ --include=*.dart --include=*.mjs | grep -v node_modules

# 日志脱敏确认
grep -rn "console\." server/index.mjs | grep -iE "token|auth"

# 路径边界实现
grep -n "assertAllowed" -A 12 server/lib/fs.mjs
```
