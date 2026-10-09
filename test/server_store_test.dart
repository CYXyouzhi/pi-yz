// ServerStore 的连接状态机与事件流守卫。
//
// 为什么值得专门搭一套假服务端：`server_store` 是 1900 行的状态中枢，之前只有 3% 覆盖，
// 而其中最需要测的两条路径 ——
//   · 主地址探活失败 → **回落备用地址**（老实现在 `connect()` 里直接 new ServerClient，
//     测不了；`test/server_endpoint_test.dart` 的注释里记着这个遗憾）
//   · SSE 事件流 → reducer → 界面状态
// —— 都要求真的有人跟它说话。所以这里在 loopback 上起一个按剧本应答的假服务端，
// 并通过 `ServerStore(clientFactory:)` 这个注入点接进去（生产路径不受影响）。
//
// 两个写测试时才弄清的实现细节（都记在下面注释里）：
//   1. flutter_test 会把 HttpClient 换成「一律返回 400」的 mock，要真连必须先还原；
//   2. `openSession()` **只订阅事件流、不主动拉快照** —— 会话内容靠 `event: snapshot` 帧推来。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/server_client.dart';
import 'package:pi_yz/server/server_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回一个 JSON 响应。必须用 `add(utf8.encode(...))`：`write()` 按 latin1 编码，
/// 中文会直接抛「Contains invalid characters」。
Future<void> reply(HttpRequest req, int status, String body) async {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..add(utf8.encode(body));
  await req.response.close();
}

