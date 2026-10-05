// 连接诊断：把「连不上」拆成能动手的具体原因。
//
// 为什么单独做一层：用户看到「连接失败」四个字什么也做不了；
// 而「端口不通」「域名解析不了」「token 不对」各自有唯一的下一步动作。
// 这里的判定全是纯函数，方便单测钉住（网络现场难复现，判定逻辑必须能被验证）。

import 'dart:async';
import 'i18n.dart';
import 'dart:convert';
import 'dart:io';

/// 一次诊断里某一项的结果。
class DiagStep {
  DiagStep({
    required this.title,
    required this.ok,
    required this.detail,
    this.hint,
  });

  final String title;
  final bool ok;
  final String detail;

  /// 失败时给的下一步动作（成功时为 null）
  final String? hint;
}

enum FailureKind { dns, portClosed, timeout, auth, serverError, unknown }

/// 把一次网络异常翻译成「人话原因 + 下一步」。
///
/// 这是合同⑤的核心：不写「连接失败」，写成用户能动手的那句话。
({FailureKind kind, String reason, String hint}) explainFailure(Object error) {
  if (error is TimeoutException) {
    return (
      kind: FailureKind.timeout,
      reason: I18n.t('ui.4ac56645f2'),
      hint: I18n.t('ui.ec95d46034'),
    );
  }
  if (error is SocketException) {
    final osMessage = error.osError?.message ?? error.message;
    final lowered = osMessage.toLowerCase();
    final code = error.osError?.errorCode ?? 0;

    // 域名解析不了：Android 上是 "Failed host lookup"，Windows 上是 11001
    if (lowered.contains('host lookup') ||
        lowered.contains('nodename') ||
        code == 11001 ||
        code == 7) {
      return (
        kind: FailureKind.dns,
        reason: I18n.t('ui.357bb00861'),
        hint: I18n.t('ui.5590f8562f'),
      );
    }
    // 端口没人监听：拒绝连接
    if (lowered.contains('refused') || code == 10061 || code == 111) {
      return (
        kind: FailureKind.portClosed,
        reason: I18n.t('ui.b1f0198098'),
        hint: I18n.t('ui.fa0b5ce725'),
      );
    }
    if (lowered.contains('unreachable') || code == 10065 || code == 113) {
      return (
        kind: FailureKind.portClosed,
        reason: I18n.t('ui.e952bae0ad'),
        hint: I18n.t('ui.f9f149dbc2'),
      );
    }
    return (
      kind: FailureKind.unknown,
      reason: I18n.tp('ui.def254a2e0', {'msg': osMessage}),
      hint: I18n.t('ui.d057f4b6c9'),
    );
  }
  return (
    kind: FailureKind.unknown,
    reason: I18n.tp('ui.3dafb8747f', {'e': error}),
    hint: I18n.t('ui.8cf5b87a5a'),
  );
}

/// token 掩码：诊断结果经常要复制给别人看，不能把 token 明文带出去。
String maskToken(String token) {
  if (token.isEmpty) return I18n.t('ui.756aadc26d');
  // 短串一律全遮：露头露尾在短 token 上等于没遮（task-16 合同③，与服务端
  // lib/secrets.mjs 的 maskSecret 同一套规则）
  if (token.length <= 6) return '*' * token.length;
  return '${token.substring(0, 2)}${'*' * (token.length - 4)}${token.substring(token.length - 2)}';
}

/// 诊断报告：既可渲染到界面，也可导出成文本。
class DiagReport {
  DiagReport({
    required this.host,
    required this.port,
    required this.token,
    required this.defaultCwd,
    required this.steps,
    required this.startedAt,
    required this.elapsed,
  });

  final String host;
  final int port;
  final String token;
  final String? defaultCwd;
  final List<DiagStep> steps;
  final DateTime startedAt;
  final Duration elapsed;

  bool get allOk => steps.every((step) => step.ok);

  String get headline {
    if (allOk) return I18n.t('ui.669d30fa77');
    final failed = steps.where((step) => !step.ok).toList();
    return failed.isEmpty ? I18n.t('ui.145eaa2097') : I18n.tp('ui.602e8032ea', {'title': failed.first.title});
  }

  /// 导出文本：给「复制」和「系统分享」用同一份，避免两处措辞不一致。
  String toText() {
    final buffer = StringBuffer()
      ..writeln(I18n.t('ui.65b148d3ae'))
      ..writeln(I18n.tp('ui.516289bc09', {'t': startedAt.toIso8601String()}))
      ..writeln(I18n.tp('ui.b5ed9e3f60', {'n': elapsed.inMilliseconds}))
      ..writeln(I18n.tp('ui.6416d2cfda', {'host': host, 'port': port}))
      ..writeln('token：${maskToken(token)}')
      ..writeln('${I18n.t('ui.9d2957f54f')}${defaultCwd ?? I18n.t('ui.cb8fd1da6d')}')
      ..writeln('');
    for (final step in steps) {
      buffer.writeln('${step.ok ? I18n.t('ui.17513e53f2') : I18n.t('ui.7b0b07b98f')} ${step.title}：${step.detail}');
      if (step.hint != null) buffer.writeln(I18n.tp('ui.62e1c6d089', {'hint': step.hint}));
    }
    return buffer.toString();
  }
}

