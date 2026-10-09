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
    // 兜底：其余 /api/* 回一个「空但合法」的对象 —— 让 store 的各种 load*/命令方法
    // 都能跑完整条代码路径（DTO 都是容错的，空对象解析不会抛）
    if (path.startsWith('/api/')) {
      return reply(req, 200, '{}');
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

  /// 收尾：等一小会儿再断线。
  ///
  /// 有些方法内部是 fire-and-forget（命令发完顺手刷新列表、拉一次命令清单…），
  /// 方法 await 返回时请求还在飞；这时 disconnect() 会 `close(force: true)`，
  /// 把在途请求打断成 HttpException。
  Future<void> settleThenDisconnect(ServerStore store) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await store.disconnect();
    store.dispose();
  }

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

      await settleThenDisconnect(store);
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

      await settleThenDisconnect(store);
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

      await settleThenDisconnect(store);
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

      await settleThenDisconnect(store);
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

      await settleThenDisconnect(store);
    });

    test('turn-summary 的 404（空会话还没落盘）不该让状态变脏', () async {
      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      await store.loadTurnSummary();

      expect(store.turnSummary, isNull);
      expect(store.state, ServerConnectionState.connected);
      expect(store.errorMessage, isNull);

      await settleThenDisconnect(store);
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

      await settleThenDisconnect(store);
    });
  });

  group('其余加载与操作路径（冒烟：不抛、状态不脏）', () {
    test('loadPool / loadDisk：跑完就回到非加载态', () async {
      final store = makeStore();
      await connectStore(store);

      await store.loadPool();
      expect(store.pool, isEmpty);
      expect(store.remoteBusy, isFalse);

      await store.loadDisk();
      expect(store.loadingDisk, isFalse);
      expect(store.diskError, isNull);

      await settleThenDisconnect(store);
    });

    test(
      'loadUsageSummary / loadSessionUsage / loadTurnSummary：空响应也不抛',
      () async {
        final store = makeStore();
        await connectStore(store);
        await store.openSession('s1');

        await store.loadUsageSummary();
        await store.loadSessionUsage();
        await store.loadTurnSummary();

        expect(store.state, ServerConnectionState.connected);
        await store.disconnect();
        store.dispose();
      },
    );

    test('refreshCommandsIfNeeded：拉一次命令清单，失败也不改连接状态', () async {
      final store = makeStore();
      await connectStore(store);

      await store.refreshCommandsIfNeeded();

      expect(store.state, ServerConnectionState.connected);
      await settleThenDisconnect(store);
    });

    test('createSession：服务端给了 id 就走通', () async {
      custom = (req) async {
        if (req.method == 'POST' && req.uri.path == '/api/sessions') {
          return reply(req, 200, '{"id":"new-1"}');
        }
        return answer(req);
      };
      final store = makeStore();
      await connectStore(store);

      final id = await store.createSession('C:/x');
      expect(id, anyOf(isNull, 'new-1'));

      await settleThenDisconnect(store);
    });

    test(
      'deleteSession / archiveSession / unarchiveSession：不抛且连接状态不变',
      () async {
        final store = makeStore();
        await connectStore(store);

        await store.archiveSession('s1');
        await store.unarchiveSession('s1');
        await store.deleteSession('s1');

        expect(store.state, ServerConnectionState.connected);
        await store.disconnect();
        store.dispose();
      },
    );

    test(
      'setModel / setThinkingLevel / setSessionName / abort / compact：走命令通道不抛',
      () async {
        final store = makeStore();
        await connectStore(store);
        await store.openSession('s1');

        await store.setModel('kimi', 'kimi-k2');
        await store.setThinkingLevel('high');
        await store.setSessionName('新名字');
        await store.abort();
        await store.compact();

        expect(store.state, ServerConnectionState.connected);
        await store.disconnect();
        store.dispose();
      },
    );

    test('setApiKey / removeApiKey：返回 bool，不抛', () async {
      final store = makeStore();
      await connectStore(store);

      expect(await store.setApiKey('kimi', 'sk-test'), isA<bool>());
      expect(await store.removeApiKey('kimi'), isA<bool>());

      await settleThenDisconnect(store);
    });

    test('ensureConnected：已经连着就不再探活一次', () async {
      final store = makeStore();
      await connectStore(store);
      final before = hits.length;

      await store.ensureConnected();

      expect(hits.length, before, reason: '已连接时 ensureConnected 不该再发探活请求');
      await settleThenDisconnect(store);
    });

    test('exportMarkdownText / closeLiveSession / resumeSync：不抛', () async {
      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      await store.exportMarkdownText();
      await store.closeLiveSession('s1');
      await store.resumeSync();

      expect(store.state, ServerConnectionState.connected);
      await settleThenDisconnect(store);
    });

    test('loadSessions 之后 visible/archived 两个视图按归档标记分开', () async {
      final store = makeStore();
      await connectStore(store);
      expect(store.visibleSessions.length, store.sessions.length);

      await store.archiveSession('s1');
      expect(store.isArchived('s1'), isTrue);

      await store.unarchiveSession('s1');

      await settleThenDisconnect(store);
    });
  });

  // 「远程访问」是手机控服务端的入口（出门在外用蜂窝网连家里那台）：
  // 连上之后状态要能如实反映「正在起 / 已起来 / 起不来」。
  // 之前 startRemote / stopRemote / loadRemote 三整块都没覆盖。
  group('远程访问：状态机如实反映服务端的三种状态', () {
    test('loadRemote：拿到 running 与公网地址', () async {
      custom = (req) async {
        if (req.uri.path == '/api/remote') {
          return reply(
            req,
            200,
            '{"status":"up","running":true,"url":"https://x.trycloudflare.com",'
            '"provider":"cloudflare","threatModel":["链路加密"]}',
          );
        }
        return answer(req); // 其余路径回默认剧本（health / sessions …），否则连不上
      };

      final store = makeStore();
      await connectStore(store);
      await store.loadRemote();

      expect(store.remote.running, isTrue);
      expect(store.remote.url, 'https://x.trycloudflare.com');
      expect(store.remote.providerLabel, isNotEmpty);
      expect(store.remote.threatModel, contains('链路加密'));

      await settleThenDisconnect(store);
    });

    test('startRemote：从 starting 轮询到 running 后返回 true、忙碌位归位', () async {
      var polls = 0;
      custom = (req) async {
        if (req.uri.path == '/api/remote/start') {
          return reply(req, 200, '{"status":"starting","running":false}');
        }
        if (req.uri.path == '/api/remote') {
          polls += 1;
          // 第一次还是 starting，之后转 running —— 模拟真实的启动过程
          return reply(
            req,
            200,
            polls >= 2
                ? '{"status":"up","running":true,"url":"https://y.trycloudflare.com"}'
                : '{"status":"starting","running":false}',
          );
        }
        return answer(req); // 其余路径回默认剧本（health / sessions …），否则连不上
      };

      final store = makeStore();
      await connectStore(store);
      final ok = await store.startRemote();

      expect(ok, isTrue);
      expect(store.remote.running, isTrue);
      expect(store.remoteBusy, isFalse, reason: '起完必须把忙碌位放开，否则按钮一直转圈');

      await settleThenDisconnect(store);
    });

    test('startRemote 失败：返回 false，状态落到 error 并带上原因', () async {
      custom = (req) async {
        if (req.uri.path == '/api/remote/start') {
          return reply(req, 500, '{"error":"隧道起不来"}');
        }
        return answer(req); // 其余路径回默认剧本（health / sessions …），否则连不上
      };

      final store = makeStore();
      await connectStore(store);
      final ok = await store.startRemote();

      expect(ok, isFalse);
      expect(store.remoteBusy, isFalse, reason: '失败也要放开忙碌位，不然界面卡住');
      expect(
        store.remote.status == 'error' || store.lastError != null,
        isTrue,
        reason: '失败必须留下人话',
      );

      await settleThenDisconnect(store);
    });

    test('stopRemote：状态回到未运行、忙碌位归位', () async {
      custom = (req) async {
        if (req.uri.path == '/api/remote/stop') {
          return reply(req, 200, '{"status":"idle","running":false}');
        }
        return answer(req); // 其余路径回默认剧本（health / sessions …），否则连不上
      };

      final store = makeStore();
      await connectStore(store);
      await store.stopRemote();

      expect(store.remote.running, isFalse);
      expect(store.remoteBusy, isFalse);

      await settleThenDisconnect(store);
    });

    test('未连接时 startRemote 不该把忙碌位卡住（先 ensureConnected）', () async {
      final store = makeStore(); // 故意不 connect
      final ok = await store.startRemote();
      expect(ok, isFalse);
      expect(store.remoteBusy, isFalse);
      expect(store.lastError, isNotNull);
      store.dispose();
    });
  });

  // 「新会话默认模型」：只影响之后新建的会话，当前会话不变。
  group('默认模型读写', () {
    test('loadDefaultModel：读回 provider 与 modelId', () async {
      custom = (req) async {
        if (req.uri.path == '/api/config/default-model') {
          return reply(
            req,
            200,
            '{"provider":"anthropic","modelId":"claude-sonnet-4-5"}',
          );
        }
        return answer(req); // 其余路径回默认剧本（health / sessions …），否则连不上
      };

      final store = makeStore();
      await connectStore(store);
      await store.loadDefaultModel();

      expect(store.defaultModelProvider, 'anthropic');
      expect(store.defaultModelId, 'claude-sonnet-4-5');

      await settleThenDisconnect(store);
    });

    test('setDefaultModel 成功：本地状态跟着改，且真的 POST 了', () async {
      custom = (req) async {
        if (req.uri.path == '/api/config/default-model') {
          return reply(req, 200, '{"ok":true}');
        }
        return answer(req); // 其余路径回默认剧本（health / sessions …），否则连不上
      };

      final store = makeStore();
      await connectStore(store);
      final ok = await store.setDefaultModel('openai', 'gpt-5');

      expect(ok, isTrue);
      expect(store.defaultModelProvider, 'openai');
      expect(store.defaultModelId, 'gpt-5');
      expect(
        hits,
        contains('POST /api/config/default-model'),
        reason: '不能只改本地状态而不写回服务端',
      );

      await settleThenDisconnect(store);
    });

    test('setDefaultModel 失败：返回 false 且不改本地状态（回滚语义）', () async {
      custom = (req) async {
        if (req.uri.path == '/api/config/default-model') {
          return reply(req, 500, '{"error":"settings.json 只读"}');
        }
        return answer(req); // 其余路径回默认剧本（health / sessions …），否则连不上
      };

      final store = makeStore();
      await connectStore(store);
      final ok = await store.setDefaultModel('openai', 'gpt-5');

      expect(ok, isFalse);
      expect(
        store.defaultModelId,
        isNot('gpt-5'),
        reason: '写服务端失败就不能显示成已生效，否则用户以为切了其实没切',
      );
      expect(store.lastError, isNotNull);

      await settleThenDisconnect(store);
    });
  });

  // 草稿是「切走再回来，没发出去的话还在」的保障 —— 完全本地，不需要服务端。
  group('草稿', () {
    test('按会话分开存：切会话不会串（串了就会把别人的话发出去）', () {
      final store = makeStore();
      store.saveDraft('s1', '给 s1 的半句话');
      store.saveDraft('s2', '给 s2 的半句话');

      expect(store.draftFor('s1'), '给 s1 的半句话');
      expect(store.draftFor('s2'), '给 s2 的半句话');
      store.dispose();
    });

    test('存空串等于清掉这条草稿', () {
      final store = makeStore();
      store.saveDraft('s1', '写了一半');
      store.saveDraft('s1', '');
      expect(store.draftFor('s1'), isEmpty);
      store.dispose();
    });

    test('没有草稿的会话返回空串（不是 null，界面直接拿去填输入框）', () {
      final store = makeStore();
      expect(store.draftFor('never-touched'), isEmpty);
      expect(store.draftFor(null), isEmpty);
      store.dispose();
    });

    test('clearDrafts 报出清了条数，且之后都空了', () {
      final store = makeStore();
      store.saveDraft('s1', 'a');
      store.saveDraft('s2', 'b');

      expect(store.clearDrafts(), 2);
      expect(store.draftFor('s1'), isEmpty);
      expect(store.draftFor('s2'), isEmpty);
      store.dispose();
    });
  });
}
