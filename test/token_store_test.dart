// token 存储与迁移的守卫。
//
// 这块的失败方式很特殊：**不会报错，只会悄悄出问题**——
//   · 迁移写坏 → 用户的 token 消失，下次连不上，还得重新配一遍（他未必还记得那串）
//   · 迁移漏做 → 明文继续留在 SharedPreferences 里，界面上一切正常，但安全目标没达成
//
// 所以三条路径（成功 / 本来就没明文 / 安全存储写不进去）都要钉住，
// 而且断言要打在「prefs 里到底还有没有明文」这种**可观察的事实**上。
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_yz/server/server_profile.dart';
import 'package:pi_yz/server/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可控的假存储：能模拟「Keystore 写不进去」（真机上表现为密钥被系统清掉、
/// 或设备不支持）。
class _FakeTokenStore implements TokenStore {
  _FakeTokenStore({this.failWrites = false});

  final Map<String, String> data = {};
  bool failWrites;
  int writes = 0;

  @override
  bool get isSecure => true;

  @override
  Future<String?> read(String id) async => data[id];

  @override
  Future<bool> write(String id, String token) async {
    writes += 1;
    if (failWrites) return false;
    data[id] = token;
    return true;
  }

  @override
  Future<void> delete(String id) async => data.remove(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerProfileStore.tokenStore = PrefsTokenStore();
  });

  group('迁移：明文 → 安全存储', () {
    test('成功：token 进了安全存储，且告诉调用方「JSON 可以重写了」', () async {
      final store = _FakeTokenStore();
      final raw = [
        {
          'id': 'p1',
          'name': '家里',
          'host': '192.168.1.9',
          'port': 30142,
          'token': 'secret-1',
        },
      ];

      final result = await migratePlaintextTokens(raw, store);

      expect(result.profiles.single.token, 'secret-1');
      expect(store.data['p1'], 'secret-1');
      expect(result.migrated, 1, reason: '> 0 才表示 JSON 里那份明文该抹了');
    });

    test('JSON 里本来就没有 token：不写、不重写（幂等）', () async {
      final store = _FakeTokenStore()..data['p1'] = 'secret-1';
      final raw = [
        {'id': 'p1', 'name': '家里', 'host': 'h', 'port': 1},
      ];

      final result = await migratePlaintextTokens(raw, store);

      expect(result.profiles.single.token, 'secret-1', reason: '要从安全存储读回来');
      expect(result.migrated, 0, reason: 'JSON 里没有明文，不需要重写');
      expect(store.writes, 0, reason: '没有明文就别去写它');
    });

    test('安全存储写不进去：token 仍可用，且不允许抹掉明文（不许丢数据）', () async {
      final store = _FakeTokenStore(failWrites: true);
      final raw = [
        {'id': 'p1', 'name': '家里', 'host': 'h', 'port': 1, 'token': 'secret-1'},
      ];

      final result = await migratePlaintextTokens(raw, store);

      expect(
        result.profiles.single.token,
        'secret-1',
        reason: '搬不过去就继续用明文里那份 —— 丢 token 比暂时留着明文更糟',
      );
      expect(result.migrated, 0, reason: '没搬成功就不能让调用方去抹明文');
    });

    test('两处都有值：以安全存储为准（用户可能刚改过 token）', () async {
      final store = _FakeTokenStore()..data['p1'] = '新token';
      final raw = [
        {'id': 'p1', 'name': '家里', 'host': 'h', 'port': 1, 'token': '旧token'},
      ];

      final result = await migratePlaintextTokens(raw, store);

      expect(result.profiles.single.token, '新token');
      expect(result.migrated, 1, reason: 'JSON 里那份过期明文仍然要抹掉');
    });

    test('多条里有一条写不进去：其余照常迁移', () async {
      final store = _FakeTokenStore(failWrites: true);
      store.data['ok'] = 'already-there';
      final raw = [
        {'id': 'ok', 'name': 'a', 'host': 'h', 'port': 1, 'token': '旧值'},
        {'id': 'bad', 'name': 'b', 'host': 'h', 'port': 2, 'token': '搬不动'},
      ];

      final result = await migratePlaintextTokens(raw, store);

      expect(result.profiles.map((p) => p.token).toList(), [
        'already-there',
        '搬不动',
      ]);
      expect(result.migrated, 1, reason: '只有 ok 那条的明文可以抹');
    });
  });

  group('往返：连接配置里不再有 token', () {
    test('saveAll 之后 prefs 里找不到 token，但 loadAll 能读回来', () async {
      const p = ServerProfile(
        id: 'p1',
        name: '家里',
        host: '192.168.1.9',
        port: 30142,
        token: 'secret-1',
      );

      await ServerProfileStore.saveAll([p]);

      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString('server_profiles_v1')!;
      expect(
        rawJson,
        isNot(contains('secret-1')),
        reason: '明文不能出现在连接配置里 —— 这是整块改动要达成的那个事实',
      );

      final back = await ServerProfileStore.loadAll();
      expect(back.single.token, 'secret-1', reason: '应用自己必须还能拿到');
      expect(back.single.host, '192.168.1.9');
      expect(back.single.port, 30142);
    });

    test('读旧版本留下的 JSON：自动迁移并把明文从 prefs 抹掉', () async {
      SharedPreferences.setMockInitialValues({
        'server_profiles_v1': jsonEncode([
          {
            'id': 'p1',
            'name': '家里',
            'host': '192.168.1.9',
            'port': 30142,
            'token': '旧明文',
          },
        ]),
      });

      final first = await ServerProfileStore.loadAll();
      expect(first.single.token, '旧明文', reason: '迁移不能让用户察觉token变了');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('server_profiles_v1'),
        isNot(contains('旧明文')),
        reason: 'loadAll 就是迁移时机：老版本的明文只存在于这个 JSON 里',
      );
      expect(
        await PrefsTokenStore().read('p1'),
        '旧明文',
        reason: '抹明文之前必须确认 token 已经存好',
      );

      // 再读一次：这次不该再重写（幂等）
      final second = await ServerProfileStore.loadAll();
      expect(second.single.token, '旧明文');
      expect(second.single.name, '家里');
    });

    test('降级路径：安全存储写不进去时，宁可按老做法写进 JSON 也不让它消失', () async {
      ServerProfileStore.tokenStore = _FakeTokenStore(failWrites: true);
      const p = ServerProfile(
        id: 'p1',
        name: '家里',
        host: 'h',
        port: 1,
        token: 'secret-1',
      );

      await ServerProfileStore.saveAll([p]);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('server_profiles_v1'),
        contains('secret-1'),
        reason:
            '这是**有意的**降级：连不上比明文风险更让用户难受，'
            '而且用户无法自救。SECURITY.md 里如实写明这条',
      );

      // 降级之后也不能把用户卡死：还能正常读回来
      ServerProfileStore.tokenStore = PrefsTokenStore();
      final back = await ServerProfileStore.loadAll();
      expect(back.single.token, 'secret-1');
    });
  });

  group('回落实现本身', () {
    test('读写删：键是独立的（不跟连接配置混在一个 JSON 里）', () async {
      final store = PrefsTokenStore();

      await store.write('p1', 'abc');
      expect(await store.read('p1'), 'abc');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('${PrefsTokenStore.keyPrefix}p1'),
        'abc',
        reason: '独立键：连接配置泄露不再等于 token 泄露',
      );
      expect(prefs.getString('server_profiles_v1'), isNull);

      await store.delete('p1');
      expect(await store.read('p1'), isNull);
    });

    test('如实报告自己不是安全存储（界面与文档都靠这个措辞）', () async {
      expect(PrefsTokenStore().isSecure, isFalse);
      expect(_FakeTokenStore().isSecure, isTrue);
    });
  });

  // Android 实现是一条跨语言的链：Dart → 通道 → Keystore。链上任何一环断了
  // 都不能把异常冒到启动路径上（那会白屏），而只能是「退化成读不到」
  // —— 上层会请用户重新输入 token。原生的加密机制见 SecureTokenStore.kt。
  group('Android 实现：通道通了才叫安全，不通就回落', () {
    const channel = MethodChannel('pi_yz/native');
    late List<MethodCall> calls;

    /// 用例可改的剧本
    String? tokenFromNative;
    bool putResult = true;
    Object? throwThis;

    setUp(() {
      calls = <MethodCall>[];
      tokenFromNative = null;
      putResult = true;
      throwThis = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (throwThis != null) throw throwThis!;
            return switch (call.method) {
              'secureGet' => tokenFromNative,
              'securePut' => putResult,
              'secureAvailable' => true,
              _ => null,
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('write：把 id 与 token 交给原生去加密', () async {
      expect(await KeystoreTokenStore().write('p1', 'secret-1'), isTrue);

      expect(calls.single.method, 'securePut');
      final args = calls.single.arguments as Map;
      expect(args['id'], 'p1');
      expect(args['token'], 'secret-1');
    });

    test('write：原生说写不进去 → 返回 false（上层据此不抹明文）', () async {
      putResult = false;
      expect(await KeystoreTokenStore().write('p1', 'secret-1'), isFalse);
    });

    test('read：把原生解出来的 token 带回去', () async {
      tokenFromNative = 'secret-1';
      expect(await KeystoreTokenStore().read('p1'), 'secret-1');
      expect(calls.single.method, 'secureGet');
    });

    test('read：解密失败（换机 / 清数据）当读不到，不抛', () async {
      throwThis = PlatformException(code: 'decrypt_failed');
      await expectLater(KeystoreTokenStore().read('p1'), completion(isNull));
    });

    test('原生的各种异常都不许冒出去 —— 启动路径上崩了就是白屏', () async {
      throwThis = MissingPluginException('没有这个实现');
      final store = KeystoreTokenStore();

      await expectLater(store.read('p1'), completion(isNull));
      await expectLater(store.write('p1', 'x'), completion(isFalse));
      await expectLater(store.delete('p1'), completes);
    });

    test('delete：走 secureRemove', () async {
      await KeystoreTokenStore().delete('p1');
      expect(calls.single.method, 'secureRemove');
    });

    test('空 id：一个跨语言调用都不发（别去动不属于自己的东西）', () async {
      final store = KeystoreTokenStore();

      expect(await store.read(''), isNull);
      expect(await store.write('', 'x'), isFalse);
      await store.delete('');

      expect(calls, isEmpty);
    });

    test('resolveTokenStore：非 Android 环境回落本地存储', () async {
      // 测试跑在桌面上，Platform.isAndroid 为 false
      final store = await resolveTokenStore();
      expect(store, isA<PrefsTokenStore>());
      expect(store.isSecure, isFalse, reason: '回落实现不得假装安全');
    });
  });
}
