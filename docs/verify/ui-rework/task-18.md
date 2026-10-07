# task-18 · 远程访问（不在同一局域网也能连上）（已完成）

五条合同逐条。证据在 `task-18/`，公网链路的原始输出在 `05-public-curl.txt`、`06-roundtrip-jsonl.txt`。

| # | 合同 | 状态 | 证据 |
|---|---|---|---|
| ① | 至少一种可用远程方案跑通（隧道或自建中继），明确定位与代价，有配置与连接成功截图 | ✅ | 方案：**Cloudflare quick tunnel 为首选**（`cloudflared tunnel --url http://localhost:30142`，二进制放在 `server/bin/cloudflared.exe`），**SSH 反向隧道（localhost.run）为兜底**（`ssh` 系统自带，零安装）。服务端 `--tunnel` 启动即开，也可由 App 开关。**连接成功**：`03-connected-via-public.png` —— 连接卡显示 `https://think-navigate-themes-vital…` + 「已连接 1.0.0 · 248 条会话」。**代价写在界面上**（`02-threat-model.png`）：流量绕 Cloudflare 海外边缘（实测洛杉矶），延迟比局域网高 0.5~1.5 秒；免费隧道不承诺 SLA，断了要重开。**实测两条路的国内可达性**：Cloudflare 的 DNS / QUIC / HTTP2 / API 四项 precheck 全过、隧道 1.5~5.5 秒响应；而 `*.lhr.life`（localhost.run）**curl 21.8 秒超时、HTTP 000** —— 这条只当兜底 |
| ② | 安全：必须带鉴权、传输加密，并说明威胁模型 | ✅ | **鉴权**：`05-public-curl.txt` —— 公网地址带对 token → `HTTP 200`；不带 token → `HTTP 401`；错 token → `HTTP 401`。token 比较是常量时间实现（`server/index.mjs` 逐字节异或累加），防时序侧信道。**传输加密**：入站是 HTTPS（TLS 证书由 Cloudflare 签发），出站是 QUIC 隧道，两层都不落明文。**威胁模型**：`02-threat-model.png` 里逐条列出（链路走向、两层加密、第三方只看得到「有流量」、鉴权仍靠 token、随机子域名扫到也连不上、延迟与 SLA 代价），且**按 provider 分开写** —— 换成 Cloudflare 之后界面不能再念 SSH 那套词（早前踩过）。**免鉴权路径只有两条**：`/api/health`（健康探测）与 `/api/pair`（拿 token 之前必须先能调，安全性靠 5 分钟窗口 + 一次性配对码） |
| ③ | 手机在非同一网络下真实连上并完成一轮对话，有截图 | ✅ | **链路是公网**：连接卡上的地址是 `https://xxx.trycloudflare.com`（不是 10.1.1.195），App 走的就是隧道（`03-connected-via-public.png`）。**一轮对话落盘为证**：`06-roundtrip-jsonl.txt` —— 会话 `01a0cabd` 里 `2026-10-04T04:40:55.603Z user | public-tunnel-roundtrip-ok` 与 `04:40:59.086Z assistant | 主人，收到 …`，两条相差 **3.5 秒**，这条 user 消息是 App 输入框里敲出去的（不是电脑端 curl 造的） |
| ④ | 可一键断开/禁用远程入口 | ✅ | App 里远程访问卡片上的「一键断开」（`01-remote-card.png`）。断开后实测：服务端 `/api/remote` → `status=idle`、`url` 清空；**公网再访问同一个域名 → `HTTP 530`**（Cloudflare 的「隧道不存在」），而局域网连接照旧。界面回到「未开启」态（`04-after-stop.png`） |
| ⑤ | 远程模式下延迟与失败提示友好（给出具体原因） | ✅ | **延迟**：公网一次列表请求实测 5.5 秒（局域网 <0.3 秒），威胁模型里写明量级；连接成功后 toast 写「已通过公网连上（https://…:443）」。**失败原因分得开**：隧道进程起不来 →「系统里有没有 ssh？」/「cloudflared 跑不起来？」；20 秒没拿到地址 →「到 Cloudflare 的网络不通？」；已开过又掉线 →「隧道断开（进程退出码 N）—— 免费隧道会被服务端清理，重新开启即可」；连接失败 →「公网连接失败：<具体原因>」。空主机名提交的即时提示见 `04-after-stop.png` 同一位置的红色文案 |

