# 05 · 实机截图索引（task-5）

设备：MuMu 模拟器 `23117RK66C`，`1080x1920` / density 480。
`tool/ctrl.py` 的截图是**半尺寸（540x960）**，所以**点击坐标 = 截图坐标 x2**。

## 一、修复前 / 修复后对照（task-3 的证据）

| 问题 | 修复前 | 修复后 |
|---|---|---|
| 会话页头部：地址被右侧三按钮挤住 | `before-01-header-occluded.png`（只露出 `10.1.1.19`） | `after-01-chat.png`（`pi ag…` 与 `10.1.1…` 各自省略号收缩，按钮完整） |
| 开始页：显示「248 天前」 | `before-02-248-days.png` | `after-02-home.png`（`pi 1.0.0 · 248 个会话`） |
| 命令面板：`/quota-fallback` 描述折行 | `before-03-slash.png` | `after-04-slash.png` |

## 二、逐页验收（中文模式）

| 页面 | 截图 | 备注 |
|---|---|---|
| 会话页 | `after-01-chat.png` | 头部遮挡已修 |
| 开始页 | `after-02-home.png` | `pi 1.0.0 · 248 个会话` |
| 设置页（上） | `after-03-settings.png` | 连接 / 工作区 |
| `/` 命令面板 | `after-04-slash.png` | 含「（未翻译）」标注 |
| AI 配置页 | `after-05-config-plugins.png` | 底部 `pi 插件（10）`；命令列表与「内置命令（13）」 |
| 连接页 | `after-06-conn.png` | 含新增的「连接诊断」入口；`远程 · think-navigate-theme…` |
| 文件页 | `after-07-files.png` | 面包屑 `powershell` / `D: / powershell`、Worktrees、目录 |
| 诊断页 | `after-08-diagnose.png` | `全部通过`、token 脱敏 `pi********26`、各项耗时 |
| 存储占用 | `after-09-storage.png` | `770 MB`、`248 条会话 · 28 个工作区`、按工作区分组 |
| 设置页（下） | `after-10-settings-bottom.png` | 离线缓存、本地数据与日志、关于 |
| 日志页 | `after-11-log.png` | 空状态 |
| 会话信息（用量） | `after-12-session-info.png` | 模型/思考等级/上下文/tokens/花费/条目 |
| 导出会话 | `after-13-export.png` | 元信息 + 落盘内容预览 |

## 三、英文模式

| 页面 | 截图 | 备注 |
|---|---|---|
| 设置页 | `en-01-settings.png` | `Language: 中文 / English / System` |
| 会话页 | `en-02-chat.png` | 英文界面 |
| 开始页 | `en-03-home.png` | `pi 1.0.0 · 248 sessions`；`No running sessions` |

英文模式的 26 处单复数问题在 task-3 中修掉（例：`1 sessions alive` → `1 session(s) alive`），
本次截图是**修复前**的状态（`1 sessions alive` 可见），修复后的数值形态见
`03-token-convergence.md` 与门禁结果。

## 四、未能覆盖的项（如实说明）

| 项 | 原因 |
|---|---|
| 命令面板「键盘弹出前后」对比 | MuMu 是物理键盘模式，设了 `show_ime_with_hard_keyboard 1` 也不弹软键盘；该修复为代码级验证 |
| 小屏 / 大字体极端设置 | 本轮未做（合同要求的是"逐屏实机截图"，未要求极端档位） |
| 「活动条有工具调用」那一支的截图 | 需要停留在一个有工具调用正在跑的状态才能拍到；本轮未构造 |


---

## 五、证据链时序（修正后，可复核）

**上一轮我犯的错**：`final-01/02/03` 拍在**代码最后修改之前**，所以 `final-02-home.png`
显示的是**旧 APK** 的 `248 session(s)`，与当时源码（已改为 `Sessions: {n}`）不符；
`ime-01-no-keyboard.png` 还与 `final-01` md5 相同，因为两次截图用的是同一个 APK —— **我没有重新构建**。
这是证据管理错误，**已修正**。

**现在的完整链条（时间戳可复核）**：

```
18:12:27  改 lib/server/i18n.dart         （剩余 11 条单复数 → 标签式）
18:12:44  改 lib/ui/server/chat_page.dart （pending 图片 chip 触控 23→41dp）
18:17:09  构建 release APK                （晚于上述所有改动）
18:18:24  v2-01-chat.png / v2-02-home.png / v2-03-settings.png
          ⚠ 这是**归档到 docs/ 后的 mtime**（cp 时间）；拍摄当时在 /tmp 的时间是
          18:17:40 / 18:17:51 / 18:18:01 —— 三者都晚于 APK 的 18:17:09。
```

**复核方式**：

```bash
ls -la --time-style=+%H:%M:%S lib/server/i18n.dart lib/ui/server/chat_page.dart
ls -la --time-style=+%H:%M:%S build/app/outputs/flutter-apk/app-release.apk
ls -la --time-style=+%H:%M:%S docs/verify/health-check/shots/v2-*.png
# 要求：APK 时间 > 两个 dart 文件时间；截图时间 > APK 时间
```

**内容核对**：`v2-02-home.png` 显示 **`pi 1.0.0 · Sessions: 248`** 与 **`Sessions alive: 1`** ——
这正是当前源码能产生的字符串（`i18n.dart:196` = `pi {v} · Sessions: {n}`；
`Sessions alive: {n}`）；旧 APK 的 `248 session(s)` / `1 sessions alive` **已不再出现**。**图与码对应。**

`final-*` 与 `ime-01-no-keyboard.png` 已删除（过时 / 误用）。
