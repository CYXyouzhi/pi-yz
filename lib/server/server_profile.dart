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
  }) =>
      ServerProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        token: token ?? this.token,
        defaultCwd: defaultCwd ?? this.defaultCwd,
        secure: secure ?? this.secure,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'token': token,
        if (defaultCwd != null) 'defaultCwd': defaultCwd,
        if (secure) 'secure': true,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 30142,
        token: json['token'] as String? ?? '',
        defaultCwd: json['defaultCwd'] as String?,
        secure: json['secure'] == true,
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
