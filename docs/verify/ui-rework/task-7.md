# task-7 · 设置页能力：App 自身配置 + 默认模型切换（已完成）

证据目录：`docs/verify/ui-rework/task-7/`（4 张实机截图 + settings.json 落盘记录）。

---

## 做了什么

设置页新增一整段 **「App 设置」**（跟「pi 的配置」分开 —— 前者是「我这台手机怎么显示/怎么输入」，
后者是「这台电脑上的 pi 怎么配」）：

| 项 | 怎么存 | 生效方式 |
|---|---|---|
| 外观（跟随系统/浅色/深色） | `AppPrefs` | 换整个外壳配色（本来就有，改为读 AppPrefs） |
| 字体大小：小/标准/大/特大 | `AppPrefs.fontScale` | **整棵树文字一起缩放**（`MediaQuery.textScaler`），立刻生效 |
| 行距：紧凑/标准/宽松 | `AppPrefs.lineHeight` | 消息正文的文字高度（user 气泡 + 正文） |
| 回车键：换行 / 直接发送 | `AppPrefs.sendWithEnter` | 输入框的回车语义 |
| 默认工作区 | `AppPrefs.defaultCwd` | 没打开会话时直接发消息，就在这个目录跑 |
| 新会话默认模型 | 写**电脑端** pi 的 `settings.json` | 只影响新会话 |
| 清理本地数据 | 清草稿 + 常用语 + 离线缓存 | 有二次确认，回执写清清了几项 |
| 打开日志 | `LogPage`（新页面） | 读 `DebugLog`，可一键复制全文 |

新增文件：`lib/server/app_prefs.dart`、`lib/ui/server/log_page.dart`。

---

## ① 配置项齐了

`01-app-settings-section.png` + `03-app-settings-rest.png` 两张就能看全：
字体大小 / 行距 / 回车键 / 默认工作区 / 新会话默认模型 / 本地数据与日志，
加上原有的「连接」（连接管理）与「外观」（主题）。

④ **没有占位项**：这一版里没有放任何「敬请期待」之类的东西。

⑤ **内容可完整浏览**：设置页本来就是 ListView，App 设置段在其下方，滚动即达（第三张截图就是滚动后的样子）。

---

## ③ 改字号真的会变（不是只存了个值）

`01-app-settings-section.png` → 点「大」→ `02-font-scale-applied.png`：
整页文字（标题、说明、chip 里的字）同步变大，选中的 chip 也变成「大」。
实现是 `MaterialApp.builder` 里套 `MediaQuery(textScaler: …)`，所以是**全 App** 生效，不是某个页面。

---

## ② provider 与默认模型可切换，落盘为证

**改法**：新增服务端模块 `server/lib/default-model.mjs` + 接口 `GET/POST /api/config/default-model`，
写的是 `~/.pi/agent/settings.json` 的 `defaultProvider` / `defaultModel` 两个字段
（先写临时文件再 rename —— 那是 pi 的启动配置，写坏了 pi 都起不来；12 个字段原样保留只碰这 2 个）。

**界面**：设置 → App 设置 → 新会话默认模型 → 选择 → 按 provider 分组列出（`04-default-model-sheet.png`，
顶部显示「当前默认：deepseek-flash · deepseek」）。

**落盘证据**（App 里点选之后直接读文件）：

```
点击前: defaultProvider = deepseek     defaultModel = deepseek-flash     （上次 curl 测的）
点击后: defaultProvider = opencode-go  defaultModel = deepseek-v4-flash  （App 写的）
字段数 = 12（没被写坏）
```

**测试后已还原**成原来的 `opencode-go / deepseek-v4.1-flash`，并在末尾核对过。

**与「会话内切换」的区别**（两个都留着，语义不同，界面也分开写清了）：
- 会话内切（任务⑤）：改**当前这条会话**，胶囊按钮里点；
- 新会话默认（本任务）：改**以后新建的会话**，写的是电脑端配置文件。

---

## 本项收口自检

| 项 | 结果 |
|---|---|
| `flutter analyze` | No issues found! |
| 服务端 | `node --check` 通过；接口实测读写正确 |
| 实机 | MuMu 上验证字号整机生效、默认模型面板与写入 |
| 数据还原 | 默认模型已还原为 `opencode-go/deepseek-v4.1-flash` |
| 未做 | 「离线缓存」清理项已在清理逻辑里预留，但离线缓存本身在任务⑮做 |
