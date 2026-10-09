# 进度

最后更新：2026-10-09。这一个文件管进度，README 不再重复写（两处写同一件事，
必然有一处先过期）。

## 已完成

### 核心

- 会话：列表 / 新建 / 重命名 / 删除 / 归档 / 跨工作区
- 聊天：SSE 流式输出（正文、思考、工具卡片）、排队提示、每轮耗时与用量
- 扩展：斜杠命令、命令面板、扩展弹层（select / confirm / input / editor）
- 分支树：切换 / fork / 导出；Markdown 导出（含表格列宽按比例分配）
- 外观：主题（浅色 / 深色 / 跟随系统）、字号与行距

### 连接

- 多套连接配置 + **备用地址自动回落**（家里走局域网、出门走 VPN，不用手动切）
- **配对**：token 绝不进广播；配对码只在显式开窗后存在、默认 5 分钟、一次性；
  单 IP 冷却 + 全局失败到阈值直接关窗（挡分布式爆破）
- UDP 局域网发现
- 远程访问：localhost.run（内置）/ Cloudflare（需自备 cloudflared）

### 安全

- **token 存进 Android Keystore**：AES-256/GCM，密钥不可导出；旧明文自动迁移，
  Keystore 写不进去时降级且**不丢数据** —— 见 [SECURITY.md](SECURITY.md)
- 威胁模型：[docs/threat-model.md](docs/threat-model.md)（含三条真机验证记录）
- 连接配置里**不再含 token**（泄露连接配置也做不了事）

### 发布

- 服务端可独立分发：`npm pack` 产出 66 kB 纯源码包，换台机器
  `npm install && npm start` 就能跑
- APK 按 ABI 拆分：arm64 **56.5 → 21.5 MiB（−62%）** —— 见 [docs/apk-size.md](docs/apk-size.md)
- GitHub Releases 自动化（Secrets 注入签名）；**没配密钥时不发 Release**，
  免得用户装了之后再也更新不上 —— 见 [docs/release.md](docs/release.md)

### 适配

- 手机竖屏 360~450dp、手机横屏、平板竖屏、平板横屏 —— 5 形态 × 3 组场景，
  见 [docs/tablet-landscape.md](docs/tablet-landscape.md)
- 宽屏内容收窄居中（> 840dp 生效，窄屏零影响）
- 安全区（刘海 / 手势条）让位、点击区 ≥ 48dp

### 质量

- 门禁：`flutter analyze` **0 issue**；**436** 个 Flutter 用例全过
- 逻辑层覆盖率 **81.0%**（`lib/server` + `lib/services`，之前 18.5%）
- 测试方法与踩过的坑：[docs/testing.md](docs/testing.md)
- CI：每次 push / PR 跑格式检查 + analyze + 全量测试 + 覆盖率摘要

## 已知问题

### 功能与体验

- 平板上内容收在 840dp 居中，**没有分栏** —— 更宽的屏幕上左右留白偏多
- 覆盖率的剩余缺口集中在异常分支与 UI 层（`server_store` 184 行、
  `notification_center` 62 行）；UI 层交给 golden 基线，不追行数

### 安全（有意保留的取舍，理由见 SECURITY.md）

- 局域网直连走 HTTP，token 明文过网 —— 不可信网络请用远程访问
- 桌面端没有 Keystore，token 回落为明文存储（界面上如实提示，不假装安全）
- 无证书固定、无请求防重放、token 不能在 App 里轮换

### 未验证

- 平板 / 横屏下的**聊天页、连接页表单、各类弹层**（需要连接态与更多交互）
- 真实的旋转过程（widget 测试里没有旋转事件，只测了静态尺寸）
- 桌面端（Windows）没做过完整验证

## 下一步

| 优先级 | 事项 | 备注 |
|---|---|---|
| 高 | 平板分栏布局 | 超过阈值后左右分栏，比单纯居中更会用空间 |
| 中 | 桌面端用 DPAPI / Keychain 存 token | 现在只有 Android 有系统级保护 |
| 中 | App 内「重新生成 token」入口 | 现在得改 `server/.token` 再重配客户端 |
| 低 | APK 再瘦身（R8 / 混淆） | 预计 1~2 MiB，性价比不如已做的 ABI 拆分 |
| 低 | 补聊天页与弹层的多形态布局测试 | 需要造「已连接 + 有会话」的测试脚手架 |

## 怎么贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。
