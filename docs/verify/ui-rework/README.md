# UI 改造阶段的工作记录

改造目标：`musdn4vd-oqgeny`（23 项，先功能后 UI）。
本目录按任务编号记录每一步的**证据与取舍**，每条都能用命令复核。

---

## task-1 · 死代码清理（已完成）

### 怎么找出来的

从 `lib/main.dart` 出发做 **import 可达性分析**（递归解析 `import`/`export`，跳过 `package:` 与 `dart:`），
凡是走不到的文件就是死代码。脚本见本节末尾，可复跑。

结果：**可达 36 个文件，不可达 17 个（6321 行）**。

### 删了哪些（16 个，5780 行）

| 文件 | 行数 | 为什么是死的 |
|---|---:|---|
| `lib/ui/home_page.dart` | 1061 | SSH 时代的首页，已被「开始」页（`ui/server/sessions_page.dart`）取代 |
| `lib/ui/terminal_page.dart` | 780 | **用户明确决定不做终端**，直接删（不再列为待补项） |
| `lib/ui/profile_edit_page.dart` | 712 | SSH 主机编辑页，服务端路线不需要 |
| `lib/ui/debug_page.dart` | 699 | SSH 时代调试页，依赖下面两个待删服务；日志入口改到任务⑦重建 |
| `lib/ui/settings_page.dart` | 480 | 旧设置页，已被 `ui/server/settings_page.dart` 取代 |
| `lib/ui/host_sheet.dart` | 405 | SSH 主机选择弹层 |
| `lib/ui/theme_preview_page.dart` | 356 | 设计稿预览页（开发用画廊） |
| `lib/ui/profile_preview_page.dart` | 235 | 同上 |
| `lib/ui/home_preview_page.dart` | 194 | 同上 |
| `lib/ui/icon_preview_page.dart` | 194 | 同上 |
| `lib/services/rpc_probe.dart` | 157 | SSH 探测，只有 debug_page 在用 |
| `lib/ui/settings_preview_page.dart` | 141 | 预览页 |
| `lib/ui/session_preview_page.dart` | 130 | 预览页 |
| `lib/ui/shell_preview_page.dart` | 101 | 预览页 |
| `lib/main_preview.dart` | 87 | 预览入口 |
| `lib/services/storage_service.dart` | 48 | SSH 主机本地存储，只有 debug_page 在用 |

删除前整包备份：`/tmp/pi-yz-dead-code-20261003.tar.gz`（44KB）。

### 保留了哪个（1 个，541 行）

| 文件 | 理由 |
|---|---|
| `lib/ui/key_bar.dart` | **手机打不出的按键条（Esc/Tab/方向键/Ctrl 组合）已经写好，只是没接进输入栏** —— 任务④把它接进输入区。它不是废代码，是没插线的功能。 |

### 连带调整

`test/widget_test.dart` 里有 12 个用例测的是上面删掉的页面（首页 4、旧设置页 3、SSH 连接配置页 3、旧会话页 2），
它们随代码一起删除；另有 2 个用例（减少动态、深色档）原本挂在旧首页/旧设置页上，已**改测活外壳**：

- `flutter test`：**25/25 通过**（改造前 37 个，其中 12 个测的是已删代码）
- `flutter analyze`：**0 issue**
- 复扫死代码：**可达 36 / 不可达 1**（只剩待接线的 `key_bar.dart`）

被删掉的 12 个用例覆盖的是不再存在的界面，属于合理缩减；
**服务端路线的新页面（开始/会话/设置/文件）目前没有 widget 测试**，这是已知缺口，
在任务④与 UI 阶段（任务㉑㉒）补上真实页面的用例。

### 复跑验证

```bash
# 1) 复扫死代码（应只剩 key_bar.dart 一个）
python - << 'PY'
import os, re, io
imp_re = re.compile(r"""^\s*(?:import|export)\s+'([^']+)'""", re.M)
seen=set(); stack=['lib/main.dart']
while stack:
    f=os.path.normpath(stack.pop()).replace(os.sep,'/')
    if f in seen or not os.path.exists(f): continue
    seen.add(f)
    for imp in imp_re.findall(io.open(f,encoding='utf-8').read()):
        if imp.startswith('package:') or imp.startswith('dart:'): continue
        stack.append(os.path.join(os.path.dirname(f), imp))
allf=[os.path.join(dp,x).replace(os.sep,'/') for dp,_,fs in os.walk('lib') for x in fs if x.endswith('.dart')]
print('可达 %d / 不可达 %d' % (len(seen), len(set(allf)-seen)))
for d in sorted(set(allf)-seen): print('  ', d)
PY

# 2) 静态检查与测试
flutter analyze      # 期望 No issues found!
flutter test         # 期望 25/25 All tests passed!
```

---

## 本目录文件

| 文件 | 内容 |
|---|---|
| `README.md`（本文） | task-1 死代码清理的记录 + 复跑脚本 |
| `task-2.md` | task-2 用户点名的六个缺陷：根因、改法、修复前/后截图与复现步骤 |
| `task-2/` | task-2 的证据截图（修复前 2 张 + 修复后 6 张） |
| `task-3.md` | task-3 六项同类缺陷：截断/不可滚/editorText/草稿/弹层/错误态重试 |
| `task-3/` | task-3 的证据截图（10 张） |
| `task-4.md` | task-4 键盘条接线：按键→pi 动作的映射表、逐键实测证据 |
| `task-4/` | task-4 的证据截图（9 张） |
| `task-5.md` | task-5 会话内切模型/思考等级：落盘证据、provider 分组、失败原因 |
| `task-5/` | task-5 的证据截图（7 张） |
| `task-6.md` | task-6 输入区能力：模板、素材直传、误发保护撤回 |
| `task-6/` | task-6 的证据截图（6 张） |
| `task-7.md` | task-7 设置页：App 自身配置（字号/行距/回车/工作区/清理/日志）+ 默认模型写入 |
| `task-7/` | task-7 的证据截图（4 张） |
| `task-8.md` | task-8 用量可视化：口径、逐轮明细、对账记录 |
| `task-8/` | task-8 的证据截图（3 张） |
| `task-10.md` | task-10 后台保活：机制、竞态 bug、落盘证据、Android 限制 |
| `task-10/` | task-10 的证据截图（2 张） |
| `task-17-plugin.md` | task-17 电脑端做成 pi 插件：目录结构、命令、装卸验证 |
| `task-19-i18n.md` + `task-19/` | task-19 界面中英切换 + 复用两份电脑端汉化表：做法、验证、术语对照、覆盖范围（6 张截图） |
