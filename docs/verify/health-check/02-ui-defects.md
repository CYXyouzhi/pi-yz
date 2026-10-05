# 02 · UI 缺陷（task-3）：遮挡、过小、溢出与命令面板

方法：**实机逐屏截图**（MuMu 1080x1920，截图坐标 x2）比静态扫描有效得多 ——
下文第 3、4 两处都是"词条语义与调用点对不上"，任何静态规则都抓不到（试过：
写了「时间语义 vs 参数名」的启发式规则，扫出 14 处候选，逐个看全是误报），
只有真机上看一眼才发现「248 天前」这种明显错误。

## 1. 命令面板高度没有扣掉键盘占用（contract 明确要求项）

**位置**：`chat_page.dart` 的 `_buildSuggestions`。

**症状**：面板高度按 `MediaQuery.sizeOf(context).height * 0.45` 算。这个值是**整屏高度**，
软键盘弹起后并不缩小；于是键盘会盖住面板底部若干条命令，用户以为「命令就这些」。

**修法**：改成从「键盘之上的可用高度」取比例，并把下限从 180 收到 160、上限放到 420：

```dart
final media = MediaQuery.of(context);
final available = media.size.height - media.viewInsets.bottom;
final maxHeight = (available * 0.45).clamp(160.0, 420.0);
```

**验证说明（要诚实）**：MuMu 模拟器是物理键盘模式，即使设了
`settings put secure show_ime_with_hard_keyboard 1` 也不弹软键盘，
所以**这一处只有代码级验证，没有「键盘弹出前后」的实机对比图**。
（同一批里其他 `showModalBottomSheet` 用的都是框架自带的 bottom sheet，
它自身会避让 `viewInsets`，不受此问题影响。）

## 2. 会话页顶部：会话名与地址被右侧按钮挤住

**症状**：头部第一行是「会话名 + 地址胶囊 + 状态点」，三个元素**都没有 `Flexible`**；
而这一行的右边还有分享 / 详情 / 新建三个圆形按钮。会话名一长，地址就被推到按钮底下，
看起来像「被遮住」（截图 `ui-01.png` 里 `10.1.1.195:30142` 只露出 `10.1.1.19`）。

**修法**：会话名与地址胶囊都包 `Flexible` + `maxLines: 1` + `TextOverflow.ellipsis`，
让它们先收缩，按钮永远完整可见。

## 3. 开始页显示「248 天前」（词条内容张冠李戴）

**症状**：连接卡片副标题显示 `248 天前`。App 才开发几天，不可能。

**根因**：`sessions_page.dart:936` 在「已连接」分支里传的是 `piVersion` 与 `sessions.length`：

```dart
I18n.tp('ui.33716d0005', {'v': _store.health?.piVersion ?? '', 'n': _store.sessions.length}),
```

而词条 `ui.33716d0005` 的内容却是 `{n} 天前` / `{n} d ago` ——
**语义与调用点完全无关**，于是 248 个会话被渲染成「248 天前」。
（这类问题占位符名是匹配的，所以设计令牌检查、占位符检查、逐调用点参数检查**全都看不见**。）

**修法**：按调用点语义订正词条内容为 `pi {v} · {n} 个会话` / `pi {v} · {n} sessions`。

## 4. 「技能与命令」之上那个 section 标题显示成「N 分钟前」

**症状**：`config_page.dart` 里渲染「已安装的 pi 插件」的 section，
标题却是 `{count} 分钟前` / `{count} min ago`。

**根因**：同第 3 处 —— 词条 `ui.9d3c5fe8d6` 内容是时间语义，调用点传的是
`_packages.isEmpty ? '' : '（${_packages.length}）'`。
对照同文件其他 section 标题（`思考等级` / `内置命令` / `MCP 服务器` / `Provider 凭据` / `技能与命令`）
都是名词短语，可见这一条是被写错的。

**修法**：订正为 `pi 插件{count}` / `pi plugins{count}`。

## 5. 命令面板里长描述换行后出现「孤儿词」

**症状**：`/quota-fallback` 的描述「额度兜底：查看状态 / on / off / switch 手动切换」
折行后第二行只剩「切换」两个字。

**判断**：这是**排版观感问题**，不是 bug —— 描述来自电脑端插件自己声明的文案，
强制截断会让信息缺失。**本轮不改**，如实记录；若后续要做，
应在服务端把描述压到一行的长度，而不是在客户端砍字。

## 6. 未发现的问题

