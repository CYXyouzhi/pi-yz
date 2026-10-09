// 局域网发现与配对码换 token 的守卫。
//
// `discovery.dart` 之前 0% 覆盖。它有两块：
//   · `DiscoveredServer.tryParse` —— 纯解析（UDP 广播响应的解析），最好测；
//   · `LanDiscovery.pair` —— 真发一个 POST 换 token，用 loopback 假服务端测。
//
// 重点在「别人的 UDP 服务别被误认成我们的服务端」和「服务端给的原因要透传给用户」
// 这两件事上 —— 前者错了会连到莫名其妙的地址，后者错了用户不知道该改什么。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/discovery.dart';

void main() {
  group('DiscoveredServer.tryParse', () {
    test('正常响应：字段齐全', () {
      final s = DiscoveredServer.tryParse(
        jsonEncode({
          'app': 'pi-yz-server',
          'name': 'CYX 的电脑',
          'port': 30142,
          'piVersion': '1.0.4',
          'pairingOpen': true,
        }),
        '10.1.1.195',
      )!;
      expect(s.name, 'CYX 的电脑');
      expect(s.host, '10.1.1.195', reason: 'host 一律取来源 IP，不信响应体里的自述');
      expect(s.port, 30142);
      expect(s.piVersion, '1.0.4');
      expect(s.pairingOpen, isTrue);
      expect(s.endpoint, '10.1.1.195:30142');
    });

    test('app 标记不对：一律不认（别的 UDP 服务不能被当成我们的服务端）', () {
      expect(
        DiscoveredServer.tryParse(
          jsonEncode({'app': 'something-else', 'port': 30142}),
          '10.1.1.9',
        ),
        isNull,
      );
      expect(
        DiscoveredServer.tryParse(jsonEncode({'port': 30142}), '10.1.1.9'),
        isNull,
      );
    });

    test('不是 JSON / 不是对象 / 空串：返回 null 而不是抛', () {
      for (final raw in ['', 'not json', '[1,2,3]', '"a string"']) {
        expect(
          DiscoveredServer.tryParse(raw, '10.1.1.9'),
          isNull,
          reason: '输入 "$raw" 不该抛，也不该被认成服务端',
        );
      }
    });

    test('name 缺失或空白：回退成来源地址（列表里总得有个能认的名字）', () {
      expect(
        DiscoveredServer.tryParse(
          jsonEncode({'app': 'pi-yz-server', 'port': 30142}),
          '10.1.1.7',
        )!.name,
        '10.1.1.7',
      );
      expect(
        DiscoveredServer.tryParse(
          jsonEncode({'app': 'pi-yz-server', 'name': '   '}),
          '10.1.1.7',
        )!.name,
        '10.1.1.7',
      );
    });

    test('port 缺失：用默认 30142；piVersion 缺失：占位 ?', () {
      final s = DiscoveredServer.tryParse(
        jsonEncode({'app': 'pi-yz-server'}),
        '10.1.1.7',
      )!;
      expect(s.port, 30142);
      expect(s.piVersion, '?');
    });

    test('pairingOpen 只认字面 true（1 / "true" 都不算开着配对窗口）', () {
      for (final v in [1, 'true', null]) {
        final s = DiscoveredServer.tryParse(
          jsonEncode({'app': 'pi-yz-server', 'pairingOpen': v}),
          '10.1.1.7',
        )!;
        expect(s.pairingOpen, isFalse, reason: 'pairingOpen=$v 不该被当成打开');
      }
    });
  });

  group('LanDiscovery.pair（loopback 假服务端）', () {
    late HttpServer server;
    late int port;
    HttpOverrides? saved;

    setUp(() async {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
    });

    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = saved;
    });

    Future<void> respond(
      int status,
      String body, {
      void Function(String code)? onCode,
    }) {
      server.listen((req) async {
        final raw = await utf8.decoder.bind(req).join();
        onCode?.call((jsonDecode(raw) as Map)['code'] as String? ?? '');
        req.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..add(utf8.encode(body));
        await req.response.close();
      });
      return Future<void>.value();
    }

    test('200 且带 token：配对成功，code 会 trim 后送出', () async {
      String? sent;
      await respond(200, '{"token":"abc-123"}', onCode: (c) => sent = c);

      final r = await LanDiscovery.pair(
        host: '127.0.0.1',
        port: port,
        code: '  123456  ',
      );
      expect(r.ok, isTrue);
      expect(r.token, 'abc-123');
      expect(sent, '123456', reason: '用户手输的配对码常带空格');
    });

    test('200 但 token 是空串：算失败（不能拿空 token 去连）', () async {
      await respond(200, '{"token":""}');
      final r = await LanDiscovery.pair(
        host: '127.0.0.1',
        port: port,
        code: '1',
      );
      expect(r.ok, isFalse);
      expect(r.token, isNull);
      expect(r.message, isNotEmpty);
    });

    test('非 200：把服务端写的原因透传给用户（例如「配对码不对」）', () async {
      await respond(400, '{"error":"配对码不对"}');
      final r = await LanDiscovery.pair(
        host: '127.0.0.1',
        port: port,
        code: '1',
      );
      expect(r.ok, isFalse);
      expect(r.message, contains('配对码不对'));
    });

    test('非 200 且正文不是 JSON：退回通用文案（带上状态码）', () async {
      await respond(502, 'bad gateway');
      final r = await LanDiscovery.pair(
        host: '127.0.0.1',
        port: port,
        code: '1',
      );
      expect(r.ok, isFalse);
      expect(r.message, contains('502'));
    });

    test('端口没人监听：失败但不抛，文案里带上地址', () async {
      // 用 1 端口：本机不会有服务监听它。
      //（一开始用 port+1，结果撞上了别的服务，报 Invalid response line —— 说明
      //  「随便挑一个相邻端口」不是可靠的「没人监听」。）
      final r = await LanDiscovery.pair(host: '127.0.0.1', port: 1, code: '1');
      expect(r.ok, isFalse);
      expect(r.message, contains('127.0.0.1'));
    });

    test('服务端不回话（超时）：失败但不抛', () async {
      server.listen((req) async {
        // 故意什么都不回
      });
      final r = await LanDiscovery.pair(
        host: '127.0.0.1',
        port: port,
        code: '1',
        timeout: const Duration(milliseconds: 200),
      );
      expect(r.ok, isFalse);
      expect(r.message, isNotEmpty);
    });
  });
}
