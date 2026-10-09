// ServerStore 的**动作层**守卫：发消息 / 翻历史 / 改名 / 回应扩展对话框 / 事件流出错。
//
// 为什么单开一个文件：`server_store_test.dart` 管连接状态机与事件流，已经不短；
// 这批管的是「用户点下去会发生什么」。
//
// 挑的都是**行为契约**，不是复述实现。比如「空态直接发消息要自动把会话开出来」
// 这条背后是用户报过的「打完字点发送，什么也没发生」—— 断言写的是
// 「先 POST /api/sessions，再 POST command」这个**请求顺序**，而不是某个内部字段。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/app_prefs.dart';
import 'package:pi_yz/server/server_client.dart';
import 'package:pi_yz/server/server_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> reply(HttpRequest req, int status, String body) async {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..add(utf8.encode(body)); // 必须 UTF-8：write() 按 latin1，中文会抛
  await req.response.close();
}

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

const healthJson = '{"ok":true,"piVersion":"1.0.4","activeSessions":1}';
const sessionsJson =
    '{"sessions":[{"id":"s1","cwd":"C:/x","preview":"hi","messageCount":2}]}';

String snapshotJson({String id = 's1'}) =>
    '{"sessionId":"$id","cwd":"C:/x","isStreaming":false,"messages":[]}';

