# 怎么测这个项目

面向：接手测试的人（以及压缩后的我自己）。这份文档只讲**做法与坑**，
不重复 `flutter test` 的用法。

## 一、先看这个数字再决定测什么

```
总行覆盖率 28%    ← 分母被 lib/ui/ 的布局代码撑大（约 12k 行）
逻辑层 ~53%       ← lib/server + lib/services，**这才是该盯的**
```

`lib/ui/` 里大量是纯布局与渲染，写 widget 测试去追行数性价比很低。
**视觉回归交给 golden**（`test/settings_golden_test.dart` 那套），
逻辑正确性交给单元测试。所以补测试的优先顺序是：

1. `lib/server/` 里**手写的解析与状态机**（DTO 的 fromJson、chat_reducer、server_store）
2. `lib/services/` 与平台无关的工具（KeyEncoder、debug_log）
3. `lib/ui/` 只测「有判断逻辑」的部分（门禁类测试更划算，见第五节）

## 二、四类东西，四种测法

| 对象 | 测法 | 例子 |
|---|---|---|
| 手写 DTO 解析 | 喂各种**形状**：缺字段 / 类型不对 / 空对象 / 空数组 | `test/usage_types_test.dart`、`test/dto_types_test.dart` |
| 纯状态机 | 造事件、断言状态与**返回值语义** | `test/chat_reducer_test.dart` |
| 网络层 | loopback 上真起假服务端 + 注入点 | `test/server_client_test.dart`、`test/server_store_test.dart` |
| UDP 发现 / 配对 | 纯解析部分直接测；网络部分同「网络层」 | `test/discovery_test.dart` |

### 1）DTO：重点是「形状容错」，不是字段齐全

服务端字段可能缺、类型可能变，而这些 fromJson 大多**手写且防御式**。
用例该问的是「缺字段时给什么默认值」「类型不对时会不会崩」，而不是把每个字段抄一遍。

```dart
test('cost 是纯 double 时不许抛（曾经被 as Map 强转炸掉）', () {
  expect(() => SessionStats.fromJson({'cost': 0.0072}), returnsNormally);
});
```

**历史教训**：`as Map` 强转一个 double 会抛，表现为「会话信息面板点了没反应」。

### 2）状态机：断言「返回值」的语义，别只断言状态

`applyEvent` 返回 `bool`（要不要重绘）。这个返回值本身就是契约：

```dart
test('未知事件类型：返回 false，不改任何状态', () {
  final r = ChatReducer();
  expect(r.applyEvent(ev('something_brand_new')), isFalse);
});
```

### 3）网络层：loopback 假服务端 + 注入点

```dart
server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
port = server.port;
server.listen((req) async { /* 按路径回响应 */ });

final store = ServerStore(
  clientFactory: (_) => ServerClient(host: '127.0.0.1', port: port, token: 't'),
);
```

为什么不用 mock：`ServerClient` 直接持有 `dart:io` 的 HttpClient（没有注入点），
而 loopback 零依赖、测到的又是**真实代码路径**（URL 拼装、请求头、状态码映射、超时）。

`ServerStore({clientFactory})` 这个注入点是**专门为测试开的唯一口子** ——
「主地址失败 → 回落备用地址」这条路径不开它就测不了。

## 三、五个必须知道的坑（都踩过）

| 坑 | 现象 | 解法 |
|---|---|---|
| **flutter_test 会把 HttpClient 换成返回 400 的 mock** | 真连 loopback 报 `HTTP 400（空响应）` | 测试里 `HttpOverrides.global = null;`，用例结束再装回去 |
| 假服务端**写响应必须用 UTF-8** | 中文正文抛 `Contains invalid characters` | `response.add(utf8.encode(body))`，不要用 `write()` |
| **SSE 推完要 close** | 报 `Connection closed while receiving data` | 不 close 时 response 没人引用、连接被提前回收 |
| **`AppPrefs.load()` 是幂等的** | 第二个用例改 mock 值不生效 | 「默认值」断言必须放在最前面 |
| **fire-and-forget 请求还在飞就断开** | `HttpException: Connection closed…` | 收尾用 `await Future.delayed(80ms)` 再 disconnect |

另外两条小的：

- 「没人监听的端口」**别用 `port + 1`** —— 它会撞上别的服务（报 Invalid response line），
  用端口 `1` 才可靠；
- 造 `Flutter` 风格字符串时注意 shell 转义：`python - <<'PY'` 里的 `\n` 会被吃一层，
  要写 `\\n`；涉及反斜杠的脚本**写成文件再跑**更省事。

## 四、SSE 的帧格式（写假服务端要知道）

真实服务端（`server/lib/sse.mjs`）两种帧：

```
data: {"type":"message_start", ...}\n\n        ← 无名事件，客户端按 name='message' 处理
event: snapshot\ndata: {...}\n\n               ← 具名事件
```

关键实现细节：**`openSession()` 只订阅事件流、不主动拉快照** ——
会话内容靠 `event: snapshot` 帧推来。所以假服务端的 events 端点必须推一帧 snapshot，
否则 `chat.messages` 永远是空的。

## 五、什么时候不写测试

- **纯布局**：用 golden 基线（三种宽度已经有了，平板档待补）
- **「配对」类不变式**：写成**源码级门禁测试**更划算，例如
  `fold_gating_test.dart`（折叠头必须与门控配对）、`startup_tab_test.dart`
  （启动不许自动切 tab）。它们读源码做断言，不会因为 UI 重构失效。
  写这类测试时**先跑一次确认它会红**（负向验证），否则可能是个只会绿的摆设。

## 六、门禁与流程

```bash
flutter analyze                     # 期望 No issues found
flutter test                        # 期望全过（golden 也要跑）
flutter test --coverage             # 看覆盖率；CI 里会把摘要打进日志
```

- 每个改动都跑一遍，**别攒到最后**；
- `dart format lib test tool` —— CI 会检查格式；
- 新增测试**单独提交**，方便回溯；
- 覆盖率**暂时不设阈值**：基线不稳时设阈值只会逼人写凑数测试。
  等关键路径补齐（见下）再考虑。

## 七、还没测到的（接手可从这里继续）

| 目标 | 未覆盖行数 | 备注 |
|---|---|---|
| `server_store.dart` | 507 | 命令 / 凭据 / 远程访问等细分路径 |
| `server_client.dart` | 190 | 40+ 个薄包装方法，共用已测的 `_json` 路径 |
| `notification_center.dart` | 173 | 已有 18 个用例，补强 |
| `diagnose.dart` | 96 | 已有 11 个用例 |
| `lib/ui/` | — | 交给 golden，别追行数 |