- **点击区域过小**：抽查的按钮/行都走了 `NeuPressable`，其 `padding` 由令牌给定，
  未发现小于 40dp 的点击目标。
- **RenderFlex overflow**：本轮截图与运行日志里**未出现**黄黑条纹或 overflow 警告
  （主消息列表用 `ListView.builder` 懒加载、无 `shrinkWrap`，是正确写法）。


---

## 七、第二轮补充：命令面板适配的验证方式（审计指出证据弱）

**审计意见成立**：命令面板是目标点名的要求，第一轮只有代码级改动、
自述「模拟器不弹软键盘所以没有对比图」，属弱证据。

**补强做法**：把高度计算**抽成纯函数** `slashPanelMaxHeight(MediaQueryData)`，
用单测**分别钉住四种情况** —— 比截图更硬：截图只能拍到「当前这一种状态」，
单测能直接控制「键盘高度」这个自变量。

```dart
// lib/ui/server/chat_page.dart
double slashPanelMaxHeight(MediaQueryData media) {
  final available = media.size.height - media.viewInsets.bottom;
  return (available * 0.45).clamp(160.0, 420.0);
}
```

测试（`test/slash_panel_height_test.dart`，4 项全过）：

| 用例 | 输入 | 期望 | 说明 |
|---|---|---|---|
| 没有键盘 | `size=400x800`, `viewInsets=0` | 360 | 800 × 0.45 |
| **键盘弹起** | 同上 + `viewInsets.bottom=400` | **180** | (800−400) × 0.45 —— **面板确实随键盘变矮** |
| 极端小空间 | `size=400x300`, `viewInsets.bottom=250` | 160 | 触到下限，不会缩成 0 |
| 大屏 | `size=400x1920` | 420 | 触到上限，不占满整屏 |

复现：`flutter test test/slash_panel_height_test.dart`


---

## 八、命令面板键盘实机证据：尝试记录与最终结论

审计要求这一项要有 **MuMu 实机截图**。本轮**试了四条路，实机截图在 MuMu 上走不通**，
如实记录尝试过程，避免下次重复踩：

| # | 尝试 | 结果 |
|---|---|---|
| 1 | `settings put secure show_ime_with_hard_keyboard 1` 后点输入框 | 无键盘（物理键盘模式下该开关不生效） |
| 2 | 改成 `0`（关闭物理键盘模式）后点输入框 | 仍无键盘 |
| 3 | `ime list -s` 查到搜狗输入法 → `ime enable` + `ime set` 设为默认 | 设置成功（`default_input_method` 已变成搜狗），点输入框**仍不弹** |
| 4 | 直接截图核对 | `kb-02-slash-panel.png`：面板正常显示，底部仍是 `Home/Chat/Settings` 导航栏，**没有键盘** |
| 5 | 把 `show_ime_with_hard_keyboard` 设回 **1**（强制：即使有物理键盘也显示 IME）+ 重启 App + 再点输入框 | **仍不弹**（见 `ime-01-no-keyboard.png`） |

**结论**：MuMu 在当前配置下不呈现软键盘，**因此拿不到「键盘弹出前后」的实机对比图**。
这不是"忘了拍"，是模拟器能力限制。

**替代证据（并说明它替代了什么）**：

1. **单测钉住自变量**（`test/slash_panel_height_test.dart`，4 项全过）——
   直接构造 `MediaQueryData` 的 `viewInsets.bottom`，验证面板高度 360 → **180**。
   这一条恰好覆盖了截图**拍不到**的东西：截图只能反映"当前这一种状态"，
   单测能对"键盘高度"这个自变量逐档验证。
2. **键盘避让机制在代码里是完整的**（本轮顺带核实）：
   - `chat_page.dart:3283` 的 `Scaffold` **未显式设置 `resizeToAvoidBottomInset`** → 取默认 `true`，
     键盘弹起时 body 被压缩、面板随之上移；
   - `chat_page.dart:3297` 面板高度按 `size.height - viewInsets.bottom` 计算；
   - `body: SafeArea(bottom: false, ...)` 不与键盘避让打架。

**我不把单测说成实机证据**：它是替代性证据。若要在真机验收这一项，
换一台有软键盘的真机、或关掉 MuMu 的物理键盘模式即可，代码侧不需要再改。

## 九、元素过小的修复（第二轮补充）

审计指出「元素过小」整项未修、且我此前"未发现明显过小的可点元素"的结论被代码证伪（确实成立）：
我说 36dp「符合 Material 最小 40dp」，而 36 < 40 —— 算错了。

