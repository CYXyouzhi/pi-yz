// ServerClient 的通信层守卫。
//
// 做法：在 loopback 上真的起一个 HttpServer 当假服务端，让它按用例剧本回响应。
// 为什么不用 mock：`ServerClient` 直接持有 `dart:io` 的 HttpClient，没有注入点；
// 而 loopback 起服务器是零依赖的，测到的又是**真实代码路径**（URL 拼装、请求头、
// 状态码映射、超时），比 mock 更接近线上。
//
// 覆盖策略：40+ 个接口方法都是 `_json()` 的薄包装，所以这里只测通信核心的六类行为
// + 三个代表方法（health / 列表 / 命令），其余靠这条路径间接保障。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/server_client.dart';

void main() {
  late HttpServer server;
  late ServerClient client;
  final seen = <HttpRequest>[];

  /// 每个用例替换它来决定怎么回
  late Future<void> Function(HttpRequest) handler;

  setUp(() async {
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handler = (req) async {
      req.response
        ..statusCode = 200
        ..write('{}');
      await req.response.close();
    };
    server.listen((req) async {
      seen.add(req);
      await handler(req);
    });
    client = ServerClient(
      host: '127.0.0.1',
      port: server.port,
      token: 'test-token-48-chars',
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  Future<void> respond(
    HttpRequest req,
    int status,
    String body, {
    String contentType = 'application/json',
  }) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.parse(contentType)
      // 必须 add + utf8.encode：`write()` 按 latin1 编码，中文会直接抛
      // 「Contains invalid characters」
      ..add(utf8.encode(body));
    await req.response.close();
  }

  group('请求本身', () {
    test('带上 Bearer token，并且打到正确的路径', () async {
      handler = (req) => respond(req, 200, '{"ok":true}');
      await client.health();

      expect(seen.length, 1);
      expect(seen.single.uri.path, '/api/health');
      expect(
        seen.single.headers.value('authorization'),
        'Bearer test-token-48-chars',
      );
    });

    test('POST 带 JSON 体与 content-type', () async {
      handler = (req) async {
        final body = await utf8.decoder.bind(req).join();
        expect(req.method, 'POST');
        expect(req.headers.contentType?.mimeType, 'application/json');
        expect((jsonDecode(body) as Map)['message'], '你好');
        await respond(req, 200, '{"ok":true}');
      };
      await client.command('s1', {'message': '你好'});
      expect(seen.single.uri.path, '/api/sessions/s1/command');
    });

    test('query 参数会被拼进 URL（工作区路径这种含特殊字符的要编码）', () async {
      handler = (req) => respond(req, 200, '{"entries":[]}');
      await client.listFiles(path: 'C:/Users/YOUZHI/Desktop/1');
      expect(
        seen.single.uri.queryParameters['path'],
        'C:/Users/YOUZHI/Desktop/1',
      );
    });
  });

  group('状态码映射', () {
    test('200 正常解析成 Map', () async {
      handler = (req) => respond(req, 200, '{"piVersion":"1.0.4","ok":true}');
      final h = await client.health();
      expect(h.piVersion, '1.0.4');
      expect(h.ok, isTrue);
    });

    test('404 抛 ServerException 且带 statusCode', () async {
      handler = (req) => respond(req, 404, '{"error":"session not found"}');
      await expectLater(
        client.health(),
        throwsA(
          isA<ServerException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e.message,
                'message',
                contains('session not found'),
              ),
        ),
      );
    });

    test('401 抛异常，提示要指向 token（而不是笼统的「失败」）', () async {
      handler = (req) => respond(req, 401, '{"error":"unauthorized"}');
      await expectLater(
        client.health(),
        throwsA(
          isA<ServerException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('500 抛异常且文案里带状态码', () async {
      handler = (req) => respond(req, 500, 'boom');
      await expectLater(
        client.health(),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            contains('500'),
          ),
        ),
      );
    });

    test('服务端给中文错误正文：不把它嵌进界面（英文模式下会漏中文）', () async {
      handler = (req) => respond(req, 500, '{"error":"这条会话正在运行"}');
      await expectLater(
        client.health(),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            isNot(contains('这条会话正在运行')),
          ),
        ),
      );
    });

    test('空响应体：不抛，拿到默认值对象', () async {
      handler = (req) => respond(req, 200, '');
      final h = await client.health();
      // `_json` 对空正文返回空 Map，再交给 DTO 的默认值（piVersion 的兜底是 '?'）
      expect(h.piVersion, '?');
      expect(h.ok, isFalse);
    });
  });

  group('网络异常', () {
    test('端口没人监听：抛 ServerException 且给出人话', () async {
      final port = server.port; // 关掉之后 port 就取不到了，先记下
      await server.close(force: true);
      final dead = ServerClient(host: '127.0.0.1', port: port, token: 't');
      await expectLater(dead.health(), throwsA(isA<ServerException>()));
    });

    test('响应慢于超时：抛异常（不会一直挂着）', () async {
      handler = (req) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await respond(req, 200, '{}');
      };
      final quick = ServerClient(
        host: '127.0.0.1',
        port: server.port,
        token: 't',
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(quick.health(), throwsA(isA<ServerException>()));
    });
  });

  group('代表性子集（其余方法都走同一条 _json 路径）', () {
    test('listSessions：解析成 ServerSession 列表', () async {
      handler = (req) => respond(req, 200, '''
        {"sessions":[
          {"id":"s1","cwd":"C:/x","preview":"hi","messageCount":8},
          {"id":"s2","cwd":"C:/y","preview":"yo","messageCount":2}
        ]}''');
      final list = await client.listSessions();
      expect(list.length, 2);
      expect(list.first.id, 's1');
      expect(list.first.messageCount, 8);
    });

    test('listSessions：缺 sessions 键 → 空列表而不是抛', () async {
      handler = (req) => respond(req, 200, '{}');
      expect(await client.listSessions(), isEmpty);
    });

    test('command：把服务端返回的 ok=false 照实带回来（不当成成功）', () async {
      handler = (req) => respond(req, 200, '{"ok":false,"error":"命令不认"}');
      final r = await client.command('s1', {'command': '/nope'});
      expect(r.success, isFalse);
      expect(r.error, '命令不认');
    });

    test('readTurnSummary：404 时返回 null（调用方据此不显示这一条）', () async {
      handler = (req) => respond(req, 404, '{"error":"session not found"}');
      expect(await client.readTurnSummary('s1'), isNull);
    });

    test('readTurnSummary：其它错误照常抛（别把真问题吞掉）', () async {
      handler = (req) => respond(req, 500, 'boom');
      await expectLater(
        client.readTurnSummary('s1'),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
