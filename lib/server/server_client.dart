// 服务端 HTTP + SSE 客户端。
//
// 用 dart:io 的 HttpClient，不引入 http 包 —— 依赖越少越好，
// 而且 SSE 需要的是"原始字节流"，HttpClient 直接给的就是这个。

import 'dart:async';

import '../services/debug_log.dart';
import 'i18n.dart';

import 'dart:convert';
import 'dart:io';

import 'chat_models.dart';
import 'diagnose.dart';
import 'server_types.dart';

/// 与服务端通信失败
class ServerException implements Exception {
  ServerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 「测试连接」按钮专用的超时。
///
/// 为什么不直接用 [ServerClient] 的默认值：这个按钮只探一次 `/api/health`，
/// 而默认是 30 秒 —— 地址填错的人要对着转圈干等。
///
/// 为什么抽成常量：新增连接页（`conn_edit_page.dart`）与连接页（`conn_page.dart`）
/// 各有一份「测试」，原先一处传了 8 秒、一处没传（两份实现走偏了，
/// E1）。共享同一个值，
/// 以后再改也是改一处。
const Duration kConnectTestTimeout = Duration(seconds: 8);

class ServerClient {
  ServerClient({
    required this.host,
    required this.port,
    required this.token,
    this.timeout = const Duration(seconds: 30),
    this.secure = false,
  });

  final String host;
  final int port;
  final String token;
  final Duration timeout;

  /// 走 HTTPS。远程（Cloudflare quick tunnel 等）必须是 true ——
  /// 明文 HTTP 过公网等于把 token 和对话一起裸奔。
  final bool secure;

  HttpClient? _http;

  HttpClient get _client {
    final existing = _http;
    if (existing != null) return existing;
    final created = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      // SSE 是长连接，空闲回收时间放宽，避免服务端心跳间隔（30s）触发回收
      ..idleTimeout = const Duration(minutes: 10);
    _http = created;
    return created;
  }

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
    scheme: secure ? 'https' : 'http',
    host: host,
    port: port,
    path: path,
    queryParameters: query,
  );

  Future<void> dispose() async {
    _http?.close(force: true);
    _http = null;
  }

  /// 发送一个请求并读取完整 JSON 响应
  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,

