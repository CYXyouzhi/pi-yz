# task-1 盘点：MuMu 实测 bug 与设计偏差清单

盘点时间：2026-10-03
设备：MuMu 模拟器（Android 15，1080×1920，density 480）
App：`com.youzhi.piyz.pi_yz`（release 51.4MB）
服务端：`pi-yz-server` @ 10.1.1.195:30142

截图证据都在本目录：`t1-*.png`

## 交互通道（工具链结论）

MuMu 踩坑记录，后续测试都依赖这个：

```
App 跑在虚拟 display 上，不是主屏
  input     要「逻辑 display id」        → 29 / 30 / 31（会变）
  screencap 要「物理 token」             → 46198278...（uniqueId "local:xxx"）
传错不报错，只是静默无效
display id 在 force-stop 后会变，必须每次探测

探测方法：逐个 screencap + 中心 40×40 亮度 > 8 判定非黑屏
工具：tool/ctrl.py（tap / swipe / text / key / shot，自动处理上述映射）
```

## 一、已验证正常的功能

| 功能 | 证据 |
|---|---|
| 连接与自动重连 | `t1-home.png` 已连接 1.0.0 · 246 条会话 |
| 会话列表按工作区分组 + 默认折叠 | `t1-home.png` 6 组全收起 |
| 工作区展开 | `t1-ws-expanded.png` |
| 打开历史会话并渲染历史 | `t1-chat-history.png` 已载入 13 条 |
| 思考块折叠显示 | `t1-chat-history.png` 有「思考 ›」 |
| 工具卡片（名称/副标题/状态标签） | `t1-chat-history.png` ask_user_question「完成」 |
| 命令面板（中文命令名完整、两行显示） | `t1-cmdpanel.png` /汉化 完整 |
| 新建会话 → 工作区选择器 | `t1-newws.png` |
| 发消息 + 流式渲染 | `t1-stream-a.png` / `t1-stream-b.png` |
| 用户气泡（accent 实心）与助手气泡（隆起）区分 | `t1-stream-a.png` |
| 底部 tab 三等分 / 选中内凹撑满 | `t1-home.png` 底部 |

## 二、Bug 清单（按优先级）

### P0 — 影响核心可读性

**B1. Markdown 完全未渲染**
`t1-chat-history.png`：模型回答里的表格 `| 线路 | 对象 | 已有基础 |`、行内代码
`` `~/.pi/agent/extensions/pi-cn` `` 都按纯文本显示。
pi 的回答大量使用标题/列表/代码块/表格，不渲染等于不能读。
设计稿也预留了 `mdHeading / mdCode / mdLink / mdQuote / mdListBullet` 等 token。

**B2. 底部内容被 tab 栏遮挡**
`t1-home.png`：「ceshi」分组被 tab 栏切掉一半；
`t1-settings.png`：关于卡片最后一行「HTTP + SSE 连接。」被遮住。
原因：页面 ListView 的 bottom padding（24）小于 tab 栏高度（约 70 + 11）。

### P1 — 逻辑错误

**B3. 连接页「已保存」条目两行文字完全重复**（`t1-conn.png`）
两行都是 `10.1.1.195:30142`。因为 `displayName` 在 name 为空时回退到 endpoint，
而第二行本来就显示 endpoint。应改成「名称」+「地址」。

**B4. 配置名为空时保存没有兜底**（`t1-conn.png`）
配置名称框是空的（显示 placeholder），但配置已存在且被选中。
应自动填「未命名」或用地址当名字。

**B5. 返回键直接退出 App**（实测：打开命令面板时按 BACK，直接退到系统设置页）
手机上返回键应先收起命令面板 → 再返回会话列表 → 最后才退出。

### P2 — 视觉/体验

**B6. 工作区展开后，会话行没有卡片包裹**（`t1-ws-expanded.png`）
设计稿是「一张分组卡包住所有工作区会话」（iOS inset-grouped），
现在分组头是卡片、会话行是裸行，层级不清。这是重构懒加载时丢的。

**B7. 命令面板高度过大**（`t1-cmdpanel.png`）
占屏幕约一半，把消息区挤没。设计稿 `keyBarHOpen = 244`，应参考收敛。

**B8. 工作区选择器面板偏简陋**（`t1-newws.png`）
纯色面板 + 顶部圆角，没有把手（grabber）、没有取消按钮、没有玻璃/隆起材质。

**B9. 会话行缺少分隔线**
inset-grouped 需要 hairline 分隔，现在纯靠间距。

## 三、待补功能（对齐 pi-web，对应 task-4/5/6）

| 功能 | 现状 |
|---|---|
| 会话搜索 | 服务端无接口 |
| 会话重命名 | 服务端有 `set_session_name`，UI 无入口 |
| 分支树浏览 | 服务端有 `get_tree`，UI 无入口 |
| 导出 HTML | 服务端有 `export_html`，UI 无入口 |
| 文件浏览 / git diff / @引用 | 完全未做 |
| 模型列表页 / 技能 / MCP 管理 | 完全未做 |

## 四、下一步

按优先级修：B1（Markdown）→ B2（遮挡）→ B6（会话行卡片）→ B3/B4（连接页）→ B5（返回键）→ B7/B8/B9（面板与分隔线），
然后进 task-4/5/6 补功能。
