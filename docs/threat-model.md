# 威胁模型

配套文档：[SECURITY.md](../SECURITY.md)（简版）· [docs/testing.md](testing.md)（这套东西怎么测的）

## 一、系统长什么样

```
   手机 App                  你的电脑
┌──────────────┐  HTTP(S)   ┌──────────────────────┐
│ Flutter 客户端 │ ─────────▶ │ Node 服务端（:30142）  │
│              │ ◀───────── │  · Bearer token 鉴权   │
│  token 存本地 │    SSE     │  · server/.token      │
└──────────────┘            └───────────┬──────────┘
                                        │ 进程内调用（无网络边界）
                                ┌───────▼────────┐
                                │ pi 的 AgentSession│  ← 能跑命令、读文件
                                └────────────────┘
```

关键一点：**服务端和 pi 之间没有边界**。谁能发号施令给服务端，谁就能在你的
电脑上跑命令、读文件。所以这套系统里真正需要守的只有一样东西：**token**。

（远程访问模式只是给这条链换一个入口：手机 → Cloudflare/localhost.run 隧道 →
电脑上的同一个服务端。鉴权还是同一个 token。）

## 二、要保护的资产

| 资产 | 泄露/被滥用的后果 | 存在哪 |
|---|---|---|
| **token** | 等于别人能操作你的电脑 | 手机本地（Keystore）+ 电脑上的 `server/.token` |
| 连接配置（地址、端口） | 只暴露「你有一台机器」 | 手机本地 |
| 会话内容 / 文件内容 | 隐私 | 全在电脑上，客户端只是显示器 |
| 命令执行能力 | 最高后果 | 只由服务端持有，靠 token 把关 |

## 三、按攻击者逐条看

### A. 同一网络里的其他人（被动嗅探 / 主动扫描）

**主动扫描**（扫到 30142 端口后直接调 `/api/*`）：✅ 防住。
每个接口都要 `Authorization: Bearer <token>`，而 token 是服务端首次启动时
生成的随机串（存在 `server/.token`，权限依赖文件系统）。没有它，任何接口都返回 401。

**被动嗅探**（局域网里抓包）：❌ 不防。
局域网直连走 `http://`，token 明文过网。

> **为什么不做自签 TLS**：要让你在手机上手动信任一张自签证书，还得处理证书过期、
> 换 IP 后重新签 —— 体验代价很大，而「家里的 WiFi」本来就在你的控制下。
> 取舍是：**局域网当可信网络，不可信网络请用远程访问（HTTPS 隧道）**。
> 这条写在 SECURITY.md 里明说了，不假装它安全。

### B. 捡到手机、但没解锁的人

✅ 防住。App 数据在应用沙箱里，且连接配置里**没有 token**（2026-10 起）。
token 在 Keystore 加密存储，密钥不可导出。

### C. 拿到手机、能安装/运行恶意 App 的人

✅ 基本防住：
- 应用沙箱不让它读别的 App 的私有目录；
- 即使通过备份、云同步拿到了文件，磁盘上也只有密文；
- Keystore 的密钥不可导出，恶意 App 无法复制走。

⚠️ 但**能读到本 App 进程内存**的攻击者（例如 hook 框架）不在这个模型里 ——
见 D。

### D. 手机被 root、且攻击者能实时调试本 App

❌ 不防。Keystore 保护好密钥本身，但运行时 token 必然会以明文出现在进程内存里
（要发给服务端就躲不开），而且攻击者可以直接替你发请求、根本不需要 token。

**这类攻击者已经越过 App 层能防守的边界**，要应对得靠设备层的完整性校验
（Play Integrity 之类），目前没做。

### E. 电脑本身已经被人控制

❌ 不防，也没法防。服务端住在上面，`server/.token` 就是电脑上的一个文件。
token 是门锁，不是防弹门。

### F. 网络中间人（远程访问模式）

取决于隧道提供方。远程访问走 Cloudflare / localhost.run 提供的 HTTPS，
链路加密由它们保证；本 App **没有做证书固定**（pinning），也拿不到它们的私钥。

### G. 恢复备份 / 换机后旧数据被复用

