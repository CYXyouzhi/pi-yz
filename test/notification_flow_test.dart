// 「什么时候发通知、内容对不对」的端到端守卫。
//
// 判定该不该提醒的纯函数已经测过一轮（notification_center_test.dart）。这里补的是
// 后者之外真正影响体验的部分：**三种结束情况各发什么**。用户在手机上看一眼通知就
// 得知道「要回去确认」还是「可以不用管」—— 发错比不发更糟。
//
// 驱动方式与真机一致：loopback 假服务端 → ServerStore → NotificationCenter.attach
// → 拦截原生通道，断言真的发了 `notify` 以及发了什么内容。
// 状态用 `event: snapshot`（可带 messages）与 `agent_start` / `agent_settled` 推。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/notification_center.dart';
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

/// 推若干 SSE 帧，推完关掉（真服务端会一直开着，测试里关掉更可控）
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

/// 一帧快照：`isStreaming` 决定「在跑/跑完」，messages 决定通知正文
String snapshot({
  required bool streaming,
  List<Map<String, dynamic>> messages = const [],
}) =>
    'event: snapshot\ndata: ${jsonEncode({'sessionId': 's1', 'cwd': 'C:/work/pi-yz', 'isStreaming': streaming, 'messages': messages})}\n\n';

/// 一帧普通事件（靠 data.type 归约）
String event(String type, [Map<String, dynamic> data = const {}]) =>
    'data: ${jsonEncode({'type': type, ...data})}\n\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late int port;
  late List<String> frames;

  /// 原生通道收到的通知（参数原样存下来）
  late List<Map<String, dynamic>> notified;

  const channel = MethodChannel('pi_yz/native');
  final center = NotificationCenter.instance;

  setUp(() async {
    frames = const [];
    notified = <Map<String, dynamic>>[];

    // 还原 HttpClient（flutter_test 会换成「一律 400」的 mock），并重置通知中心
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'app_lang': 'zh'});
    center.enabled = true;
    center.watchOnly = false;
    center.dndEnabled = false;
    center.quickReply = true;
    center.notifyOnDone = true;
    center.notifyOnError = true;
    center.notifyOnNeedInput = true;
    center.suppressed.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'permission':
              return true;
            case 'notify':
              notified.add((call.arguments as Map).cast<String, dynamic>());
              return true;
            default:
              return null;
          }
        });

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/api/health') {
        return reply(req, 200, '{"ok":true,"piVersion":"1.0.4"}');
      }
      if (path == '/api/sessions') {
        return reply(
          req,
          200,
          '{"sessions":[{"id":"s1","cwd":"C:/work/pi-yz","preview":"hi"}]}',
        );
      }
      if (RegExp(r'^/api/sessions/[^/]+/events$').hasMatch(path)) {
        return sse(req, frames);
      }
      if (path.startsWith('/api/')) return reply(req, 200, '{}');
      return reply(req, 404, '{"error":"no"}');
    });
  });

  tearDown(() async {
    center.detach();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    HttpOverrides.global = null;
    await server.close(force: true);
  });

  /// 按剧本连上并打开会话，然后等帧落地
  Future<ServerStore> runOnce() async {
    final store = ServerStore(
      clientFactory: (_) =>
          ServerClient(host: '127.0.0.1', port: port, token: 't'),
    );
    await store.connect(
      ServerTarget(host: '127.0.0.1', port: port, token: 't'),
    );
    center.attach(store);
    await store.openSession('s1');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return store;
  }

  group('⑪ 三种结束情况各发什么', () {
    test('正常跑完 → 发「完成」通知，正文是最后一条消息', () async {
      frames = [
        snapshot(streaming: true),
        snapshot(
          streaming: false,
          messages: [
            {'role': 'assistant', 'content': '重构做完了，18 个测试全过'},
          ],
        ),
      ];

      final store = await runOnce();

      expect(notified, hasLength(1), reason: '跑完应当刚好发一条通知');
      final body = notified.single['body'] as String;
      expect(body, contains('重构做完了'));
      expect(center.lastNotifiedTitle, isNotEmpty, reason: '标题要能让人认出是哪个会话');
      await store.disconnect();
      store.dispose();
    });

    test('出错了 → 通知内容指向错误本身（不是同一句「跑完了」）', () async {
      // 先跑一次「正常」拿到基准标题，再比对着看错误情况的差异
      frames = [
        snapshot(streaming: true),
        snapshot(
          streaming: false,
          messages: [
            {'role': 'assistant', 'content': '正常结束', 'isError': false},
          ],
        ),
      ];
      var store = await runOnce();
      final doneTitle = center.lastNotifiedTitle;
      await store.disconnect();
      store.dispose();

      notified = <Map<String, dynamic>>[];
      frames = [
        snapshot(streaming: true),
        snapshot(
          streaming: false,
          messages: [
            {'role': 'assistant', 'content': '命令执行失败：端口被占用', 'isError': true},
          ],
        ),
      ];
      store = await runOnce();

      expect(notified, hasLength(1));
      expect(notified.single['body'], contains('端口被占用'));
      expect(
        center.lastNotifiedTitle,
        isNot(doneTitle),
        reason: '出错和跑完的标题必须不一样，否则用户分不清该不该回去看',
      );
      await store.disconnect();
      store.dispose();
    });

    test('有等待确认的请求 → 通知正文是那个请求（哪怕已经跑完）', () async {
      frames = [
        event('agent_start'),
        event('extension_ui_request', {
          'id': 'r1',
          'method': 'confirm',
          'title': '要跑 deploy 吗？',
        }),
        event('agent_settled'),
      ];

      final store = await runOnce();

      expect(notified, isNotEmpty, reason: '有人在等确认，这是最该提醒的情况');
      expect(
        notified.last['body'],
        contains('要跑 deploy 吗'),
        reason: '正文要带上到底在问什么，不然用户还得切回去看',
      );
      await store.disconnect();
      store.dispose();
    });
  });

  group('⑫ 免打扰时段：压掉而不是丢掉', () {
    test('时段内不打扰，但记录「刚被压掉了什么」（设置页能看）', () async {
      final hour = DateTime.now().hour;
      center.dndEnabled = true;
      center.dndStartHour = hour;
      center.dndEndHour = (hour + 2) % 24; // 避开 start == end（那是「不分时段」）

      frames = [
        snapshot(streaming: true),
        snapshot(
          streaming: false,
          messages: [
            {'role': 'assistant', 'content': '夜里跑完了'},
          ],
        ),
      ];

      final store = await runOnce();

      expect(notified, isEmpty, reason: '免打扰时段内不该弹通知');
      expect(
        center.suppressed,
        isNotEmpty,
        reason: '压掉的通知要留痕，否则用户不知道「刚才其实有结果」',
      );
      // 留痕记的是「标题 + 原因」（正文不重复记：设置页那行地方小）
      expect(center.suppressed.first, contains('pi-yz'), reason: '要能看出是哪个会话');
      expect(
        center.suppressed.first,
        contains('免打扰'),
        reason: '还要说明为什么压 —— 否则用户会以为通知根本没生效',
      );
      await store.disconnect();
      store.dispose();
    });
  });
}
