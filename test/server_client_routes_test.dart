// ServerClient 40+ 个接口方法的「路由契约」守卫。
//
// 为什么这么测：这些方法几乎都是手写的 URL 拼装（`_json('POST', '/api/...')`），
// 路径或 HTTP 方法写错时**编译期完全看不出来**，在界面上表现为「面板打不开 /
// 点了没反应」。给每个方法单写一个用例维护成本太高，所以用表驱动：一次把所有
// 方法都调一遍，断言打在「假服务端实际收到的请求」上。
//
// 通信核心（状态码映射、连接失败、超时）在 server_client_test.dart 里，
// 这里只管「打没打对端点、参数有没有丢」。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/server_client.dart';

/// 一次被服务端收到的请求
class Hit {
  Hit(this.method, this.uri);
  final String method;
  final Uri uri;
  String body = '';
}

void main() {
  late HttpServer server;
  late ServerClient client;
  final hits = <Hit>[];

  /// 用例可以改它来决定回什么体 / 什么状态码
  var responseBody = '{}';
  var responseStatus = 200;

  /// 用例可以整体接管响应（rawFile / 超时这类要自定义的）
  Future<void> Function(HttpRequest)? custom;

  setUp(() async {
    hits.clear();
    responseBody = '{}';
    responseStatus = 200;
    custom = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final hit = Hit(req.method, req.uri);
      // body 必须在这里读完：handler 返回后这条请求流就没了
      hit.body = await utf8.decoder.bind(req).join();
      hits.add(hit);
      if (custom != null) return custom!(req);
      req.response
        ..statusCode = responseStatus
        ..headers.contentType = ContentType.json
        ..add(utf8.encode(responseBody));
      await req.response.close();
    });
    client = ServerClient(
      host: '127.0.0.1',
      port: server.port,
      token: 'test-token',
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  group('路由契约：方法 + 路径', () {
    test('全部接口方法都打在正确的端点', () async {
      final cases = <(String, Future<void> Function())>[
        ('GET /api/health', () => client.health()),
        ('GET /api/sessions', () => client.listSessions()),
        ('DELETE /api/sessions/s1', () => client.deleteSession('s1')),
        ('DELETE /api/pool/s1', () => client.closeLiveSession('s1')),
        ('GET /api/pool', () => client.pool()),
        ('GET /api/sessions/disk', () => client.diskUsage()),
        ('GET /api/remote', () => client.remoteState()),
        ('POST /api/remote/start', () => client.startRemote()),
        ('POST /api/remote/stop', () => client.stopRemote()),
        ('GET /api/files', () => client.listFiles()),
        ('GET /api/file', () => client.readFile('C:/a.md')),
        ('GET /api/file/raw', () => client.rawFile('C:/a.png')),
        ('GET /api/git/status', () => client.gitStatus('C:/w')),
        ('GET /api/git/diff', () => client.gitDiff('C:/w')),
        ('GET /api/file-index', () => client.fileIndex('C:/w', 'main')),
        ('GET /api/mcp', () => client.listMcp('C:/w')),
        ('GET /api/credentials', () => client.listCredentials()),
        ('POST /api/credentials', () => client.setApiKey('anthropic', 'sk-x')),
        (
          'DELETE /api/credentials/anthropic',
          () => client.removeApiKey('anthropic'),
        ),
        (
          'POST /api/mcp',
          () => client.upsertMcp(name: 'x', scope: 'user', config: {}),
        ),
        ('DELETE /api/mcp/x', () => client.removeMcp('x', scope: 'user')),
        (
          'PATCH /api/mcp/x',
          () => client.setMcpEnabled('x', scope: 'user', enabled: true),
        ),
        (
          'POST /api/upload',
          () => client.uploadFile(dir: 'C:/w', name: 'a.txt', base64: 'AA=='),
        ),
        ('GET /api/git/worktrees', () => client.listWorktrees('C:/w')),
        (
          'POST /api/git/worktrees',
          () => client.addWorktree(cwd: 'C:/w', dir: 'C:/wt'),
        ),
        (
          'DELETE /api/git/worktrees',
          () => client.removeWorktree(cwd: 'C:/w', dir: 'C:/wt'),
        ),
        ('GET /api/providers', () => client.listProviders()),
        ('POST /api/login', () => client.startLogin('anthropic', 'oauth')),
        ('GET /api/login/t1', () => client.loginStatus('t1')),
        ('POST /api/login/t1', () => client.answerLogin('t1', 'yes')),
        ('POST /api/login/t1', () => client.cancelLogin('t1')),
        ('POST /api/logout', () => client.logoutProvider('anthropic')),
        ('GET /api/packages', () => client.listPackages('C:/w')),
        ('POST /api/packages', () => client.packageAction(action: 'install')),
        ('GET /api/config/models', () => client.configModels('C:/w')),
        (
          'GET /api/config/thinking-levels',
          () => client.configThinkingLevels('C:/w', null, null),
        ),
        ('GET /api/config/commands', () => client.configCommands('C:/w')),
        ('GET /api/sessions/s1/usage', () => client.readSessionUsage('s1')),
        (
          'GET /api/sessions/s1/turn-summary',
          () => client.readTurnSummary('s1'),
        ),
        ('GET /api/usage', () => client.readUsageSummary()),
        ('GET /api/config/default-model', () => client.readDefaultModel()),
        (
          'POST /api/config/default-model',
          () => client.writeDefaultModel('p', 'm'),
        ),
        ('GET /api/sessions/s1/export', () => client.exportMarkdown('s1')),
        ('POST /api/sessions/s1/export', () => client.exportToServer('s1')),
        (
          'POST /api/sessions/s1/command',
          () => client.command('s1', {'type': 'x'}),
        ),
        (
          'POST /api/sessions/s1/ui-response',
          () => client.respondToUi('s1', 'r1', {}),
        ),
      ];

      final wrong = <String>[];
      for (final (expected, call) in cases) {
        hits.clear();
        try {
          await call();
        } catch (error) {
          wrong.add('$expected → 抛了 $error');
          continue;
        }
        if (hits.isEmpty) {
          wrong.add('$expected → 一个请求都没发');
          continue;
        }
        final got = '${hits.first.method} ${hits.first.uri.path}';
        if (got != expected) wrong.add('$expected → 实际是 $got');
      }

      expect(wrong, isEmpty, reason: '端点不匹配：\n${wrong.join('\n')}');
    });

    test('createSession：服务端给的 id 要带回来，端点也没打错', () async {
      responseBody = '{"sessionId":"s-new"}';

      expect(await client.createSession('C:/w'), 's-new');
      expect('${hits.last.method} ${hits.last.uri.path}', 'POST /api/sessions');
    });

    test('createSession：服务端没给 id 时必须抛（不能返回空 id 让上层存脏数据）', () async {
      // responseBody 默认是 {}，也就是没有 id
      await expectLater(
        client.createSession('C:/w'),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('参数传递：query 与 body 不能丢', () {
    test('gitDiff：cwd 必带，path 传了才带', () async {
      await client.gitDiff('C:/w');
      expect(hits.last.uri.queryParameters['cwd'], 'C:/w');
      expect(hits.last.uri.queryParameters.containsKey('path'), isFalse);

      await client.gitDiff('C:/w', path: 'lib/a.dart');
      expect(hits.last.uri.queryParameters['path'], 'lib/a.dart');
    });

    test('fileIndex：cwd 与搜索词（q，不是 query）都在 query 里', () async {
      await client.fileIndex('C:/w', 'chat');
      expect(hits.last.uri.queryParameters['cwd'], 'C:/w');
      expect(hits.last.uri.queryParameters['q'], 'chat');
    });

    test('removeMcp / setMcpEnabled：scope 走 query，名字走路径', () async {
      await client.removeMcp('github', scope: 'project', cwd: 'C:/w');
      expect(hits.last.uri.path, '/api/mcp/github');
      expect(hits.last.uri.queryParameters['scope'], 'project');
      expect(hits.last.uri.queryParameters['cwd'], 'C:/w');
    });

    test('MCP 名字里的特殊字符要编码（否则路径被截断，删错东西）', () async {
      await client.removeMcp('a/b c', scope: 'user');
      // 编码后仍应落在 /api/mcp/ 下面，且只能是一段路径
      expect(hits.last.uri.path, startsWith('/api/mcp/'));
      expect(hits.last.uri.pathSegments.length, 3);
      expect(hits.last.uri.path, isNot(contains(' ')));
    });

    test('respondToUi：body 里既有 id 也有用户的选择', () async {
      await client.respondToUi('s1', 'req-9', {'answer': '同意'});
      final body = jsonDecode(hits.last.body) as Map;
      expect(body['id'], 'req-9');
      expect(body['answer'], '同意');
    });

    test('uploadFile：dir / name / base64 / overwrite 四个都传', () async {
      await client.uploadFile(
        dir: 'C:/w',
        name: 'a.txt',
        base64: 'AA==',
        overwrite: true,
      );
      final body = jsonDecode(hits.last.body) as Map;
      expect(body['dir'], 'C:/w');
      expect(body['name'], 'a.txt');
      expect(body['base64'], 'AA==');
      expect(body['overwrite'], isTrue);
    });

    test('addWorktree：空的 branch / base 不该混进 body（服务端会当成真值）', () async {
      await client.addWorktree(cwd: 'C:/w', dir: 'C:/wt');
      final body = jsonDecode(hits.last.body) as Map;
      expect(body['cwd'], 'C:/w');
      expect(body['dir'], 'C:/wt');
      expect(body.containsKey('branch'), isFalse);
      expect(body.containsKey('base'), isFalse);
    });

    test('removeWorktree：force 只在为真时才带', () async {
      await client.removeWorktree(cwd: 'C:/w', dir: 'C:/wt');
      expect(hits.last.uri.queryParameters.containsKey('force'), isFalse);

      await client.removeWorktree(cwd: 'C:/w', dir: 'C:/wt', force: true);
      expect(hits.last.uri.queryParameters['force'], '1');
    });
  });

  group('rawFile：唯一不走 _json 的实现（要拿字节与响应头）', () {
    test('200：带回 contentType 与 x-pi-file-kind', () async {
      custom = (req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('image', 'png')
          ..headers.set('x-pi-file-kind', 'image')
          ..add([1, 2, 3, 4]);
        await req.response.close();
      };

      final data = await client.rawFile('C:/a.png');

      expect(data.bytes, [1, 2, 3, 4]);
      expect(data.contentType, 'image/png');
      expect(data.kind, 'image');
    });

    test('缺 x-pi-file-kind 时退回 binary（不抛）', () async {
      custom = (req) async {
        req.response
          ..statusCode = 200
          ..add([7]);
        await req.response.close();
      };

      final data = await client.rawFile('C:/a.bin');
      expect(data.kind, 'binary');
      expect(
        data.contentType,
        isNotEmpty,
        reason: '缺失时要给一个能用的默认值，调用方直接拿它当 Content-Type',
      );
    });

    test('非 200：抛 ServerException（不能静默给个空文件）', () async {
      custom = (req) async {
        req.response
          ..statusCode = 404
          ..add(utf8.encode('{"error":"no such file"}'));
        await req.response.close();
      };

      await expectLater(
        client.rawFile('C:/nope.png'),
        throwsA(isA<ServerException>()),
      );
    });

    test('文件路径走 query 而不是路径段（Windows 的盘符与反斜杠不能进路径）', () async {
      await client.rawFile('C:/work/图 片.png');
      expect(hits.last.uri.path, '/api/file/raw');
      expect(hits.last.uri.queryParameters['path'], 'C:/work/图 片.png');
    });
  });

  group('超时', () {
    test('响应慢于超时：抛异常并给出人话（不是一直挂着）', () async {
      custom = (req) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        req.response
          ..statusCode = 200
          ..add(utf8.encode('{}'));
        await req.response.close();
      };

      await expectLater(
        client.health(timeout: const Duration(milliseconds: 200)),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
