// 服务端连接配置。
//
// 原型的连接页配的是 SSH（主机/密钥/工作区），现在服务端是 HTTP，
// 所以字段改成：地址 + 端口 + token + 默认工作区。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
  }) =>
      ServerProfile(
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'token': token,
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

  static Future<List<ServerProfile>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => ServerProfile.fromJson(item.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveAll(List<ServerProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
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
