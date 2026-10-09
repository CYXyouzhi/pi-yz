// 服务端连接配置。
//
// 原型的连接页配的是 SSH（主机/密钥/工作区），现在服务端是 HTTP，
// 所以字段改成：地址 + 端口 + token + 默认工作区。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:pi_yz/server/token_store.dart';

class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.token,
    this.defaultCwd,
    this.secure = false,
    this.fallbackHost,
    this.fallbackPort,
    this.fallbackSecure = false,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String token;

  /// 新建会话时默认使用的远程工作目录
  final String? defaultCwd;

  /// 走 HTTPS（远程隧道用）。局域网直连是 http。
  final bool secure;

  /// 备用地址（可选）。
  ///
  /// 用途：在家走局域网、出门走 VPN（Tailscale 之类）——主地址连不上时
  /// **自动**试这个，不用手动切 profile。为空 = 不启用回落，行为与以前完全一致。
  ///
  /// 为什么是「同一个 profile 里的两个地址」而不是「两个 profile 手动切」：
  /// 用户分不清「现在该用哪个」，而程序分得清（哪个连得上用哪个）。
  final String? fallbackHost;
  final int? fallbackPort;
  final bool fallbackSecure;

  /// 是否配了可用的备用地址
  bool get hasFallback => (fallbackHost ?? '').trim().isNotEmpty;

  String get displayName =>
      name.trim().isNotEmpty ? name.trim() : (secure ? host : '$host:$port');

  /// 展示用：secure 且 443 时不带端口（`https://xxx.trycloudflare.com` 才是它本来的样子）
  String get endpoint {
    if (!secure) return '$host:$port';
    return port == 443 ? 'https://$host' : 'https://$host:$port';
  }

  ServerProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? token,
    String? defaultCwd,
    bool? secure,
    String? fallbackHost,
    int? fallbackPort,
    bool? fallbackSecure,
  }) => ServerProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    token: token ?? this.token,
    defaultCwd: defaultCwd ?? this.defaultCwd,
    secure: secure ?? this.secure,
    fallbackHost: fallbackHost ?? this.fallbackHost,
    fallbackPort: fallbackPort ?? this.fallbackPort,
    fallbackSecure: fallbackSecure ?? this.fallbackSecure,
  );

  /// 序列化。
  ///
  /// **默认不含 token** —— token 归 [TokenStore] 管（见 lib/server/token_store.dart）。
  /// 写进这里就等于把它以明文留在 SharedPreferences 的 JSON 里，
  /// 而那个文件只要有读权限就能整个拿走。
  ///
  /// 只有 `ServerProfileStore.saveAll` 在「安全存储写不进去」的降级路径上会传
  /// `includeToken: true`。
  Map<String, dynamic> toJson({bool includeToken = false}) => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    if (includeToken && token.isNotEmpty) 'token': token,
    if (defaultCwd != null) 'defaultCwd': defaultCwd,
    if (secure) 'secure': true,
    // 备用地址：只在真配了才写，保持旧 profile 的 JSON 面貌不变
    if (hasFallback) 'fallbackHost': fallbackHost,
    if (fallbackPort != null) 'fallbackPort': fallbackPort,
    if (fallbackSecure) 'fallbackSecure': true,
  };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    host: json['host'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 30142,
    token: json['token'] as String? ?? '',
    defaultCwd: json['defaultCwd'] as String?,
    secure: json['secure'] == true,
    fallbackHost: json['fallbackHost'] as String?,
    fallbackPort: (json['fallbackPort'] as num?)?.toInt(),
    fallbackSecure: json['fallbackSecure'] == true,
  );
}

class ServerProfileStore {
  static const _profilesKey = 'server_profiles_v1';
  static const _activeKey = 'server_active_profile_v1';

  /// token 的具体存放处。
  ///
  /// 默认是回落实现（明文，但至少与连接配置分开存）；Android 上由 `main()`
  /// 换成 Keystore 实现。测试里换成假的就能验证「写不进去时不许弄丢 token」。
  static TokenStore tokenStore = PrefsTokenStore();