/// 开一条 SSE 连接并推若干帧。
///
/// 推完就 close（真实服务端会一直开着，但测试里关掉更可控）：不 close 的话
/// `response` 对象在 handler 返回后没人引用，连接可能被提前回收 —— 实测就报过
/// 「Connection closed while receiving data」。真正常驻的长连接由真机验证覆盖。
Future<void> sse(HttpRequest req, List<String> frames) async {
  req.response
    ..statusCode = 200
    ..headers.contentType = ContentType('text', 'event-stream')
    ..headers.set('cache-control', 'no-cache');
  for (final f in frames) {
    req.response.add(utf8.encode(f));
  }
  await req.response.flush();
  await req.response.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late int port;
  final hits = <String>[];

  /// flutter_test 在 binding 初始化时会把 `HttpClient` 换成一个「一律返回 400 空响应」的
  /// mock（上面那句 `ensureInitialized()` 就是触发点）。这里要真连 loopback，
  /// 所以先还原，用例结束再装回去。
  HttpOverrides? savedOverrides;

  /// 单个用例可以替换它来改写某个路径的响应
  Future<void> Function(HttpRequest)? custom;

  /// 事件流要推哪些帧。默认只推一帧快照 —— 因为 `openSession` 只订阅事件流、
  /// 不主动拉快照，会话内容全靠这里进来。
  late List<String> sseFrames;

  const healthJson = '{"ok":true,"piVersion":"1.0.4","activeSessions":1}';
  const sessionsJson =
      '{"sessions":[{"id":"s1","cwd":"C:/x","preview":"hi","messageCount":2}]}';
  String snapshotJson({String id = 's1'}) =>
      '{"sessionId":"$id","cwd":"C:/x","thinkingLevel":"medium",'
      '"isStreaming":false,"autoCompactionEnabled":true,'
      '"messages":[{"role":"user","content":"快照里的第一条"}]}';

  /// 默认剧本
  Future<void> answer(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/api/health') {
      return reply(req, 200, healthJson);
    }
    if (path == '/api/sessions') {
      return reply(req, 200, sessionsJson);
    }
    if (RegExp(r'^/api/sessions/[^/]+/events$').hasMatch(path)) {
      return sse(req, sseFrames);
    }
    if (RegExp(r'^/api/sessions/[^/]+/turn-summary$').hasMatch(path)) {
      // 真实服务端对「还没落盘的空会话」就是 404
      return reply(req, 404, '{"error":"session not found"}');
    }
    if (RegExp(r'^/api/sessions/[^/]+$').hasMatch(path)) {
      return reply(req, 200, snapshotJson());
    }
    return reply(req, 404, '{"error":"no such endpoint"}');
  }

  setUp(() async {
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'app_lang': 'zh'});
    hits.clear();
    custom = null;
    sseFrames = ['event: snapshot\ndata: ${snapshotJson()}\n\n'];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((req) async {
      hits.add('${req.method} ${req.uri.path}');
      // custom 的优先级判断放在这一层：写进 answer() 会自己递归调用自己
      if (custom != null) return custom!(req);
      await answer(req);
    });
  });

  tearDown(() async {
    await server.close(force: true);
    HttpOverrides.global = savedOverrides;
  });

  /// 所有候选都指向假服务端
  ServerStore makeStore() => ServerStore(
    clientFactory: (_) =>
        ServerClient(host: '127.0.0.1', port: port, token: 'test-token'),
  );

  Future<void> connectStore(ServerStore store) => store.connect(
    ServerTarget(host: '127.0.0.1', port: port, token: 'test-token'),
  );

  group('连接状态机', () {
    test('connect 成功：状态变已连接、拿到 health、会话列表也拉回来了', () async {
      final store = makeStore();
      await connectStore(store);

      expect(
        store.state,
        ServerConnectionState.connected,
        reason: '连接失败原因：${store.errorMessage}',
      );
      expect(store.errorMessage, isNull);
      expect(store.health?.piVersion, '1.0.4');
      expect(store.sessions.length, 1);
      expect(store.sessions.single.id, 's1');
      expect(hits, containsAll(['GET /api/health', 'GET /api/sessions']));

      await store.disconnect();
      store.dispose();
    });

    test('探活失败：状态变 error 并留下人话（不是静默失败）', () async {
      custom = (req) async {
        if (req.uri.path == '/api/health') {
          return reply(req, 500, 'boom');
        }
        return answer(req);
      };
      final store = makeStore();
      await connectStore(store);

      expect(store.state, ServerConnectionState.error);
      expect(store.errorMessage, isNotNull);
      expect(store.errorMessage, isNotEmpty);

      await store.disconnect();
      store.dispose();
    });

    test('回落：主地址探不通时自动落到备用地址，并如实标出 isFallback', () async {
      // 主地址给一个没人监听的端口，备用给真服务端
      final deadPort = port + 1;
      final store = ServerStore(
        clientFactory: (endpoint) => ServerClient(
          host: '127.0.0.1',
          port: endpoint.isFallback ? port : deadPort,
          token: 'test-token',
        ),
      );

      await store.connect(
        ServerTarget(
          host: '127.0.0.1',
          port: deadPort,
          token: 'test-token',
          fallbackHost: '127.0.0.1',
          fallbackPort: port,
        ),
      );

      expect(
        store.state,
        ServerConnectionState.connected,
        reason: '连接失败原因：${store.errorMessage}',
      );
      expect(store.activeEndpoint, isNotNull);
      expect(
        store.activeEndpoint!.isFallback,
        isTrue,
        reason: '走的是备用地址，界面必须能如实标出来（否则用户不知道现在走局域网还是 VPN）',
      );

      await store.disconnect();
      store.dispose();
    });

    test('disconnect：回到未连接，且清掉已连接时的数据', () async {
      final store = makeStore();
      await connectStore(store);
      expect(
        store.state,
        ServerConnectionState.connected,
        reason: '连接失败原因：${store.errorMessage}',
      );

      await store.disconnect();
      expect(store.state, ServerConnectionState.disconnected);
      expect(store.health, isNull);
      expect(store.sessions, isEmpty);
      store.dispose();
    });
  });

  group('会话载入与事件流', () {
    test('openSession：事件流推来的快照会灌进 reducer', () async {
      final store = makeStore();
      await connectStore(store);

      await store.openSession('s1');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(store.currentSessionId, 's1');
      expect(
        store.chat.messages,
        isNotEmpty,
        reason: '快照没进来：openSession 靠事件流的 snapshot 帧，不是 HTTP 拉取',
      );
      expect(store.chat.messages.first.text, contains('快照里的第一条'));
      expect(store.chat.cwd, 'C:/x');

      await store.disconnect();
      store.dispose();
    });

    test('SSE 事件到达后会被归约进 chat（服务端推 message_start）', () async {
      sseFrames = [
        'event: snapshot\ndata: ${snapshotJson()}\n\n',
        'data: ${jsonEncode({
          'type': 'message_start',
          'message': {'role': 'user', 'content': '来自事件流'},
        })}\n\n',
      ];

      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        store.chat.messages.any((m) => m.text.contains('来自事件流')),
        isTrue,
        reason: 'SSE 解析或归约断了：事件没进到 chat 状态里',
      );

      await store.disconnect();
      store.dispose();
    });

    test('turn-summary 的 404（空会话还没落盘）不该让状态变脏', () async {
      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      await store.loadTurnSummary();

      expect(store.turnSummary, isNull);
      expect(store.state, ServerConnectionState.connected);
      expect(store.errorMessage, isNull);

      await store.disconnect();
      store.dispose();
    });

    test('loadSessions 在服务端报错时：给出错误态而不是抛到界面', () async {
      custom = (req) async {
        if (req.uri.path == '/api/sessions') {
          return reply(req, 500, 'boom');
        }
        return answer(req);
      };
      final store = makeStore();
      await connectStore(store);

      await store.loadSessions(refresh: true);

      expect(store.sessionsError, isNotNull);
      expect(store.loadingSessions, isFalse);
      expect(store.sessions, isEmpty);

      await store.disconnect();
      store.dispose();
    });
  });
}
