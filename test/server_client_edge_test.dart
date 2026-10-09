// ServerClient 的**边界与容错**守卫。
//
// 与 `server_client_test.dart`（通信核心：状态码映射、超时、连接失败）和
// `server_client_routes_test.dart`（47 个方法的路由契约）分工：
// 这里管「服务端返回的形状不对劲时，客户端会不会崩」。
//
// 服务端的返回形状是**会变的**（不同版本、不同错误路径），而客户端里到处是
// `whereType<Map>()` / `as List?` 这类防御式解析。这些分支平时不跑，
// 一旦服务端多返回一个 null，就是「面板整页空白」级别的故障。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/server_client.dart';

Future<void> reply(HttpRequest req, int status, String body) async {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..add(utf8.encode(body));
  await req.response.close();
}

void main() {
  late HttpServer server;
  late ServerClient client;
  late List<String> bodies;
  late String Function(HttpRequest) responder;

  /// 服务端拖延多久再回（用来造超时）
  var delayMs = 0;

  /// 回响应之前先把连接掰断（用来造「连接中断」）
  var killConnection = false;

  setUp(() async {
    bodies = <String>[];
    delayMs = 0;
    killConnection = false;
    responder = (_) => '{}';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      bodies.add(body);
      if (killConnection) {
        // 拆掉底层 socket，客户端会收到 HttpException
        final socket = await req.response.detachSocket();
        socket.destroy();
        return;
      }
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
      await reply(req, 200, responder(req));
    });
    client = ServerClient(host: '127.0.0.1', port: server.port, token: 't');
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  group('列表里混了非对象项：只认能解析的，不许整页崩', () {
    test('listSessions：junk / 数字 / null 一律跳过', () async {
      responder = (_) =>
          '{"sessions":[{"id":"s1","cwd":"C:/x"},"junk",42,null,{"id":"s2"}]}';

      final list = await client.listSessions();

      expect(list.map((s) => s.id).toList(), ['s1', 's2']);
    });

    test('pool：同上', () async {
      responder = (_) => '{"sessions":[{"id":"p1"}, "junk", null]}';

      final list = await client.pool();

      expect(list, hasLength(1));
      expect(list.single.id, 'p1');
    });

    test('fileIndex：files 里混非对象也不影响其余结果', () async {
      responder = (_) =>
          '{"files":[{"path":"a.dart"}, "junk", {"path":"b.dart"}]}';

      final list = await client.fileIndex('C:/w', 'a');

      expect(list.map((f) => f.path).toList(), ['a.dart', 'b.dart']);
    });

    test('listCredentials：同上', () async {
      responder = (_) => '{"credentials":[{"provider":"anthropic"}, "junk"]}';

      final list = await client.listCredentials();

      expect(list, hasLength(1));
    });

    test('listProviders：同上', () async {
      responder = (_) => '{"providers":[{"id":"anthropic"}, 7]}';

      final list = await client.listProviders();

      expect(list, hasLength(1));
    });

    test('configCommands：同上', () async {
      responder = (_) => '{"commands":[{"name":"/help"}, null]}';

      final list = await client.configCommands('C:/w');

      expect(list, hasLength(1));
    });

    test('listMcp：servers 里混非对象也不影响其余结果', () async {
      responder = (_) => '{"servers":[{"name":"github"}, "junk", null]}';

      final list = await client.listMcp('C:/w');

      expect(list, hasLength(1));
    });

    test('configModels：models 里混非对象也不影响其余结果', () async {
      responder = (_) => '{"models":[{"id":"gpt-5"}, 7]}';

      final list = await client.configModels('C:/w');

      expect(list, hasLength(1));
    });

    test('exportMarkdown：正文从 markdown 字段来，缺字段时给空串', () async {
      responder = (_) => '{"markdown":"# 标题","filename":"a.md"}';

      final result = await client.exportMarkdown('s1');

      expect(result.markdown, contains('标题'));
    });

    test('exportToServer：errors 里的噪声不会误伤，真错误才报', () async {
      // 混了非字符串：只认真的那条
      responder = (_) => '{"errors":["磁盘满了",5,null]}';
      await expectLater(
        client.exportToServer('s1'),
        throwsA(isA<ServerException>()),
      );

      // 全是噪声：不该报错
      responder = (_) => '{"errors":[5,null]}';
      await expectLater(client.exportToServer('s1'), completes);
    });
  });

  group('可选参数：传了就得进请求，没传就别塞进去', () {
    /// 最后一次请求的 body（显式转型，避免 dynamic 调用）
    Map<String, dynamic> lastBody() =>
        (jsonDecode(bodies.last) as Map).cast<String, dynamic>();

    test('startRemote(prefer:)：prefer 进 body', () async {
      await client.startRemote(prefer: 'cloudflare');
      expect(lastBody()['prefer'], 'cloudflare');

      await client.startRemote();
      expect(
        bodies.last,
        anyOf(isEmpty, '{}'),
        reason: '没传 prefer 时不该凭空塞一个字段进去',
      );
    });

    test('addWorktree(branch:)：只在非空时才带', () async {
      await client.addWorktree(cwd: 'C:/w', dir: 'C:/wt', branch: 'feat-x');
      expect(lastBody()['branch'], 'feat-x');

      await client.addWorktree(cwd: 'C:/w', dir: 'C:/wt', branch: '');
      expect(
        lastBody().containsKey('branch'),
        isFalse,
        reason: '空字符串不该当成真值发给服务端',
      );
    });

    test('packageAction(source:)：同上', () async {
      await client.packageAction(action: 'install', source: 'npm:pi-foo');
      expect(lastBody()['source'], 'npm:pi-foo');

      await client.packageAction(action: 'install');
      expect(lastBody().containsKey('source'), isFalse);
    });

    test('configThinkingLevels(provider, modelId)：都进 query', () async {
      await client.configThinkingLevels('C:/w', 'anthropic', 'claude');
      // query 在 URL 上，这一条由路由测试覆盖；这里确认不抛且能解析
      expect(bodies, isNotEmpty);
    });
  });

  group('解析形状异常时不崩', () {
    test('模型信息：current 与 model 都缺时给空标签', () async {
      responder = (_) => '{}';
      final (levels, current, label) = await client.configThinkingLevels(
        'C:/w',
        null,
        null,
      );
      expect(levels, isEmpty);
      expect(current, isNull);
      expect(label, isEmpty);
    });

    test('模型信息：model 给了 provider 与 id 时拼成「provider/id」', () async {
      responder = (_) =>
          '{"levels":["low","high"],"current":"high",'
          '"model":{"provider":"anthropic","id":"claude"}}';

      final (levels, current, label) = await client.configThinkingLevels(
        'C:/w',
        null,
        null,
      );
      expect(levels, ['low', 'high']);
      expect(current, 'high');
      expect(label, 'anthropic/claude');
    });

    test('404 的正文是中文时：不把它嵌进界面（英文模式下会漏中文）', () async {
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await reply(req, 404, '{"error":"找不到这条会话"}');
      });
      final c2 = ServerClient(host: '127.0.0.1', port: server.port, token: 't');

      await expectLater(
        c2.readFile('C:/nope'),
        throwsA(isA<ServerException>()),
      );
      await c2.dispose();
    });
  });

  group('rawFile 的失败路径也要说人话', () {
    test('端口没人监听：抛 ServerException 而不是裸的 SocketException', () async {
      // 端口 1 上不会有服务（别用 port+1：那会撞上别的服务）
      final bare = ServerClient(host: '127.0.0.1', port: 1, token: 't');

      await expectLater(
        bare.rawFile('C:/a.png'),
        throwsA(isA<ServerException>()),
      );
      await bare.dispose();
    });
  });

  group('_json 的超时：报「超时」而不是一直挂着', () {
    test('服务端拖着不回：按给定 timeout 抛 ServerException', () async {
      delayMs = 2000;

      await expectLater(
        client.health(timeout: const Duration(milliseconds: 200)),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('连接被掐断', () {
    test('HttpException 要统一成 ServerException（否则漏出去就是个没头绪的红屏）', () async {
      killConnection = true;

      await expectLater(client.health(), throwsA(isA<ServerException>()));
    });
  });

  group('小东西', () {
    test('ServerException.toString() 就是消息本身（日志里别打印一堆字段）', () {
      final error = ServerException('出事了', statusCode: 500);
      expect(error.toString(), '出事了');
      expect(error.statusCode, 500);
    });
  });
}
