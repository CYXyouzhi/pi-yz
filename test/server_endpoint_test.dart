// 主地址 / 备用地址：候选列表的构造规则与 profile 序列化。
//
// ## 为什么这里不测「连不上自动回落」本身
//
// 那段逻辑在 `ServerStore.connect()` 里**直接 `new ServerClient()`**，没有注入点。
// 要单测它得先给生产代码加一层工厂参数 —— 为了测试改生产结构，而这轮改动
// 本来就不小，不划算。
//
// 所以回落**行为**改用实机验证：把主地址填成一个不存在的 IP、备用地址填对，
// 看它是否静默切到备用并连上（见 docs/verify/remote-access/README.md）。
//
// 这里覆盖的是回落所依赖的两块**纯数据**逻辑：
//   1. `candidates` 的构造规则（顺序、端口继承、空白处理）；
//   2. `ServerProfile` 的往返序列化 + 对旧 JSON 的向后兼容。

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/server_profile.dart';
import 'package:pi_yz/server/server_store.dart';

void main() {
  group('ServerTarget.candidates（候选地址顺序）', () {
    test('没配备用地址：只有一条候选，行为与改动前完全一致', () {
      const t = ServerTarget(host: '192.168.1.5', port: 30142, token: 'x');
      final c = t.candidates;

      expect(c.length, 1, reason: '未配备用时不能凭空多出候选');
      expect(c.first.host, '192.168.1.5');
      expect(c.first.port, 30142);
      expect(c.first.isFallback, isFalse);
    });

    test('配了备用地址：两条候选，主在前、备在后', () {
      const t = ServerTarget(
        host: '192.168.1.5',
        port: 30142,
        token: 'x',
        fallbackHost: '100.64.0.1',
        fallbackPort: 30142,
      );
      final c = t.candidates;

      expect(c.length, 2);
      // 顺序很关键：局域网延迟比走 VPN 低一个数量级，所以主地址必须排第一
      expect(c[0].host, '192.168.1.5');
      expect(c[0].isFallback, isFalse);
      expect(c[1].host, '100.64.0.1');
      expect(c[1].isFallback, isTrue, reason: '回落成功时界面要能标出来');
    });

    test('备用端口没填：继承主端口', () {
      const t = ServerTarget(
        host: '192.168.1.5',
        port: 30142,
        token: 'x',
        fallbackHost: '100.64.0.1',
      );
      expect(t.candidates[1].port, 30142);
    });

    test('备用地址只有空白：视为没配', () {
      const t = ServerTarget(
        host: 'a',
        port: 1,
        token: 'x',
        fallbackHost: '   ',
      );
      expect(t.candidates.length, 1);
    });

    test('备用地址前后有空格：会被 trim', () {
      const t = ServerTarget(
        host: 'a',
        port: 1,
        token: 'x',
        fallbackHost: '  100.64.0.1  ',
      );
      expect(t.candidates[1].host, '100.64.0.1');
    });

    test('备用地址可以走 HTTPS（主走局域网 http）', () {
      const t = ServerTarget(
        host: '192.168.1.5',
        port: 30142,
        token: 'x',
        fallbackHost: 'pi.example.com',
        fallbackPort: 443,
        fallbackSecure: true,
      );
      final c = t.candidates;
      expect(c[0].label, '192.168.1.5:30142');
      expect(c[1].label, 'https://pi.example.com');
    });
  });

  group('ServerProfile 序列化', () {
    test('往返保留备用地址三个字段', () {
      const p = ServerProfile(
        id: 'p1',
        name: '家里的电脑',
        host: '192.168.1.5',
        port: 30142,
        token: 'tok',
        fallbackHost: '100.64.0.1',
        fallbackPort: 30142,
        fallbackSecure: false,
      );

      final back = ServerProfile.fromJson(p.toJson());

      expect(back.host, '192.168.1.5');
      expect(back.fallbackHost, '100.64.0.1');
      expect(back.fallbackPort, 30142);
      expect(back.fallbackSecure, isFalse);
      expect(back.hasFallback, isTrue);
    });

    test('没配备用地址时，JSON 里不该多出这些键（保持旧面貌）', () {
      const p = ServerProfile(
        id: 'p1',
        name: 'x',
        host: 'h',
        port: 1,
        token: 't',
      );
      final json = p.toJson();

      expect(json.containsKey('fallbackHost'), isFalse);
      expect(json.containsKey('fallbackPort'), isFalse);
      expect(json.containsKey('fallbackSecure'), isFalse);
      expect(json['secure'], isNull, reason: 'secure=false 时也不写');
    });

    test('向后兼容：旧的 JSON（完全没有备用字段）能正常解析', () {
      // 这是升级路径的关键 —— 用户手机上存着的旧 profile 必须还能用
      final json = <String, dynamic>{
        'id': 'old',
        'name': '旧配置',
        'host': '192.168.1.9',
        'port': 30142,
        'token': 'legacy',
        'secure': true,
      };

      final p = ServerProfile.fromJson(json);

      expect(p.host, '192.168.1.9');
      expect(p.secure, isTrue);
      expect(p.hasFallback, isFalse, reason: '旧配置不该被判成"配了备用地址"');
      expect(p.fallbackHost, isNull);
      expect(p.fallbackPort, isNull);
    });

    test('fallbackSecure=true 才写进 JSON', () {
      const p = ServerProfile(
        id: 'p',
        name: 'x',
        host: 'h',
        port: 1,
        token: 't',
        fallbackHost: 'f',
        fallbackSecure: true,
      );
      expect(p.toJson()['fallbackSecure'], isTrue);
    });

    test('copyWith 能单独改备用地址而不动别的字段', () {
      const p = ServerProfile(
        id: 'p1',
        name: 'n',
        host: 'h',
        port: 1,
        token: 't',
      );
      final q = p.copyWith(fallbackHost: '100.64.0.1');

      expect(q.fallbackHost, '100.64.0.1');
      expect(q.host, 'h');
      expect(q.token, 't');
      expect(q.id, 'p1');
    });
  });
}
