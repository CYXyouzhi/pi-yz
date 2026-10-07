// config 领域的数据模型
//
// 由 server_types.dart 拆分而来（原文件保留为 barrel，
// 所以调用方 import 路径不用改）。




/// MCP 服务器（只读列举）
class McpServerInfo {
  const McpServerInfo({
    required this.name,
    required this.scope,
    required this.kind,
    required this.target,
    this.args = '',
    this.enabled = true,
    this.description = '',
  });

  final String name;
  final String scope; // user | project
  final String kind; // local | remote
  final String target;
  final String args;

  /// enabled:false 表示条目保留但不连接
  final bool enabled;
  final String description;

  factory McpServerInfo.fromJson(Map<String, dynamic> json) => McpServerInfo(
        name: json['name'] as String? ?? '',
        scope: json['scope'] as String? ?? 'user',
        kind: json['kind'] as String? ?? 'local',
        target: json['target'] as String? ?? '',
        args: json['args'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        description: json['description'] as String? ?? '',
      );
}

/// Provider 凭据（只报哪个 provider 配了，不含密钥本体）


/// Provider 凭据（只报哪个 provider 配了，不含密钥本体）
class CredentialInfo {
  const CredentialInfo({required this.provider, required this.type});
  final String provider;
  final String type;

  factory CredentialInfo.fromJson(Map<String, dynamic> json) => CredentialInfo(
        provider: json['provider'] as String? ?? '',
        type: json['type'] as String? ?? 'api_key',
      );
}


/// 一个已配置的 pi 包（插件）



/// 一个已配置的 pi 包（插件）
class PiPackageInfo {
  const PiPackageInfo({
    required this.source,
    required this.scope,
    this.filtered = false,
    this.installedPath,
    this.zhCount = 0,
  });

  /// npm:xxx / git 地址 / 本地路径
  final String source;
  final String scope; // user | project
  final bool filtered;
  final String? installedPath;

  /// 电脑端汉化扩展在这个包里翻译了多少处文案（0 = 没汉化过）
  final int zhCount;

  factory PiPackageInfo.fromJson(Map<String, dynamic> json) => PiPackageInfo(
        source: json['source'] as String? ?? '',
        scope: json['scope'] as String? ?? 'user',
        filtered: json['filtered'] as bool? ?? false,
        installedPath: json['installedPath'] as String?,
        zhCount: (json['zhCount'] as num?)?.toInt() ?? 0,
      );
}

/// 可更新的包


/// 可更新的包
class PackageUpdateInfo {
  const PackageUpdateInfo({required this.source, this.displayName = '', this.type = 'npm'});

  final String source;
  final String displayName;
  final String type;

  factory PackageUpdateInfo.fromJson(Map<String, dynamic> json) => PackageUpdateInfo(
        source: json['source'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        type: json['type'] as String? ?? 'npm',
      );
}

/// 原始文件（图片 / PDF 预览）


// ==================== Provider 登录（/api/providers, /api/login） ====================

/// provider 支持的一种登录方式
class AuthOption {
  const AuthOption({
    required this.type,
    required this.label,
    this.interactive = true,
    this.subscription = false,
  });

  /// api_key | oauth
  final String type;
  final String label;

  /// false = 只能靠环境变量/配置文件，界面上点不了
  final bool interactive;
  final bool subscription;

  factory AuthOption.fromJson(Map<String, dynamic> json) => AuthOption(
        type: json['type'] as String? ?? 'api_key',
        label: json['label'] as String? ?? 'API Key',
        interactive: json['interactive'] as bool? ?? true,
        subscription: json['subscription'] as bool? ?? false,
      );
}


class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    this.configured = false,
    this.source,
    this.label,
    this.auth = const [],
  });

  final String id;
  final String name;
  final bool configured;
  final String? source;
  final String? label;
  final List<AuthOption> auth;

  factory ProviderInfo.fromJson(Map<String, dynamic> json) => ProviderInfo(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        configured: json['configured'] as bool? ?? false,
        source: json['source'] as String?,
        label: json['label'] as String?,
        auth: (json['auth'] as List?)
                ?.whereType<Map>()
                .map((e) => AuthOption.fromJson(e.cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}

/// 登录流程里的一个提示（服务端问、用户答）


/// 登录流程里的一个提示（服务端问、用户答）
class AuthPromptInfo {
  const AuthPromptInfo({
    required this.type,
    required this.message,
    this.placeholder,
    this.options = const [],
  });

  /// text | secret | select | manual_code
  final String type;
  final String message;
  final String? placeholder;
  final List<({String id, String label, String? description})> options;

  factory AuthPromptInfo.fromJson(Map<String, dynamic> json) => AuthPromptInfo(
        type: json['type'] as String? ?? 'text',
        message: json['message'] as String? ?? '',
        placeholder: json['placeholder'] as String?,
        options: (json['options'] as List?)
                ?.whereType<Map>()
                .map((e) => (
                      id: e['id'] as String? ?? '',
                      label: e['label'] as String? ?? '',
                      description: e['description'] as String?,
                    ))
                .toList() ??
            const [],
      );
}

/// 登录流程的一次轮询结果


/// 登录流程的一次轮询结果
class LoginStatus {
  const LoginStatus({
    required this.id,
    required this.state,
    this.prompt,
    this.events = const [],
    this.error,
  });

  /// running | prompt | done | error | cancelled
  final String state;
  final String id;
  final AuthPromptInfo? prompt;

  /// 服务端推来的信息（授权链接、设备码、进度）
  final List<Map<String, dynamic>> events;
  final String? error;

  bool get isFinished => state == 'done' || state == 'error' || state == 'cancelled';

  factory LoginStatus.fromJson(Map<String, dynamic> json) => LoginStatus(
        id: json['id'] as String? ?? '',
        state: json['state'] as String? ?? 'running',
        prompt: json['prompt'] is Map
            ? AuthPromptInfo.fromJson((json['prompt'] as Map).cast<String, dynamic>())
            : null,
        events: (json['events'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            const [],
        error: json['error'] as String?,
      );
}


/// 一轮（一次模型调用）的用量明细。数字全部来自落盘 JSONL，缺的就是 null。
