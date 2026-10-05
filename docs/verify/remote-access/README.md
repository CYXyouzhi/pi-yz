# 远程访问与凭据安全（4 项改动）

面向的需求：**端到端自己控 + 地址固定 + 断线自动恢复**，同时补掉审计发现的凭据缺口。

## 0. 方案选择：为什么不是 Cloudflare 隧道

现状本来就有 `--tunnel`（Cloudflare quick tunnel / localhost.run），而且已经有 Cloudflare
账号 + 域名可用 —— 用 named tunnel 能直接拿到**固定域名**，是最省事的路。

**但被排除了**：Cloudflare 是第三方，TLS 在它边缘终止，**内容对它可见**。
而需求明确要求「不接受第三方中转」。

**矛盾点必须说清**：在没有 VPS 的前提下，「零第三方」做不到 —— 必须选一个第三方，
区别只在它能看到多少。最终选了 **Tailscale（WireGuard）**：

| | 内容 | 元数据 |
|---|---|---|
| Cloudflare 隧道 | **可见**（TLS 在边缘终止）| 可见 |
| **Tailscale** | **不可见**（端到端加密，中继只转发密文）| 可见（设备连接关系）|

用户确认接受这个边界。**如果以后要求连元数据都不可见，唯一出路是买一台 VPS 自建
headscale 或纯 WireGuard** —— 这一条写在这里，免得以后重新推一遍。

## 1. 配对接口加限速

`server/lib/pairing.mjs`。背景：配对码是 6 位数字（100 万种）、窗口 5 分钟，
而**原先没有任何失败计数** —— 局域网里发几百到几千 req/s，5 分钟能覆盖相当比例。

三层防护：

| 规则 | 值 | 挡什么 |
|---|---|---|
| 单 IP 连续失败 | `MAX_FAILS_PER_IP = 5` → 冷却 `IP_COOLDOWN_MS = 60s` | 单机爆破 |
| 全局失败 | `GLOBAL_FAIL_LIMIT = 20` → **立即关窗** | 换 IP 的分布式爆破 |
| 冷却期内 | **不比较配对码、直接拒** | 免得比较耗时成为旁路信道 |

**一个刻意的设计**：窗口没开时的失败**不计入限速**。那是用户操作顺序问题，
不该罚他 —— 有专门的测试守这条。

`index.mjs` 侧：传来源 IP（`clientIpOf`，处理 `::ffff:` 映射地址、**不信
`X-Forwarded-For`**），冷却中回 **429 + `Retry-After`** 而不是 403。

**验证**：`server/test/pairing.test.mjs` **10 个用例全过**（含「冷却期内正确码也拒」
「一个 IP 不影响另一个」「窗口外的失败不罚到窗口内」）。时间用注入的 `now`，不用真等 60 秒。

```
$ node --test test/*.test.mjs
ℹ tests 20   ℹ pass 20   ℹ fail 0      （原有 10 + 配对限速 10）
```

## 2. token 持久化

`server/lib/token-store.mjs`。原来的两条路都不好用：

- `start.cmd` 写死 `pimobile2026`（项目名 + 年份）—— 猜中成本几乎为零；
- 不给 `--token` 则每次启动随机 —— 很强，但**每次重启都变**，手机要重填。

现在优先级：`--token` 参数 > `.token` 文件 > 首次生成并写入。**同时拿到「强」和「不变」**。

```
$ node -e "import('./lib/token-store.mjs').then(m => {...})"
  第 1 次: generated 474fc299… 长度 48
  第 2 次: file      474fc299… 长度 48
  两次相同: 是（重启不用重配）
  显式指定: explicit my-explicit （且不落盘）
  显式之后再读文件: file 仍是文件里的值
```

**明文存储这一点不藏**：能读这个文件的人本来就能读你的会话记录、`~/.pi`、SSH 私钥，
多一个 token 对他没有增量；Windows 上也没有跨平台无依赖的安全存储可用。
只做两件正确的小事：**进 `.gitignore`**、**日志只打脱敏值**。