/// 跑一次完整诊断。任何一步失败都继续往下走（诊断页的价值就在于把失败摊开）。
Future<DiagReport> runDiagnosis({
  required String host,
  required int port,
  required String token,
  String? defaultCwd,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final started = DateTime.now();
  final steps = <DiagStep>[];

  // ① DNS / 地址解析
  String? resolved;
  try {
    final lookup = await InternetAddress.lookup(host).timeout(timeout);
    if (lookup.isEmpty) throw SocketException('no address');
    resolved = lookup.first.address;
    steps.add(DiagStep(
      title: I18n.t('ui.7c27423840'),
      ok: true,
      detail: resolved == host ? host : '$host → $resolved',
    ));
  } catch (error) {
    final explained = explainFailure(error);
    steps.add(DiagStep(
      title: I18n.t('ui.7c27423840'),
      ok: false,
      detail: explained.reason,
      hint: explained.hint,
    ));
  }

  // ② 端口可达性（纯 TCP，不涉及 HTTP 与鉴权）
  Duration? tcpMs;
  if (resolved != null) {
    final startedTcp = DateTime.now();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      tcpMs = DateTime.now().difference(startedTcp);
      socket.destroy();
      steps.add(DiagStep(
        title: I18n.t('ui.0cd14773ed'),
        ok: true,
        detail: I18n.tp('ui.9fa43bc9a3', {'host': host, 'port': port, 'n': tcpMs.inMilliseconds}),
      ));
    } catch (error) {
      final explained = explainFailure(error);
      steps.add(DiagStep(
        title: I18n.t('ui.0cd14773ed'),
        ok: false,
        detail: explained.reason,
        hint: explained.hint,
      ));
    }
  } else {
    steps.add(DiagStep(
      title: I18n.t('ui.0cd14773ed'),
      ok: false,
      detail: I18n.t('ui.469c7e631a'),
      hint: I18n.t('ui.391fd0df8f'),
    ));
  }

  // ③ 健康检查 + 延迟（3 次取最快与平均）
  if (tcpMs != null) {
    final samples = <int>[];
    String piVersion = '?';
    var active = 0;
    String? failure;
    for (var i = 0; i < 3; i += 1) {
      final client = HttpClient()..connectionTimeout = timeout;
      final startedHealth = DateTime.now();
      try {
        final request =
            await client.getUrl(Uri.parse('http://$host:$port/api/health')).timeout(timeout);
        final response = await request.close().timeout(timeout);
        final text = await utf8.decoder.bind(response).join();
        samples.add(DateTime.now().difference(startedHealth).inMilliseconds);
        final json = jsonDecode(text);
        if (json is Map) {
          piVersion = json['piVersion'] as String? ?? piVersion;
          active = (json['activeSessions'] as num?)?.toInt() ?? active;
        }
      } catch (error) {
        failure ??= explainFailure(error).reason;
      } finally {
        client.close(force: true);
      }
    }
    if (samples.isEmpty) {
      steps.add(DiagStep(
        title: I18n.t('ui.a0da7db9e8'),
        ok: false,
        detail: failure ?? I18n.t('ui.6c95da9a4c'),
        hint: I18n.t('ui.032d279244'),
      ));
    } else {
      samples.sort();
      final fastest = samples.first;
      final average = samples.reduce((a, b) => a + b) ~/ samples.length;
      steps.add(DiagStep(
        title: I18n.t('ui.eabef5aeca'),
        ok: true,
        detail: I18n.tp('ui.0f83db566b', {'f': fastest, 'a': average}),
      ));
      steps.add(DiagStep(
        title: I18n.t('ui.62f64d669e'),
        ok: true,
        detail: I18n.tp('ui.5c1455e056', {'v': piVersion, 'n': active}),
      ));
    }

    // ④ 鉴权（只有带 token 打一个受保护接口才知道对不对）
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('http://$host:$port/api/sessions'))
          .timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      if (response.statusCode == 200) {
        steps.add(DiagStep(
          title: I18n.t('ui.1abcfdd7b6'),
          ok: true,
          detail: I18n.t('ui.97d3f39246'),
        ));
      } else if (response.statusCode == 401) {
        steps.add(DiagStep(
          title: I18n.t('ui.1abcfdd7b6'),
          ok: false,
          detail: I18n.t('ui.0264d45a05'),
          hint: I18n.t('ui.eebdd18b00'),
        ));
      } else {
        steps.add(DiagStep(
          title: I18n.t('ui.1abcfdd7b6'),
          ok: false,
          detail: 'HTTP ${response.statusCode}',
          hint: I18n.t('ui.75c322d9f5'),
        ));
      }
    } catch (error) {
      final explained = explainFailure(error);
      steps.add(DiagStep(
        title: I18n.t('ui.1abcfdd7b6'),
        ok: false,
        detail: explained.reason,
        hint: explained.hint,
      ));
    } finally {
      client.close(force: true);
    }
  }

  return DiagReport(
    host: host,
    port: port,
    token: token,
    defaultCwd: defaultCwd,
    steps: steps,
    startedAt: started,
    elapsed: DateTime.now().difference(started),
  );
}