  static Future<List<ServerProfile>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return const [];
    final List<Map<String, dynamic>> items;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      items = decoded
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return const [];
    }

    final result = await migratePlaintextTokens(items, tokenStore);

    // 有 token 刚被搬进安全存储 → 把明文从 prefs 里抹掉。
    //
    // 这一步放在 load 里做有点意外，但迁移只有这一次机会：老版本留下的明文
    // 只存在于这个 JSON 里，不在这儿抹就再没有别的时机（用户不会主动去做
    // 「把 token 换个地方存」这件事）。
    if (result.migrated > 0) {
      await prefs.setString(
        _profilesKey,
        jsonEncode(result.profiles.map((p) => p.toJson()).toList()),
      );
    }
    return result.profiles;
  }

  static Future<void> saveAll(List<ServerProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();

    // 先把 token 写进安全存储（并回读确认）。只要有一个写不进去，就整体退化成
    // 老做法（token 也写进 JSON）—— 两害相权：留在明文里是**风险**，
    // 把 token 弄丢是用户**立刻连不上**，后者更糟、且用户无法自救。
    var allStored = true;
    for (final p in profiles) {
      if (p.token.isEmpty) continue;
      final ok = await tokenStore.write(p.id, p.token);
      if (ok && await tokenStore.read(p.id) == p.token) continue;
      allStored = false;
      break;
    }

    await prefs.setString(
      _profilesKey,
      jsonEncode(
        profiles.map((p) => p.toJson(includeToken: !allStored)).toList(),
      ),
    );
  }

  static Future<String?> loadActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeKey);
  }

  static Future<void> saveActiveId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setString(_activeKey, id);
    }
  }
}

/// 一次「明文 token 迁移」的结果。
class TokenMigration {
  const TokenMigration({required this.profiles, required this.migrated});

  /// token 已经就位的连接配置（来源可能是安全存储，也可能是还没搬完的明文）
  final List<ServerProfile> profiles;

  /// 成功搬进安全存储的条数。> 0 表示 prefs 里的 JSON 还带着明文，需要重写。
  final int migrated;
}

/// 把旧格式 JSON 里的明文 token 搬进 [store]。
///
/// 三条不能违反的规则：
///
/// 1. **先写新、再抹旧**：写不进去就保持原样。宁可不迁移，也不能把 token 弄丢
///    —— 丢了用户得重新配一遍连接，而他未必还记得那串 token。
/// 2. **回读确认**：写完读回来一致才算成功。只信写入返回值不够，回落实现与
///    Keystore 的「成功」语义并不完全一样。
/// 3. **幂等**：安全存储里已经有值就以它为准，不再用旧明文覆盖。用户可能刚在
///    设置页改过 token，JSON 里那份反而是过期数据。
Future<TokenMigration> migratePlaintextTokens(
  List<Map<String, dynamic>> raw,
  TokenStore store,
) async {
  final profiles = <ServerProfile>[];
  var migrated = 0;

  for (final json in raw) {
    final profile = ServerProfile.fromJson(json);
    final plaintext = (json['token'] as String?) ?? '';
    var stored = await store.read(profile.id);

    // 只在明文里有 → 搬过去（写成功还要回读确认）
    if ((stored == null || stored.isEmpty) && plaintext.isNotEmpty) {
      if (await store.write(profile.id, plaintext)) {
        stored = await store.read(profile.id);
      }
    }

    final hasInStore = stored != null && stored.isNotEmpty;
    // 安全存储里有、JSON 里也有 → JSON 里这份明文可以抹掉了
    if (hasInStore && plaintext.isNotEmpty) migrated += 1;

    profiles.add(profile.copyWith(token: hasInStore ? stored : plaintext));
  }

  return TokenMigration(profiles: profiles, migrated: migrated);
}
