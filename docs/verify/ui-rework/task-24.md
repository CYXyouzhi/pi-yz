# task-24 · i18n 收尾与三处真实缺陷修复

本轮是审计第三轮意见（"i18n 未完成：诊断页 47 处、运行时 toast 42 处、翻译键未接线、英文模式下有中文漏出"）的整改闭环。

## 1. 结论先行

| 指标 | 结果 | 命令 |
|---|---|---|
| 代码里仍是中文字面量 | **0 处** | `python tool/i18n_coverage.py` |
| 定义了却没有调用点的 key | **0 个** | 同上 |
| 已接上的 i18n 调用点 | 1249 个 key（词表 766 条） | 同上 |
| 静态检查 | `No issues found!` | `flutter analyze` |
| 单元测试 | `All tests passed!`（99 条） | `flutter test` |

覆盖率脚本自己会打印 `✅ 代码里没有中文残留，词表也没有闲置条目`；
只要 ① 或 ② 不为 0，它会打印 `⚠ 英文模式下就一定有中文漏出来` —— 现在不打印了。

证据文件：`docs/verify/ui-rework/task-23/07-i18n-final.txt`（覆盖率全量输出）。

## 2. 接线范围（本轮新增）

| 文件 | 处数 | 内容 |
|---|---|---|
| `lib/server/diagnose.dart` | 47 | 诊断页全部判定文案、每步标题、下一步提示、导出报告模板 |
| `lib/server/server_store.dart` | 42 | 全部运行时 toast：上传/失败、worktree、MCP、provider 凭据、模型与思考等级、重连 |
| `lib/server/notification_center.dart` | 11 | 通知栏快速回复、点击直达、压掉原因、卡住判定调试输出 |
| `lib/server/chat_models.dart` | 2 | 截断标记 |
| `lib/server/session_cache.dart` | 1 | 离线缓存截断标记 |
| `lib/main.dart` | 1 | App 标题 |

实现方式：`tool/wire-final.py` 用「中文原文 → 英文」映射表批量生成词条并替换调用点；
带插值的文案走 `I18n.tp(key, {...})`，英文用 `{name}` 占位。

## 3. 本轮修掉的三处真实缺陷

这三处都不是"漏翻"，而是**会显示给用户看的坏东西**，审计没有点出来但确实存在：

### 3.1 占位符不匹配 —— 英文模式下会显示成 `{n}` 字面量

**现场**：设置页连接卡片副标题显示 `· {n} messages · {size}`。

**根因**：词条里的占位符名与调用点传入的参数名不一致（两轮脚本口径不同造成的），
其中 7 处是**词条内容与调用点语义张冠李戴**：

| key | 错误内容（旧） | 按调用点语义订正为 |
|---|---|---|
| `ui.b083df935e` | `· {n} 条 · {size}` | `pi {v}` |
| `ui.ded70fe6ab` | `已删除 · 腾出 {size}` | `提醒已开启{dnd}` |
| `ui.03dd98a903` | `已复制 {n} 条日志` | `默认模型 {provider}/{name}` |
| `ui.1c4dd927c8` | `{n} 小时前` | `今日已用 {today}，接近额度` |
| `ui.5283a21d5b` | `每条 {n} 条消息、` | `今日已用 {today}，额度已用完` |
| `ui.3550a72e44` | `已缓存 {n} 条会话 · 共 {size}` | `连接失败：{e}` |
| `ui.c6729a8150` | `共 {n} 个会话活着` | `登录失败：{e}` |

**扫描方式**：写了一次性检查 —— 遍历所有 `I18n.tp(key, {...})` 调用，
把「词条中/英文要求出现的占位符」与「调用点实际传入的参数名」做差集。
初次扫描 **24 处不匹配**，机械对齐 12 处 + 语义订正 7 处 + 调用点改名 1 处后归零。
**这类问题静态检查（analyze/test）发现不了**，只有这个差集扫描能发现。

### 3.2 诊断页没有入口 —— 页面存在却进不去

`conn_page.dart` 里的 `_openDiagnose()` 有完整实现，但**全工程没有调用点**，
也就是说诊断页是一个只有代码、没有按钮的死页面。
本轮在「扫描局域网」下方补了 `Diagnose connection` 入口（`ui.diagnoseBtn`），
诊断页现在真的可达 —— 这也是能给出下面那张英文截图的前提。

### 3.3 构建门禁曾被自己弄坏（已修复，如实记录）

`DiagStep` 的构造函数带 `const`，而接线后部分调用点含运行时值（如 `explained.reason`），
两者冲突；我在这一个点上反复了六轮（加 const → 去 const → 又加…），
期间 `flutter analyze` 一度是 11 issues、`flutter test` 编译不过。

**最终口径**（写进交接文件避免重犯）：**构造函数保留 `const`，所有调用点与测试里的 `const` 去掉**
（Dart 允许非 const 调用 const 构造函数）。另外 `runDiagnosis` 的默认参数
`Duration(seconds: 8)` 需显式写成 `const Duration(seconds: 8)` 才不报 `non_constant_default_value`。

## 4. 实机验收（英文模式）

设备：MuMu 模拟器（1080×1920，density 480），release APK。

| 截图 | 内容 | 关键观察 |
|---|---|---|
| `10-chat-en.png` | 会话页 | `Message` / `Continue` / `Try again` / `Idle`，无中文 |
| `11-settings-en.png` | 设置页 | `Connection` / `Workspace` / `Appearance`；连接卡片副标题为 **`pi 1.0.0`**（修复前是 `· {n} messages · {size}`） |
| `12-conn-en.png` | 连接配置页 | `Remote access` / `Enabled · Cloudflare tunnel` / `Scan LAN` / **`Diagnose connection`（新入口）** / `Saved` |
| `13-diagnose-en.png` | **诊断页** | `Connection diagnosis`；`All passed 1554 ms`；`DNS resolution` / `Port reachability` / `Health check & latency: 3 samples · fastest 0ms · average 2ms` / `Server info: pi 1.0.0 · 1 active sessions` / `Authentication: Token accepted`；**token 显示为 `pi********26`（脱敏）**；底部 `Re-diagnose` / `Copy result` |

这四张连起来覆盖了审计质疑的完整链路：
**设置页 → 连接配置页 → 诊断页**，三页在英文模式下都没有中文残留，
且诊断页的结果正文（原来最集中的 47 处）已全部走 `I18n.t`。

## 5. 复现命令

```bash
cd pi-mobile
flutter analyze                        # 期望 No issues found!
flutter test                           # 期望 All tests passed!（99）
python tool/i18n_coverage.py           # 期望 ① 0 处、② 0 个、末尾 ✅
python tool/wire-final.py              # 幂等：重复跑不会重复加词条
```

## 6. 仍未做的（诚实登记）

- 词表里存在少量**同文案两个 key** 的情况（如 `ui.1f75ab9c48` 与 `ui.9d3c5fe8d6` 都是「N 分钟前」），
  功能与显示都正确，属可合并的冗余，未做合并以免动调用点。
- `notification_center.dart` 的 `debugPrint` 调试日志本轮**直接改写为英文**而未进词表
  （面向开发者而非用户，进词表反而增加维护面）；这些字符串含 `[notif]` 前缀，便于 grep 定位。