## 3. 双地址自动回落

**动机**：在家走局域网（延迟低一个数量级）、出门走 VPN —— 用户分不清该用哪个，
**程序分得清**（哪个连得上用哪个）。

改动：
- `ServerProfile` / `ServerTarget` 加 `fallbackHost` / `fallbackPort` / `fallbackSecure`
- `ServerTarget.candidates`：主地址在前、备用在后（顺序是刻意的）
- `connect()` 逐个试候选，主地址失败**静默**试备用
- 设置页显示**实际连上的**地址，走备用时标出「走的是备用地址（主地址连不上）」

**向后兼容**：旧 profile 的 JSON 没有备用字段，解析后 `hasFallback == false`，行为与改动前完全一致（有测试守）。没配备用时 `toJson` **不会多写字段**。

### 实机验证（真实回落，不是模拟）

方法：用 root 直接改模拟器里的 `FlutterSharedPreferences.xml`，把 active profile 的主地址
换成 `192.0.2.1`（TEST-NET-1，保证不可达）、备用指向真实的 `10.1.1.195:30142`。

| 步骤 | 证据 |
|---|---|
| 启动后卡在连接中（主地址不可达） | `r1-connecting-primary-unreachable.png` |
| 自动切到备用并连上（画面已进会话页，连续 4 次截图 md5 相同 = 状态稳定） | `r2-connected-via-fallback-chat.png` |
| 设置页显示 **`10.1.1.195:30142` + 「走的是备用地址（主地址连不上）」** | `r3-settings-shows-fallback.png`、`r4-fallback-label-zoom.png` |

**基线**：同一时刻从设备 `ping 10.1.1.195` 通（0% loss），`/api/health` 也可达 —— 排除「备用本身连不上」。

### 实机验证抓出的两个真 bug

这一轮**第一次跑实机时回落是失败的**（卡在「连接中」3 分钟以上，进程没崩、备用也 ping 得通）。
查出两个叠加的缺陷：

1. **`health()` 用默认 30 秒超时。** 回落的目的是「快速切到能用那条」，
   等 30 秒完全失去意义。→ 新增 `_probeTimeout = 5s`，探活是探活、干活是干活。
2. **`catch` 只接了 `ServerException`。** `ServerClient._json` 只把 **`openUrl` 阶段**的
   `TimeoutException` 翻译成了 `ServerException`；而 `request.close()` 和读 body 的
   `.timeout()` 抛的是 Dart 内置 `TimeoutException` —— **它会冒泡出 `connect()`**，
   状态永远停在 `connecting`。→ 加 `catch (error)` 兜底。

**如果没有走实机，这个 bug 不会暴露**：`analyze` 干净、132 个单测全过、
数据层测试也全绿 —— 因为问题出在「异常类型没被接住」这种只在真实网络失败时才走到的路径上。

## 4. 连接页的安全提示

`conn_page.dart` 表单下方加三行（走 i18n，中英两栏，受 `i18n_integrity_test` 守）：

```
安全提示
· token 由服务端首次启动时自动生成，保存在 server/.token（已在 .gitignore 里）；
· 不要把这个端口直接暴露到公网。出门请用 VPN（如 Tailscale）而不是公共隧道；
· 配对码只在你于电脑端打开的 5 分钟窗口内有效，连续填错会被限速。
```

**为什么写具体机制而不是「注意安全」**：泛泛的提醒用户会直接跳过。

## 门禁

```
flutter analyze   No issues found
flutter test      132 全过（本轮前 121，+11 地址回落数据层用例）
node --test       20 全过（本轮前 10，+10 配对限速用例）
```

## 待用户执行（我替代不了的部分）

1. 电脑与手机各装 Tailscale，登录同一账号
2. 电脑上 `tailscale ip -4` 拿到 `100.x.x.x`
3. 服务端启动加 `--host 0.0.0.0`（局域网网卡与 Tailscale 网卡都能连）
4. App 连接页：主地址填局域网 IP、**备用地址填 Tailscale IP** → 出门自动回落