    /// 单次请求的超时（安装插件这类会联网的操作要放宽，默认用全局 timeout）
    Duration? timeout,
  }) async {
    final effective = timeout ?? this.timeout;
    // 只记写操作（POST/DELETE/PUT）：GET 里有池/会话轮询，记下来会把 500 条
    // 环形缓冲冲干净，真正要看的连接故障反而被挤出去。
    if (method != 'GET') {
      DebugLog.instance.debug('api', '$method $path');
    }
    final HttpClientRequest request;
    try {
      request = await _client
          .openUrl(method, _uri(path, query))
          .timeout(effective);
    } on TimeoutException {
      DebugLog.instance.error(
        'api',
        '$method $path 超时（${effective.inSeconds}s）',
      );
      final explained = explainFailure(TimeoutException('$host:$port'));
      throw ServerException(
        '${explained.reason}（$host:$port）→ ${explained.hint}',
      );
    } on SocketException catch (error) {
      DebugLog.instance.error('api', '$method $path 连接失败：${error.message}');
      // 具体原因交给诊断层翻译（端口没人监听 / 域名解析不了 / 网络不可达）：
      // 只回一句「无法连接」用户没法下手（合同⑤）
      final explained = explainFailure(error);
      throw ServerException(
        '${explained.reason}（$host:$port）→ ${explained.hint}',
      );
    }

    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = bytes.length;
      request.add(bytes);
    }

    // 这三段都要包：超时不只可能发生在「打开连接」时，也可能发生在
    // 「等服务端响应」与「读正文」这两段。只包第一段的话，后两段的 TimeoutException
    // 会**裸着漏出去** —— 而调用方（server_store）到处是 `on ServerException`，
    // 漏出去的异常表现为「没有提示的失败」，比报错更难查。
    final HttpClientResponse response;
    final String text;
    try {
      response = await request.close().timeout(effective);
      text = await response.transform(utf8.decoder).join().timeout(effective);
    } on TimeoutException {
      DebugLog.instance.error(
        'api',
        '$method $path 读响应超时（${effective.inSeconds}s）',
      );
      final explained = explainFailure(TimeoutException('$host:$port'));
      throw ServerException(
        '${explained.reason}（$host:$port）→ ${explained.hint}',
      );
    } on SocketException catch (error) {
      DebugLog.instance.error('api', '$method $path 连接中断：${error.message}');
      final explained = explainFailure(error);
      throw ServerException(
        '${explained.reason}（$host:$port）→ ${explained.hint}',
      );
    } on HttpException catch (error) {
      // 收发过程中连接被掐断（服务端退了、网断了，或调用方自己断开 —— 删会话、
      // 切会话、断网都会碰到）。**必须也包成 ServerException**：调用方
      // （server_store）到处都是 `on ServerException`，漏出去的 HttpException
      // 会变成未捕获的异步异常（写 server_store 测试时被这一点绊住才发现）。
      // 文案复用「连不上」那套：对用户来说「连不上」与「连了又断」要做的事一样。
      DebugLog.instance.error('api', '$method $path 连接被中断：${error.message}');
      final explained = explainFailure(SocketException(error.message));
      throw ServerException(
        '${explained.reason}（$host:$port）→ ${explained.hint}',
      );
    }

    if (response.statusCode != 200) {
      final explained = _explainStatus(response.statusCode, text);
      DebugLog.instance.error(
        'api',
        '$method $path → ${response.statusCode} $explained',
      );
      throw ServerException(explained, statusCode: response.statusCode);
    }
    if (text.isEmpty) return const {};
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, dynamic>() : {'data': decoded};
  }

  /// 取原始字节（图片 / PDF 预览用）。
  /// 不能走 `_json`：它把响应当 UTF-8 正文解析，二进制会变成乱码。
  Future<RawFileData> rawFile(String filePath) async {
    final HttpClientRequest request;
    try {
      request = await _client
          .openUrl('GET', _uri('/api/file/raw', {'path': filePath}))
          .timeout(timeout);
    } on TimeoutException {
      final explained = explainFailure(TimeoutException('$host:$port'));
      throw ServerException(
        '${explained.reason}（$host:$port）→ ${explained.hint}',
      );
    } on SocketException catch (error) {
      // 具体原因交给诊断层翻译（端口没人监听 / 域名解析不了 / 网络不可达）：
      // 只回一句「无法连接」用户没法下手（合同⑤）
      final explained = explainFailure(error);
      throw ServerException(
        '${explained.reason}（$host:$port）→ ${explained.hint}',
      );
    }
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close().timeout(timeout);
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    if (response.statusCode != 200) {
      throw ServerException(
        _explainStatus(
          response.statusCode,
          utf8.decode(bytes, allowMalformed: true),
        ),
        statusCode: response.statusCode,
      );
    }
    return RawFileData(
      bytes: bytes,
      contentType:
          response.headers.contentType?.mimeType ?? 'application/octet-stream',
      // 服务端把预览类型放在自定义头里（image / pdf / audio / video / text / binary）
      kind: response.headers.value('x-pi-file-kind') ?? 'binary',
    );
  }

  String _explainStatus(int status, String body) {
    if (status == 401) return I18n.t('ui.0264d45a05');
    // 服务端错误正文是给 PC 端看的中文（例：409 的「这条会话正在运行…」）。
    // 直接嵌进手机界面，在英文模式下就会漏中文；正文含中文时丢掉它，退回本地文案。
    final safe = RegExp(r'[\u4e00-\u9fa5]').hasMatch(body) ? '' : body;
    if (status == 404) {
      return safe.isEmpty
          ? I18n.t('ui.588c5be1a0')
          : I18n.tp('ui.07d8607b07', {'body': safe});
    }
    return I18n.tp('ui.a1a3b0d3e1', {
      'code': status,
      'body': safe.isEmpty ? I18n.t('ui.ee85679cef') : safe,
    });
  }

  // ==================== 接口 ====================

  /// 健康检查（无需认证，也用来验证地址是否可达）
  /// 健康检查。
  ///
  /// 之所以开放 `timeout`：回落（[ServerStore.connect]）需要在主地址不可达时
  /// **快速**切到备用地址。用默认的 30 秒的话，用户出门要盯着「连接中…」半分钟
  /// 才等到回落 —— 那等于回落没做。
  Future<HealthInfo> health({Duration? timeout}) async =>
      HealthInfo.fromJson(await _json('GET', '/api/health', timeout: timeout));

  /// 会话列表
  Future<List<ServerSession>> listSessions({bool refresh = false}) async {
    final json = await _json(
      'GET',
      '/api/sessions',
      query: refresh ? const {'refresh': '1'} : null,
    );
    final list = json['sessions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((item) => ServerSession.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  /// 新建会话，返回会话 id
  Future<String> createSession(String cwd) async {
    final json = await _json('POST', '/api/sessions', body: {'cwd': cwd});
    final id = json['sessionId'] as String?;
    if (id == null) {
      throw ServerException(I18n.tp('ui.27c192ed70', {'json': json}));
    }
    return id;
  }

  /// 删除一条会话。
  ///
  /// 服务端会拒绝删正在跑的那条（409），除非显式 force ——
  /// 「不能误删在跑的」这条规则放在服务端，客户端绕不过去。
  /// 关闭一条活跃会话：把它从服务端的会话池里移出。
  ///
  /// 与 [deleteSession] 的区别是**不删会话文件** —— 用户的原话是
  /// 「下面那个活跃会话应该加一个关闭功能，不然我不跑了也一直显示」，
  /// 他要的是「别再占着列表」，不是「把记录删掉」。
  Future<void> closeLiveSession(String sessionId) async {
    await _json('DELETE', '/api/pool/${Uri.encodeComponent(sessionId)}');
  }

  Future<void> deleteSession(String sessionId, {bool force = false}) async {
    await _json(
      'DELETE',
      '/api/sessions/$sessionId',
      query: force ? const {'force': '1'} : null,
    );
  }

  /// 池里活着的会话（多会话总览）
  Future<List<PoolSession>> pool() async {
    final json = await _json('GET', '/api/pool');
    final list = json['sessions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => PoolSession.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 会话磁盘占用（按工作区分组）
  Future<DiskUsage> diskUsage() async =>
      DiskUsage.fromJson(await _json('GET', '/api/sessions/disk'));

  // ==================== 远程访问隧道（task-18） ====================

  Future<RemoteState> remoteState() async =>
      RemoteState.fromJson(await _json('GET', '/api/remote'));

  /// [prefer] 选走哪条道：`'cloudflare'` / `'ssh'`。
  /// 不传则由服务端自己挑（有 cloudflared 用 Cloudflare，否则退回 SSH）。
  Future<RemoteState> startRemote({String? prefer}) async =>
      RemoteState.fromJson(
        await _json(
          'POST',
          '/api/remote/start',
          body: prefer == null ? null : {'prefer': prefer},
        ),
      );

  /// 一键断开远程入口：关掉隧道后公网再也不通，局域网照常
  Future<RemoteState> stopRemote() async =>
      RemoteState.fromJson(await _json('POST', '/api/remote/stop'));

  // ==================== 文件与 Git（只读） ====================

  /// 列目录。path 省略时用服务端的默认根（会话工作区）。
  Future<DirListing> listFiles({String? path}) async {
    final json = await _json(
      'GET',
      '/api/files',
      query: path == null || path.isEmpty ? null : {'path': path},
    );
    return DirListing.fromJson(json);
  }

  /// 读文本文件
  Future<FileText> readFile(String path) async {
    final json = await _json('GET', '/api/file', query: {'path': path});
    return FileText.fromJson(json);
  }

  /// git status
  Future<GitStatusInfo> gitStatus(String cwd) async {
    final json = await _json('GET', '/api/git/status', query: {'cwd': cwd});
    return GitStatusInfo.fromJson(json);
  }

  /// git diff（不给 path 就是全仓）
  Future<GitDiffInfo> gitDiff(String cwd, {String? path}) async {
    final json = await _json(
      'GET',
      '/api/git/diff',
      query: {'cwd': cwd, if (path != null && path.isNotEmpty) 'path': path},
    );
    return GitDiffInfo.fromJson(json);
  }

  /// @ 引用候选文件
  Future<List<FileRef>> fileIndex(String cwd, String query) async {
    final json = await _json(
      'GET',
      '/api/file-index',
      query: {'cwd': cwd, 'q': query},
    );
    return (json['files'] as List?)
            ?.whereType<Map>()
            .map((e) => FileRef.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  /// MCP 服务器列表（只读）
  Future<List<McpServerInfo>> listMcp(String cwd) async {
    final json = await _json('GET', '/api/mcp', query: {'cwd': cwd});
    return (json['servers'] as List?)
            ?.whereType<Map>()
            .map((e) => McpServerInfo.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  // ==================== Provider 凭据 ====================

  Future<List<CredentialInfo>> listCredentials() async {
    final json = await _json('GET', '/api/credentials');
    return (json['credentials'] as List?)
            ?.whereType<Map>()
            .map((e) => CredentialInfo.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  Future<void> setApiKey(String provider, String apiKey) async {
    await _json(
      'POST',
      '/api/credentials',
      body: {'provider': provider, 'apiKey': apiKey},
    );
  }

  Future<void> removeApiKey(String provider) async {
    await _json('DELETE', '/api/credentials/${Uri.encodeComponent(provider)}');
  }

  // ==================== MCP 服务器（增/改/删） ====================

  /// 新增或覆盖一条 MCP 配置（真的写进 mcp.json）
  Future<void> upsertMcp({
    required String name,
    required String scope,
    required Map<String, dynamic> config,
    String? cwd,
  }) async {
    await _json(
      'POST',
      '/api/mcp',
      body: {
        'name': name,
        'scope': scope,
        if (cwd != null && cwd.isNotEmpty) 'cwd': cwd,
        'config': config,
      },
    );
  }

  Future<void> removeMcp(
    String name, {
    required String scope,
    String? cwd,
  }) async {
    await _json(
      'DELETE',
      '/api/mcp/${Uri.encodeComponent(name)}',
      query: {'scope': scope, if (cwd != null && cwd.isNotEmpty) 'cwd': cwd},
    );
  }

  Future<void> setMcpEnabled(
    String name, {
    required String scope,
    required bool enabled,
    String? cwd,
  }) async {
    await _json(
      'PATCH',
      '/api/mcp/${Uri.encodeComponent(name)}',
      query: {'scope': scope, if (cwd != null && cwd.isNotEmpty) 'cwd': cwd},
      body: {'enabled': enabled},
    );
  }

  // ==================== 文件上传 / worktree ====================

  /// 把一份字节写进工作区（base64 传输，服务端会校验目录白名单）
  Future<Map<String, dynamic>> uploadFile({
    required String dir,
    required String name,
    required String base64,
    bool overwrite = false,
  }) async {
    return _json(
      'POST',
      '/api/upload',
      body: {
        'dir': dir,
        'name': name,
        'base64': base64,
        'overwrite': overwrite,
      },
    );
  }

  Future<Map<String, dynamic>> listWorktrees(String cwd) async {
    return _json('GET', '/api/git/worktrees', query: {'cwd': cwd});
  }

  Future<Map<String, dynamic>> addWorktree({
    required String cwd,
    required String dir,
    String? branch,
    String? base,
  }) async {
    return _json(
      'POST',
      '/api/git/worktrees',
      body: {
        'cwd': cwd,
        'dir': dir,
        if (branch != null && branch.isNotEmpty) 'branch': branch,
        if (base != null && base.isNotEmpty) 'base': base,
      },
    );
  }

  Future<Map<String, dynamic>> removeWorktree({
    required String cwd,
    required String dir,
    bool force = false,
  }) async {
    return _json(
      'DELETE',
      '/api/git/worktrees',
      query: {'cwd': cwd, 'path': dir, if (force) 'force': '1'},
    );
  }

  // ==================== Provider 登录 ====================

  Future<List<ProviderInfo>> listProviders() async {
    final json = await _json('GET', '/api/providers');
    return (json['providers'] as List?)
            ?.whereType<Map>()
            .map((e) => ProviderInfo.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  /// 起一次登录，返回任务 id
  Future<String?> startLogin(String provider, String type) async {
    final json = await _json(
      'POST',
      '/api/login',
      body: {'provider': provider, 'type': type},
    );
    return json['id'] as String?;
  }

  Future<LoginStatus> loginStatus(String taskId) async {
    final json = await _json('GET', '/api/login/$taskId');
    return LoginStatus.fromJson(json);
  }

  Future<bool> answerLogin(String taskId, String answer) async {
    final json = await _json(
      'POST',
      '/api/login/$taskId',
      body: {'answer': answer},
    );
    return json['accepted'] as bool? ?? false;
  }

  Future<void> cancelLogin(String taskId) async {
    await _json('POST', '/api/login/$taskId', body: {'cancel': true});
  }

  Future<void> logoutProvider(String provider) async {
    await _json('POST', '/api/logout', body: {'provider': provider});
  }

  // ==================== pi 包（插件）====================

  Future<Map<String, dynamic>> listPackages(String cwd) async {
    return _json('GET', '/api/packages', query: {'cwd': cwd});
  }

  /// action: install | remove | update（装/卸会联网，可能几十秒）
  Future<Map<String, dynamic>> packageAction({
    required String action,
    String? source,
    bool local = false,
    String? cwd,
  }) async {
    return _json(
      'POST',
      '/api/packages',
      body: {
        'action': action,
        if (source != null && source.isNotEmpty) 'source': source,
        'local': local,
        if (cwd != null && cwd.isNotEmpty) 'cwd': cwd,
      },
      timeout: const Duration(minutes: 5),
    );
  }

  // ==================== 会话无关的配置信息 ====================
  // 没有打开的会话时也能读：AI 配置页因此不会整页空白。

  Future<List<ModelInfo>> configModels(String cwd) async {
    final json = await _json('GET', '/api/config/models', query: {'cwd': cwd});
    return (json['models'] as List?)
            ?.whereType<Map>()
            .map((e) => ModelInfo.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  /// 返回 [等级列表, 当前等级, 模型 provider/id]
  Future<(List<String>, String?, String)> configThinkingLevels(
    String cwd,
    String? provider,
    String? modelId,
  ) async {
    final json = await _json(
      'GET',
      '/api/config/thinking-levels',
      query: {
        'cwd': cwd,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        if (modelId != null && modelId.isNotEmpty) 'model': modelId,
      },
    );
    final levels =
        (json['levels'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final current = json['current'] as String?;
    final model = json['model'] as Map?;
    final label = model == null
        ? ''
        : '${model['provider'] ?? ''}/${model['id'] ?? ''}';
    return (levels, current, label);
  }

  Future<List<SlashCommand>> configCommands(String cwd) async {
    final json = await _json(
      'GET',
      '/api/config/commands',
      query: {'cwd': cwd},
    );
    return (json['commands'] as List?)
            ?.whereType<Map>()
            .map((e) => SlashCommand.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const [];
  }

  /// 一条会话的逐轮用量（服务端从落盘 JSONL 算）
  Future<SessionUsage> readSessionUsage(String sessionId) async {
    final json = await _json('GET', '/api/sessions/$sessionId/usage');
    return SessionUsage.fromJson(json);
  }

  /// 本轮改动速览（改了哪些文件、增删多少行）
  ///
  /// 会话里一条 edit/write 都没有时会返回空表（不是错误）——
  /// 404 只有会话本身找不到才出现，那种情况返回 null 让界面不显示这一条。
  Future<TurnSummary?> readTurnSummary(String sessionId) async {
    try {
      final json = await _json('GET', '/api/sessions/$sessionId/turn-summary');
      return TurnSummary.fromJson(json);
    } on ServerException catch (error) {
      // 404 = 会话不在了（被归档/删了）；其余错误照常抛，别把真问题吞掉
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  /// 跨会话用量（今天 / 本月 / 按 provider）
  Future<UsageSummary> readUsageSummary() async {
    final json = await _json(
      'GET',
      '/api/usage',
      timeout: const Duration(seconds: 30),
    );
    return UsageSummary.fromJson(json);
  }

  /// pi 侧「新会话默认模型」（读 / 写 settings.json 的两个字段）
  Future<Map<String, dynamic>> readDefaultModel() async =>
      await _json('GET', '/api/config/default-model');

  Future<Map<String, dynamic>> writeDefaultModel(
    String provider,
    String modelId,
  ) async => await _json(
    'POST',
    '/api/config/default-model',
    body: {'provider': provider, 'modelId': modelId},
  );

  /// 会话导出：Markdown 文本（App 内预览 / 复制 / 存到手机）
  Future<ExportMarkdown> exportMarkdown(String sessionId) async {
    final json = await _json(
      'GET',
      '/api/sessions/$sessionId/export',
      query: {'format': 'markdown'},
    );
    return ExportMarkdown(
      markdown: json['markdown'] as String? ?? '',
      filename: json['filename'] as String? ?? 'session.md',
      title: json['title'] as String? ?? '',
    );
  }

  /// 会话导出：写到服务端磁盘（HTML + JSONL），返回路径
  Future<Map<String, String>> exportToServer(String sessionId) async {
    final json = await _json('POST', '/api/sessions/$sessionId/export');
    final errors =
        (json['errors'] as List?)?.whereType<String>().toList() ?? const [];
    if (errors.isNotEmpty) throw ServerException(errors.join('；'));
    return {
      'html': json['html'] as String? ?? '',
      'jsonl': json['jsonl'] as String? ?? '',
    };
  }

  /// 会话导出：HTML 全文（用于在 App 里另存）
  Future<String> exportHtml(String sessionId) async {
    final json = await _json(
      'GET',
      '/api/sessions/$sessionId/export',
      query: {'format': 'html'},
    );
    return json['html'] as String? ?? '';
  }

  /// 发送一条命令
  Future<CommandResponse> command(
    String sessionId,
    Map<String, dynamic> command,
  ) async {
    final json = await _json(
      'POST',
      '/api/sessions/$sessionId/command',
      body: command,
    );
    return CommandResponse.fromJson(json);
  }

  /// 回应扩展对话框
  Future<bool> respondToUi(
    String sessionId,
    String requestId,
    Map<String, dynamic> response,
  ) async {
    final json = await _json(
      'POST',
      '/api/sessions/$sessionId/ui-response',
      body: {'id': requestId, ...response},
    );
    return json['accepted'] as bool? ?? false;
  }

  // ==================== SSE ====================

  /// 订阅会话事件流。取消订阅即关闭连接。
  ///
  /// 事件帧格式（服务端约定）：
  ///   event: snapshot   ← 连接建立后的第一帧，含完整状态与历史消息
  ///   event: message    ← 增量事件
  ///   event: status     ← 连接阶段提示（connecting / error / shutdown）
  ///   : ping            ← 心跳注释行，会被忽略
  Stream<ServerEvent> events(String sessionId) async* {
    final HttpClientRequest request;
    try {
      request = await _client.openUrl(
        'GET',
        _uri('/api/sessions/$sessionId/events'),
      );
    } on SocketException catch (error) {
      // 具体原因交给诊断层翻译（端口没人监听 / 域名解析不了 / 网络不可达）：
      // 只回一句「无法连接」用户没法下手（合同⑤）
      final explained = explainFailure(error);
      throw ServerException(
        '${explained.reason}（$host:$port）→ ${explained.hint}',
      );
    }

    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

    final response = await request.close();
    if (response.statusCode != 200) {
      final text = await response.transform(utf8.decoder).join();
      throw ServerException(
        _explainStatus(response.statusCode, text),
        statusCode: response.statusCode,
      );
    }

    // 关键：utf8.decoder 作为流式转换器会保留不完整的多字节字符，
    // 所以中文字符跨 chunk 时不会被切坏（逐块 decode 就会出乱码）
    var buffer = '';
    await for (final chunk in response.transform(utf8.decoder)) {
      buffer += chunk;
      var boundary = buffer.indexOf('\n\n');
      while (boundary != -1) {
        final frame = buffer.substring(0, boundary);
        buffer = buffer.substring(boundary + 2);
        final event = _parseFrame(frame);
        if (event != null) yield event;
        boundary = buffer.indexOf('\n\n');
      }
    }
  }

  static ServerEvent? _parseFrame(String frame) {
    String? name;
    final dataLines = <String>[];
    for (final line in frame.split('\n')) {
      if (line.startsWith('event:')) {
        name = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
      // 以 ':' 开头的是注释（心跳），直接忽略
    }
    if (dataLines.isEmpty) return null;
    try {
      final decoded = jsonDecode(dataLines.join('\n'));
      if (decoded is! Map) return null;
      return ServerEvent(name ?? 'message', decoded.cast<String, dynamic>());
    } catch (_) {
      return null; // 坏帧丢弃，不让整条流断掉
    }
  }
}
