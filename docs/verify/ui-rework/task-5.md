# task-5 · 会话内一键浮动切换模型与思考等级（已完成）

证据目录：`docs/verify/ui-rework/task-5/`（7 张实机截图 + 落盘记录）。

---

## 做了什么

**入口**：会话页顶部新增一枚**模型胶囊**，直接显示「模型名 · provider」，点一下弹出切换面板。
以前只有打 `/model` 命令才会出选择器 —— 手机上没人会去记这个。

**面板**（`模型与思考等级`）：

- 顶部一行「当前：<模型名> · <provider>」；
- 思考等级一排 chip（`off / low / high / max`，当前那个凹进去高亮）；
- 模型列表**按 provider 分组**（`deepseek` 一组、`opencode-go` 一组），每行显示
  「模型名」+「provider · 上下文 · 是否支持思考」，当前模型打 ✓；
- 点一下就切，**不离开会话**。

`ServerStore.setModel` / `setThinkingLevel` 从 `Future<void>` 改成 `Future<bool>`，
失败时把原因写进 `lastError`（以前切失败只会在日志里，界面完全没反应）。

---

## ① 不离开会话即可切，且下一条消息确实用新模型

**落盘证据**（测试会话 `D:\powershell`，会话文件逐行读出来的）：

```
[model_change] provider=opencode-go modelId=deepseek-v4.1-flash   (19:56:20 会话建立)
[model_change] provider=deepseek    modelId=deepseek-flash        (19:57:23 ← 我在 App 里切的)
[user] reply ok
[assistant] provider=deepseek model=deepseek-flash stop=stop      ← 回复真的来自新模型
```

截图：`03-switched-to-deepseek.png`（切完胶囊与面板都变成 `deepseek`，deepseek 组的行打上 ✓）
→ `04-after-send.png`（发出去、拿到回复）。

---

## ② 一眼看出模型属于哪个 provider

胶囊本身就带 provider（`DeepSeek V4.1 Flash · opencode-go`），
面板里也是按 provider 分组列出来的 —— `02-switcher-grouped-by-provider.png` 能同时看到
`deepseek`（官方）与 `opencode-go`（中转）两组，切换时不会糊。

这一条是用户明确点名的需求（"一眼看出用的是 opencode-go 还是 deepseek 官方"），
也是**额度用尽时要靠它来判断当前跑在哪家**。

---

## ③ 切换失败给出具体原因（并且修掉一个真缺陷）

**踩到的坑**：一开始失败原因是用 `NeuToast` 弹的，结果**什么都看不到** ——
底部弹层也在 overlay 里、盖在 toast 上面，弹层内部弹的 toast 被自己挡住了。
这属于「看起来没做，其实做了但看不见」的假象，必须修。

**改法**：失败原因直接渲染成**面板里的红字行**（在「当前：…」下面），成功才用 toast 提示。

**证据**：`07-failure-reason-in-sheet.png` —— 服务端停掉后点一行模型，
面板里出现「⚠ 没连上服务端，切不了模型」。

（`setModel` 的失败原因优先取服务端返回的原文，例如缺凭据、模型不存在；本次环境里所有 provider
都配了 key，所以用「服务端不可达」这条最容易复现的失败路径来验证。）

---

## ④ 重启后保持所选，且不影响新会话默认值

| 场景 | 截图 | 结果 |
|---|---|---|
| 杀掉 App 再启动，重新打开那条会话 | `05-persists-after-restart.png` | 胶囊仍是 `DeepSeek V4.1 Flash · deepseek` ✓ |
| 新建一条会话 | `06-new-session-keeps-default.png` | 胶囊是 `DeepSeek V4.1 Flash · opencode-go`（默认值没被改） ✓ |

原因：pi 的 `set_model` 写的是**会话记录**（就是上面那条 `model_change`），
不动 `settings.json` 里的默认模型 —— 所以「会话级保持 + 新会话仍用默认」是天然成立的，
这里只是把它实测确认了一遍。

---

## 本项收口自检

| 项 | 结果 |
|---|---|
| `flutter analyze` | No issues found! |
| 实机 | MuMu 上走完「切 → 发 → 重启 → 新建」全链路，证据见 `task-5/` |
| 数据还原 | 测试会话（`reply ok`，D:\powershell）已删除，会话总数回到 **244** |
| 附带修复 | 弹层内 toast 被遮挡 → 改为面板内红字错误行 |