/// 一条成功的命令响应（服务端对 /api/sessions/:id/command 的正常回法）
String commandOk({Map<String, dynamic>? data}) => jsonEncode({
  'command': 'prompt',
  'success': true,
  'id': 'c1',
  'data': data ?? <String, dynamic>{},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late int port;
  final hits = <String>[];
  final bodies = <String, String>{};
  Future<void> Function(HttpRequest)? custom;
  late List<String> sseFrames;

  Future<void> answer(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/api/health') return reply(req, 200, healthJson);
    if (path == '/api/sessions' && req.method == 'GET') {
      return reply(req, 200, sessionsJson);
    }
    if (path == '/api/sessions' && req.method == 'POST') {
      return reply(req, 200, '{"sessionId":"s-new"}');
    }
    if (RegExp(r'^/api/sessions/[^/]+/events$').hasMatch(path)) {
      return sse(req, sseFrames);
    }
    if (RegExp(r'^/api/sessions/[^/]+/command$').hasMatch(path)) {
      return reply(req, 200, commandOk());
    }
    if (path.startsWith('/api/')) return reply(req, 200, '{}');
    return reply(req, 404, '{"error":"no such endpoint"}');
  }

  setUp(() async {
    hits.clear();
    bodies.clear();
    custom = null;
    sseFrames = ['event: snapshot\ndata: ${snapshotJson()}\n\n'];
    HttpOverrides.global = null; // flutter_test 会把 HttpClient 换成「一律 400」
    SharedPreferences.setMockInitialValues({'app_lang': 'zh'});
    // AppPrefs 是内存单例：不清掉「已读过」标志的话，上个用例留下的
    // lastSessionId 会被 connect() 拿去恢复会话（见 debugForgetLoaded 的注释）。
    AppPrefs.instance.debugForgetLoaded();
    await AppPrefs.instance.load();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((req) async {
      hits.add('${req.method} ${req.uri.path}');
      final body = await utf8.decoder.bind(req).join();
      if (body.isNotEmpty) bodies['${req.method} ${req.uri.path}'] = body;
      if (custom != null) return custom!(req);
      await answer(req);
    });
  });

  tearDown(() async {
    await server.close(force: true);
    HttpOverrides.global = null;
  });

  ServerStore makeStore() => ServerStore(
    clientFactory: (_) =>
        ServerClient(host: '127.0.0.1', port: port, token: 'test-token'),
  );

  Future<void> connectStore(ServerStore store, {String? defaultCwd}) =>
      store.connect(
        ServerTarget(
          host: '127.0.0.1',
          port: port,
          token: 'test-token',
          defaultCwd: defaultCwd,
        ),
      );

  /// 收尾：等 fire-and-forget 落地再断线（见 server_store_test.dart 的说明）
  Future<void> settleThenDisconnect(ServerStore store) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await store.disconnect();
    store.dispose();
  }

  Map<String, dynamic> commandBody(String path) =>
      jsonDecode(bodies[path]!) as Map<String, dynamic>;

  group('发消息：空态 / 带图 / 内置命令', () {
    test('空白文本又没图：返回 false，一个请求都不发', () async {
      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');
      hits.clear();

      expect(await store.sendPrompt('   '), isFalse);
      expect(hits, isEmpty, reason: '空白消息不该去打扰服务端');

      await settleThenDisconnect(store);
    });

    test('有会话：发 prompt 命令，正文是 trim 过的', () async {
      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      expect(await store.sendPrompt('  你好  '), isTrue);

      final body = commandBody('POST /api/sessions/s1/command');
      expect(body['type'], 'prompt');
      expect(body['message'], '你好', reason: '首尾空白要去掉');
      expect(body['id'], isNotEmpty, reason: '每条指令要有自己的 id，服务端靠它回执');

      await settleThenDisconnect(store);
    });

    test('只有图没有文字：允许发（拍照问一句是常见用法）', () async {
      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      expect(
        await store.sendPrompt(
          '',
          images: [
            {'type': 'image', 'data': 'AA==', 'mimeType': 'image/png'},
          ],
        ),
        isTrue,
      );

      final body = commandBody('POST /api/sessions/s1/command');
      expect(body['images'], hasLength(1));
      expect(body['message'], '');

      await settleThenDisconnect(store);
    });

    test('没有会话时自动把会话开出来再发（用户报过「打完字点发送没反应」）', () async {
      // 服务端一条会话都没有 —— 这样 connect 之后才是真的「无会话可用」
      // （有会话的话 store 会自动选中第一个，前提就造不出来了）
      custom = (req) async {
        if (req.uri.path == '/api/sessions' && req.method == 'GET') {
          return reply(req, 200, '{"sessions":[]}');
        }
        return answer(req);
      };

      final store = makeStore();
      await connectStore(store, defaultCwd: 'C:/work');
      expect(store.currentSessionId, isNull, reason: '前提：还没开会话');
      hits.clear();

      expect(await store.sendPrompt('第一条消息'), isTrue);

      expect(
        hits.first,
        'POST /api/sessions',
        reason: '**必须先建会话** —— 否则 runCommand 没有 sessionId，消息静默丢失',
      );
      expect(hits, contains('POST /api/sessions/s-new/command'));

      await settleThenDisconnect(store);
    });

    test('没有会话、也没有默认工作区：返回 false 并给出人话（不许静默失败）', () async {
      custom = (req) async {
        if (req.uri.path == '/api/sessions' && req.method == 'GET') {
          return reply(req, 200, '{"sessions":[]}');
        }
        return answer(req);
      };

      final store = makeStore();
      await connectStore(store); // 不带 defaultCwd，AppPrefs 里也没有

      expect(await store.sendPrompt('你好'), isFalse);
      expect(store.lastError, isNotNull, reason: '要告诉用户「先设个工作区」');
      expect(
        hits.any((h) => h.endsWith('/command')),
        isFalse,
        reason: '连会话都开不出来，就别去发指令了',
      );

      await settleThenDisconnect(store);
    });

    test('内置命令被服务端拦截：结果交给界面层，仍算「已接受」', () async {
      custom = (req) async {
        if (req.uri.path.endsWith('/command')) {
          return reply(
            req,
            200,
            commandOk(
              data: {
                'builtin': {'text': '斜杠命令的结果'},
              },
            ),
          );
        }
        return answer(req);
      };

      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      Map<String, dynamic>? got;
      store.onBuiltinResult = (builtin) => got = builtin;

      expect(await store.sendPrompt('/help'), isTrue);
      expect(got?['text'], '斜杠命令的结果', reason: '内置命令的结果不是模型回答，要交给界面层展示');

      await settleThenDisconnect(store);
    });

    test('命令被服务端拒绝（success=false）：如实返回 false', () async {
      custom = (req) async {
        if (req.uri.path.endsWith('/command')) {
          return reply(
            req,
            200,
            '{"command":"prompt","success":false,"error":"被拒绝"}',
          );
        }
        return answer(req);
      };

      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      expect(await store.sendPrompt('你好'), isFalse);

      await settleThenDisconnect(store);
    });
  });

  group('翻历史：不该发请求的时候一个都不发', () {
    test('没有更多历史时返回 false', () async {
      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');
      hits.clear();

      expect(await store.loadMoreHistory(), isFalse);
      expect(hits, isEmpty, reason: '已经到头了就别再去问服务端');
      expect(store.loadingHistory, isFalse);

      await settleThenDisconnect(store);
    });
  });

  group('重命名会话', () {
    test('空名字：返回 false 并给提示，不发请求', () async {
      final store = makeStore();
      await connectStore(store);
      hits.clear();

      expect(await store.renameSession('s1', '   '), isFalse);
      expect(store.lastError, isNotNull);
      expect(hits, isEmpty, reason: '空名字不该发出去 —— 服务端也改不了');

      await settleThenDisconnect(store);
    });

    test('正常改名：发出 rename_session，名字 trim 过', () async {
      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      expect(await store.renameSession('s1', '  新名字  '), isTrue);

      final body = commandBody('POST /api/sessions/s1/command');
      expect(body['type'], 'rename_session');
      expect(body['sessionId'], 's1');
      expect(body['name'], '新名字');

      await settleThenDisconnect(store);
    });

    test('服务端拒绝：返回 false，lastError 用服务端给的原因', () async {
      custom = (req) async {
        if (req.uri.path.endsWith('/command')) {
          return reply(
            req,
            200,
            '{"command":"rename_session","success":false,"error":"名字太长"}',
          );
        }
        return answer(req);
      };

      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      expect(await store.renameSession('s1', '很长的名字'), isFalse);
      expect(store.lastError, '名字太长');

      await settleThenDisconnect(store);
    });
  });

  group('扩展弹层：回应与移除', () {
    test('回应之后这条请求要从待办里消失（乐观移除）', () async {
      sseFrames = [
        'event: snapshot\ndata: ${snapshotJson()}\n\n',
        'data: ${jsonEncode({'type': 'extension_ui_request', 'id': 'r1', 'method': 'confirm', 'title': '要跑 deploy 吗？'})}\n\n',
      ];

      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        store.uiRequests.map((r) => r.id),
        contains('r1'),
        reason: '前提：请求确实进来了',
      );

      await store.respondUi('r1', {'answer': true});

      expect(
        store.uiRequests.any((r) => r.id == 'r1'),
        isFalse,
        reason: '回应过就从待办里拿掉，否则界面会一直挂着这个弹层',
      );

      await settleThenDisconnect(store);
    });

    test('回应时服务端报错：弹层已经关了，不抛异常，只提示', () async {
      custom = (req) async {
        if (req.uri.path.endsWith('/ui-response')) {
          return reply(req, 500, '{"error":"会话已经关了"}');
        }
        return answer(req);
      };

      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      String? toast;
      store.onToast = (text, {type}) => toast = text;

      await expectLater(
        store.respondUi('r-unknown', {'answer': true}),
        completes,
      );
      expect(toast, isNotNull, reason: '失败了要说话，不能静默');

      await settleThenDisconnect(store);
    });
  });

  group('扩展发来的通知与状态', () {
    test('method=notify：冒泡成界面提示（带类型）', () async {
      sseFrames = [
        'event: snapshot\ndata: ${snapshotJson()}\n\n',
        'data: ${jsonEncode({'type': 'extension_ui_request', 'id': 'n1', 'method': 'notify', 'message': '扩展提示了一句话', 'notifyType': 'error'})}\n\n',
      ];

      final store = makeStore();
      String? toast;
      String? toastType;
      store.onToast = (text, {type}) {
        toast = text;
        toastType = type;
      };

      await connectStore(store);
      await store.openSession('s1');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(toast, '扩展提示了一句话');
      expect(toastType, 'error', reason: 'notifyType 要透传给界面，不然红/黄分不出来');

      await settleThenDisconnect(store);
    });

    test('method=setStatus：写进 extensionStatus；空文本则清掉这一项', () async {
      sseFrames = [
        'event: snapshot\ndata: ${snapshotJson()}\n\n',
        'data: ${jsonEncode({'type': 'extension_ui_request', 'id': 'st1', 'method': 'setStatus', 'statusKey': 'build', 'statusText': '正在构建…'})}\n\n',
      ];

      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(store.extensionStatus['build'], '正在构建…');

      await settleThenDisconnect(store);
    });

    test('method=notify 不会被塞进待办弹层（它不需要回应）', () async {
      sseFrames = [
        'event: snapshot\ndata: ${snapshotJson()}\n\n',
        'data: ${jsonEncode({'type': 'extension_ui_request', 'id': 'n2', 'method': 'notify', 'message': '只是通知'})}\n\n',
      ];

      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(store.uiRequests, isEmpty, reason: '通知类插进来会弹出一个永远等不到回应的对话框');

      await settleThenDisconnect(store);
    });
  });

  group('小 getter：界面直接用，不能抛', () {
    test('currentSessionTitle：没有会话时给空串而不是 null', () async {
      final store = makeStore();
      expect(store.currentSessionTitle, '');
      store.dispose();
    });

    test('runningPool：只挑出正在跑的那些', () async {
      final store = makeStore();
      expect(store.runningPool, isEmpty);
      store.dispose();
    });
  });

  // 这一批用**表驱动**：50 多个公开动作方法逐个调一遍。
  //
  // 为什么这么写：这些方法的结构高度一致（取 client → try → catch ServerException
  // → 给提示），一个方法一个用例性价比很低；但**完全不测**的话，任何一处漏了 catch
  // 都会把异常抛到界面上 —— 用户看到的就是「点了没反应」或红屏。
  //
  // 所以用两种服务端剧本各跑一遍：正常态覆盖主干，**「全部 500」专门覆盖 catch 分支**。
  group('动作方法：正常态与「服务端全 500」都不许抛', () {
    List<(String, Future<Object?> Function(ServerStore))> cases() => [
      ('loadPool', (s) => s.loadPool()),
      ('loadDisk', (s) => s.loadDisk()),
      ('loadRemote', (s) => s.loadRemote()),
      ('closeLiveSession', (s) => s.closeLiveSession('s1')),
      ('deleteSession', (s) => s.deleteSession('s1')),
      ('createSession', (s) => s.createSession('C:/w')),
      ('cloneSession', (s) => s.cloneSession()),
      ('fetchTree', (s) => s.fetchTree()),
      ('forkFromMessage', (s) => s.forkFromMessage('e1')),
      ('navigateTree', (s) => s.navigateTree('t1')),
      ('rawFile', (s) => s.rawFile('C:/a.png')),
      (
        'uploadFile',
        (s) => s.uploadFile(dir: 'C:/w', name: 'a.txt', bytes: [1, 2, 3]),
      ),
      ('worktrees', (s) => s.worktrees('C:/w')),
      ('addWorktree', (s) => s.addWorktree(cwd: 'C:/w', dir: 'C:/wt')),
      ('removeWorktree', (s) => s.removeWorktree('C:/w', 'C:/wt')),
      ('packages', (s) => s.packages()),
      ('runPackageAction', (s) => s.runPackageAction(action: 'install')),
      ('listFiles', (s) => s.listFiles()),
      ('readFile', (s) => s.readFile('C:/a.md')),
      ('gitStatus', (s) => s.gitStatus('C:/w')),
      ('gitDiff', (s) => s.gitDiff('C:/w')),
      ('fileRefs', (s) => s.fileRefs('chat')),
      (
        'saveMcpServer',
        (s) => s.saveMcpServer(name: 'x', scope: 'user', config: {}),
      ),
      ('removeMcpServer', (s) => s.removeMcpServer('x', scope: 'user')),
      (
        'setMcpServerEnabled',
        (s) => s.setMcpServerEnabled('x', scope: 'user', enabled: true),
      ),
      ('mcpServers', (s) => s.mcpServers()),
      ('providers', (s) => s.providers()),
      ('beginLogin', (s) => s.beginLogin('anthropic', 'oauth')),
      ('pollLogin', (s) => s.pollLogin('t1')),
      ('answerLogin', (s) => s.answerLogin('t1', 'yes')),
      ('cancelLogin', (s) => s.cancelLogin('t1')),
      ('logoutProvider', (s) => s.logoutProvider('anthropic')),
      ('credentials', (s) => s.credentials()),
      ('setApiKey', (s) => s.setApiKey('anthropic', 'sk-x')),
      ('removeApiKey', (s) => s.removeApiKey('anthropic')),
      ('sessionStats', (s) => s.sessionStats()),
      ('exportMarkdownText', (s) => s.exportMarkdownText()),
      ('exportFilesToServer', (s) => s.exportFilesToServer()),
      ('abort', (s) => s.abort()),
      ('compact', (s) => s.compact()),
      ('setModel', (s) => s.setModel('openai', 'gpt-5')),
    ];

    test('正常态：全部跑通，不抛异常', () async {
      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      for (final (name, call) in cases()) {
        try {
          await call(store);
        } catch (error) {
          fail('$name 抛了异常：$error');
        }
      }

      await settleThenDisconnect(store);
    });

    test('服务端全 500：全部自己吞掉，不抛到界面', () async {
      custom = (req) async {
        final path = req.uri.path;
        // 连接与事件流保持正常，其余一律 500 —— 这样才进得去各个 catch 分支
        if (path == '/api/health') return reply(req, 200, healthJson);
        if (path == '/api/sessions' && req.method == 'GET') {
          return reply(req, 200, sessionsJson);
        }
        if (RegExp(r'/events$').hasMatch(path)) return sse(req, sseFrames);
        return reply(req, 500, '{"error":"服务端炸了"}');
      };

      final store = makeStore();
      await connectStore(store);
      await store.openSession('s1');

      final failed = <String>[];
      for (final (name, call) in cases()) {
        try {
          await call(store);
        } catch (error) {
          failed.add('$name：$error');
        }
      }

      expect(
        failed,
        isEmpty,
        reason:
            '这些方法必须自己吞掉 ServerException —— 抛到界面就是「点了没反应」。'
            '第一个失败的：${failed.isEmpty ? "无" : failed.first}',
      );

      await settleThenDisconnect(store);
    });
  });
}