✅ 防住。密文是用设备 Keystore 里的密钥加密的，换设备后密钥不同 →
GCM 认证失败 → 程序把它当成「读不到」，请用户重新输入 token，
**绝不猜测、绝不静默用错的值**。这条在真机上验证过（见下）。

## 四、token 的存储实现

```
Android 6.0+                     桌面 / 测试环境
─────────────                    ──────────────
Keystore（密钥不可导出）           无 Keystore
   │  AES-256/GCM                   │
   ▼                                ▼
pi_yz_secure_tokens.xml          server_token_v1_<id>
（base64 密文）                   （明文，独立键）
已加密 ✅                          未加密 ⚠️ 界面如实提示
```

四条实现上的硬要求（写在 `android/.../SecureTokenStore.kt` 的注释里）：
1. **GCM 而不是 CBC**：CBC 不校验完整性，密文改一位照样解出垃圾明文。
2. **IV 每次随机、与密文一起存**：IV 不是秘密，但绝不能重复。
3. **不开 `setUserAuthenticationRequired`**：开了就要求指纹/锁屏，用户没开锁屏
   就直接用不了 —— 那是可用性事故，不是安全收益。
4. **解密失败一律当「读不到」**：换机、清数据、系统重置 Keystore 都会这样。

### 一条有意保留的降级路径

Keystore 写不进去时（设备异常、密钥被系统重置），程序退回老做法：
把 token 也写进连接配置的 JSON。

**为什么**：留在明文里是**风险**，把 token 弄丢是用户**立刻连不上且无法自救**
（他多半不记得那串随机 token）。两害相权，选轻的那个。界面上「token 存放方式」
那一行会如实反映当前状态，不谎报。

## 五、真机验证记录

**环境**：MuMu 模拟器 · Android 15（API 35）· debug 构建 · 2026-10-09

| # | 验的是什么 | 怎么验的 | 结果 |
|---|---|---|---|
| ① | 旧明文能被迁移走 | 往 `FlutterSharedPreferences.xml` 注入旧格式（含明文 token）→ 启动 App | 明文从连接配置里**消失**；`pi_yz_secure_tokens.xml` 出现 base64 密文 |
| ② | 密文能被正确解密 | 把 host 改成一台记录式假服务端（**prefs 里不含 token**）→ 启动 App | 服务端收到 `Authorization: Bearer MIGRATION-TEST-TOKEN-1234567890` |
| ③ | 换机/恢复备份不崩 | 备份密文 → 卸载重装（Keystore 密钥随之重置）→ 回填旧密文 → 启动 | 进程存活、**0 条 FATAL**、请求里 token 为空（被正确当成读不到） |

②是这三条里最有说服力的一条：它同时证明了「token 不在配置文件里」和
「token 能从密文里正确取出来用」两件事。

复现 ①②③ 的命令（在装有 MuMu 的机器上）：

```bash
MM=/d/ruanjian/MuMuPlayer/nx_main/MuMuManager.exe   # MuMuManager 路径按实际改
D=/data/data/com.youzhi.piyz.pi_yz

# 看连接配置里有没有明文 token（新版应该没有）
"$MM" sh -v 0 --cmd "run-as com.youzhi.piyz.pi_yz cat $D/shared_prefs/FlutterSharedPreferences.xml"

# 看密文文件（内容是 base64，看不到 token 本身）
"$MM" sh -v 0 --cmd "run-as com.youzhi.piyz.pi_yz cat $D/shared_prefs/pi_yz_secure_tokens.xml"
```

（`run-as` 只对 debug 构建有效。）

## 六、已知弱点与可做的加固

| 弱点 | 现状 | 要加固的话 |
|---|---|---|
| 局域网明文过网 | 有意取舍，文档写明 | 自签 TLS + 首次连接指纹确认 |
| 桌面端明文存储 | 回落实现，界面如实提示 | Windows DPAPI / macOS Keychain |
| 无证书固定 | 依赖隧道提供方的 TLS | pin 隧道证书（但会影响换证书时的可用性） |
| 无请求防重放 | 未做 | token 签名 + 时间戳 nonce |
| token 不能轮换 | 需要改 `server/.token` 并重配客户端 | 加一个「重新生成 token」的界面入口 |
| 设备完整性校验 | 未做 | Play Integrity（会引入 Google 依赖，与项目「不引第三方插件」的取向冲突，需要权衡） |
