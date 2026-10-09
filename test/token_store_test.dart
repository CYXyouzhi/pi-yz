// token 存储与迁移的守卫。
//
// 这块的失败方式很特殊：**不会报错，只会悄悄出问题**——
//   · 迁移写坏 → 用户的 token 消失，下次连不上，还得重新配一遍（他未必还记得那串）
//   · 迁移漏做 → 明文继续留在 SharedPreferences 里，界面上一切正常，但安全目标没达成
//
// 所以三条路径（成功 / 本来就没明文 / 安全存储写不进去）都要钉住，
// 而且断言要打在「prefs 里到底还有没有明文」这种**可观察的事实**上。
import 'dart:convert';

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
}