**先给出全量清单**（脚本按「图标尺寸 + padding」估算触控目标，共 **76 处 < 40dp**），
再修审计点名的三处：

| 位置 | 修复前 | 修复后 | 做法 |
|---|---|---|---|
| `chat_page.dart:2707` 分支树「从此处分叉」 | **23dp**（图标 13 + padding 5×2） | **41dp** | `all(n5)` → `all(n14)` |
| `chat_page.dart:1390/1406/1415/1424` 头部 4 个按钮（重点模式/分享/详情/新建） | **36dp**（图标 18 + padding 9×2） | **40dp** | `all(n9)` → `all(n11)` |
| `key_bar.dart:460` 折叠态键帽 | **35dp**（高 30 + padding 2.5×2） | **40dp** | `all(2.5)` → `all(n5)` |

**为什么没有一次性全局兜底**：我先试过在 `NeuPressable` 里统一加 `minWidth/minHeight: 40`，
结果 `flutter test` 立刻报 `RenderFlex overflowed by 88 pixels on the right`
（`Row` 里的按钮被强制放宽，撑破头部布局）。改成只兜底高度后，`Center` 仍会让水平方向"尽力大"
而溢出。**结论：触控尺寸不能全局兜底，只能按处修** —— 这个失败尝试也记在这里，
免得以后再走一遍。

**剩余未修的部分（如实登记）**：76 处里还有约 73 处（多为列表行内的小图标、标签行内按钮）。
它们不是审计点名的项，且逐个改会牵动多处布局；本轮先修了被点名的三处与全部 `SizedBox` 间距。
若要继续收敛，建议按"是否在 `Row` 内、是否有挤压风险"分批做，而不是无脑加 padding。


---

## 十、元素过小：全量修复（审计第二轮）

审计指出「元素过小」只做了 3/76、且只改被点名的位置 —— **成立**。本轮做完了。

**扫描口径**（可复现）：对每个 `NeuPressable`，取「内部 `NeuIcon` 的 size + 2 × 垂直 padding」为触控高度。
修前共 **71 处 < 40dp**（`all` 形式 29、`symmetric` 形式 42）。

**批量修法**：把不足部分**加到垂直方向，水平 padding 保持原值**：

| 原形式 | 改成 | 理由 |
|---|---|---|
| `EdgeInsets.all(nX)` | `EdgeInsets.symmetric(horizontal: nX, vertical: nNeed)` | 水平不动 → 不撑破 `Row` |
| `EdgeInsets.symmetric(horizontal: h, vertical: v)` | `..., vertical: nNeed)` | 同上 |

`nNeed` = 向上取整到最近令牌档位的 `(40 − icon)/2`。

**结果**：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| 触控高度 < 40dp 的 `NeuPressable` | **71** | **0** |
| `NeuPressable` 总数 | 137 | 137 |

**为什么只改垂直、不改水平（这是之前失败的教训）**：先试过在 `NeuPressable` 里**全局**加
`minWidth/minHeight: 40`，`flutter test` 立刻报 `RenderFlex overflowed by 88 pixels on the right`
（`Row` 里的按钮被强制放宽，撑破头部布局）；改成只兜底高度后，`Center` 又在水平方向"尽力大"而继续溢出。
**结论：触控尺寸不能全局兜底，也不该动水平方向。**

**实机确认**：改完重装后逐屏截图（`v2-01-chat.png`/`v2-02-home.png`/`v2-03-settings.png`）——
布局正常、无溢出、无遮挡；`flutter test` 103 项全过（含当初被全局兜底弄挂的三个外壳渲染测试）。

## 十一、命令面板：golden 渲染证据（补强第八节）

第八节记录了「MuMu 不弹软键盘」的四条尝试。本轮补一个**可复现的视觉证据**：

```bash
flutter test --update-goldens test/slash_panel_golden_test.dart
#   test/goldens/slash_panel_no_keyboard.png    面板 360dp
#   test/goldens/slash_panel_with_keyboard.png  面板 180dp（viewInsets.bottom = 400）
```

两图已复制到 `shots/`：**无键盘时面板约占画布 45%，键盘占 400dp 时压到约 22%**，
键盘占位对面板高度的压缩一眼可见。（图中文字是方块，因 Flutter 测试环境用 `Ahem` 字体，不影响高度对比。）

**必须说清楚**：这是**渲染证据**，不是实机截图 —— 与第八节单测同类（只是更直观）。
**实机截图仍然没有**，原因见第八节。