## 这轮加的代码

```
服务端 server/lib/tunnel.mjs      隧道管理：Cloudflare quick tunnel 优先、SSH 反向隧道兜底；
                                  URL 解析、失败原因分类、威胁模型（按 provider）、起/停
      server/lib/args.mjs         --tunnel 启动参数
      server/index.mjs            GET /api/remote、POST /api/remote/start、POST /api/remote/stop；
                                  启动时按 --tunnel 开，退出时关
      server/bin/cloudflared.exe  隧道二进制（55 MB，从 gh-proxy.com 镜像取的官方 release）
App   lib/server/server_types.dart   RemoteState（status/url/error/provider/threatModel）
      lib/server/server_client.dart  secure 字段 + 三类请求走 https；remote()/startRemote()/stopRemote()
      lib/server/server_store.dart   remote 状态 + loadRemote/startRemote/stopRemote；ServerTarget 带 secure
      lib/server/server_profile.dart 配置加 secure；endpoint 显示成 https://…
      lib/ui/server/conn_page.dart    远程访问卡片（开关/地址可复制/用这个地址连/一键断开/威胁模型）；
                                      host 支持直接粘贴整条 https:// URL（自动拆出域名与 443）
```

## 实测踩到的四个坑（都已落到代码注释里）

| 坑 | 现象 | 处理 |
|---|---|---|
| 把欢迎信息当隧道地址 | localhost.run 的欢迎横幅里有 `https://admin.localhost.run`（管理自定义域的地址），早期正则写成了泛化的 `*.localhost.run`，于是 `/api/remote` 报的「隧道地址」根本打不开 | 正则收紧到只认真实隧道域名：`trycloudflare.com` / `lhr.life` / `lhrtunnel.link` |
| 界面念错威胁模型 | 换成 Cloudflare 之后，展开「链路与代价」还在说「SSH 反向隧道」 | 威胁模型按 provider 生成（`threatModelFor`），文案里不再写死某一家的链路 |
| 关掉之后还挂着错误 | 一键断开后状态是「未开启」，下面却还留着上次失败的 `HTTP 502` | `stopTunnel()` 一并清 `lastError` |
| 隧道地址让用户手抄 | 地址又长又随机、每次重开都变，手抄必错 | App 端加「用这个地址连」：拿当前已配对的 token + 这个地址直接存成一条配置并连过去 |

## 已知限制（写清楚，不粉饰）

- **Cloudflare quick tunnel 对 SSE 长连接不稳**：App 首连成功、也能完成一轮对话（见 ③），但长连接可能被中途掐断，之后 App 会退到「离线 · 显示缓存」那套行为（task-13 做好的降级路径）。要长期稳定跑，建议用带账号的 named tunnel 或 Tailscale。
- **localhost.run 在国内不可达**（实测 21 秒超时），所以它只是「网络能通时的零安装兜底」。
- **cloudflared 二进制需要自行获取**：GitHub 直连在本机不通（HTTP 000），本轮是用 `gh-proxy.com` 镜像下的官方 release（版本 2026.9.3）。仓库里不放二进制时，`hasCloudflared()` 会退到 PATH 查找，再不行就走 SSH 隧道。

## 复现步骤（MuMu 上自己再看一遍）

1. 电脑：`cd pi-yz/server && node index.mjs --host 0.0.0.0 --token <你的token> --tunnel`，等 5~20 秒，日志出现 `[tunnel] 远程入口已就绪(cloudflare): https://xxx.trycloudflare.com`。
2. 手机：设置 → 连接 → 顶部「远程访问」卡片显示「已开启 · Cloudflare 隧道」+ 地址 → 点「用这个地址连」，toast 提示「已通过公网连上」。
3. 回开始页：连接卡上是 `https://xxx.trycloudflare.com`、「已连接」、能看到会话列表。
4. 随便进一条会话发一句话 —— 这次请求走的是公网（可在电脑上对照会话 JSONL 的时间戳）。
5. 回连接页点「一键断开」：卡片变「未开启」；电脑上 `curl https://xxx.trycloudflare.com/api/health` 得到 `HTTP 530`；局域网地址仍然可用。
