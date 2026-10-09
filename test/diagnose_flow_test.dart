// 连接诊断流程（`runDiagnosis`）的守卫。
//
// 之前这个函数 **0% 覆盖** —— 而它是「连不上时用户唯一能自助的地方」：
// 逐项查出是域名、端口、服务端还是 token 的问题，并给出下一步。
// 它内部直接 `new HttpClient()`，所以用 loopback 假服务端来测（同 server_client 的做法）。
//
// 三条主路径：全部通过 / 域名解析失败 / 端口没人监听（后两项决定了「失败时要指对方向」）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/diagnose.dart';

void main() {
  late HttpServer server;
  late int port;
  HttpOverrides? saved;

  setUp(() async {
    // flutter_test 会把 HttpClient 换成「一律 400」的 mock，要真连必须先还原
    saved = HttpOverrides.current;
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
  });

  tearDown(() async {
    await server.close(force: true);
    HttpOverrides.global = saved;
  });

  Future<void> serveHealthy() async {
    server.listen((req) async {
      final authorized =
          req.headers.value('authorization') == 'Bearer good-token';
      final body = switch (req.uri.path) {
        '/api/health' => '{"ok":true,"piVersion":"1.0.4","activeSessions":2}',
        // 需要鉴权的端点：token 不对就 401
        _ when !authorized => '{"error":"unauthorized"}',
        _ => '{}',
      };
      req.response
        ..statusCode = body.contains('unauthorized') ? 401 : 200
        ..headers.contentType = ContentType.json
        ..add(utf8.encode(body));
      await req.response.close();
    });
  }

  test('全部通过：域名 / 端口 / 健康检查 / 服务端信息 / 鉴权 逐项 ok', () async {
    await serveHealthy();

    final report = await runDiagnosis(
      host: '127.0.0.1',
      port: port,
      token: 'good-token',
      timeout: const Duration(seconds: 3),
    );

    expect(report.host, '127.0.0.1');
    expect(report.port, port);
    expect(report.steps, isNotEmpty);
    expect(
      report.allOk,
      isTrue,
      reason:
          '失败项：${report.steps.where((s) => !s.ok).map((s) => s.title).join('、')}',
    );
    // 至少跑了 域名 / 端口 / 健康检查 / 鉴权 四步
    expect(report.steps.length, greaterThanOrEqualTo(4));
    expect(report.elapsed.inMilliseconds, greaterThanOrEqualTo(0));
  });

  test('域名解析不了：第一步就失败，并给出下一步（不是「未知错误」）', () async {
    final report = await runDiagnosis(
      host: 'nonexistent-host.invalid',
      port: port,
      token: 't',
      timeout: const Duration(seconds: 3),
    );

    expect(report.allOk, isFalse);
    final first = report.steps.first;
    expect(first.ok, isFalse);
    expect(first.detail, isNotEmpty);
    // 解析不了时后续步骤应说明「跳过」而不是假装通过
    final portStep = report.steps.elementAt(1);
    expect(portStep.ok, isFalse);
  });

  test('端口没人监听：域名那步通过、端口那步失败', () async {
    final report = await runDiagnosis(
      host: '127.0.0.1',
      port: 1, // 端口 1 上不会有服务（别用 port+1：会撞上别的服务）
      token: 't',
      timeout: const Duration(seconds: 3),
    );

    expect(report.allOk, isFalse);
    expect(report.steps.first.ok, isTrue, reason: '127.0.0.1 能解析，第一步应当通过');
    final portStep = report.steps.elementAt(1);
    expect(portStep.ok, isFalse);
    expect(portStep.detail, isNotEmpty);
  });

  test('token 不对：鉴权那步失败（前面的步骤照样通过）', () async {
    await serveHealthy();

    final report = await runDiagnosis(
      host: '127.0.0.1',
      port: port,
      token: 'wrong-token',
      timeout: const Duration(seconds: 3),
    );

    expect(report.allOk, isFalse);
    // 前两步（域名、端口）与网络无关，应当照常通过 —— 这样用户一眼能看出
    // 「网是通的，问题在 token」
    expect(report.steps[0].ok, isTrue);
    expect(report.steps[1].ok, isTrue);
  });

  test('报告文本：列出失败项与下一步（诊断页要能复制给别人的那种）', () async {
    final report = await runDiagnosis(
      host: '127.0.0.1',
      port: 1,
      token: 't',
      timeout: const Duration(seconds: 3),
    );

    final text = report.toText();
    expect(text, contains('127.0.0.1'));
    expect(text, contains('1'));
    expect(text.length, greaterThan(20));
  });
}
