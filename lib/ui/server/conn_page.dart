// 连接配置页。
//
// 原型这里配的是 SSH（主机/密钥/工作区），服务端改成 HTTP 后字段变为：
// 配置名称 / 主机地址 / 端口 / token / 默认工作区。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../server/discovery.dart';
import '../../server/i18n.dart';
import '../../server/server_client.dart';
import '../../server/server_profile.dart';
import '../../server/server_store.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
import 'conn/widgets.dart';
import 'diagnose_page.dart';
import 'conn_edit_page.dart';

class ServerConnPage extends StatefulWidget {
  const ServerConnPage({super.key, required this.store, this.onConnected});

  final ServerStore store;
  final VoidCallback? onConnected;

  @override
  State<ServerConnPage> createState() => _ServerConnPageState();
}

class _ServerConnPageState extends State<ServerConnPage> {
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '30142');
  final _token = TextEditingController();
  final _cwd = TextEditingController();
  /// 备用地址（可选）。留空 = 不启用回落，行为与改动前一致。
  final _fallback = TextEditingController();

  /// 是否走 HTTPS。**显式开关**（原来只能靠在地址栏粘 https:// 或把端口填 443
  /// 隐式触发，用户根本不知道有这回事）。粘贴完整 URL 时仍会自动打开它。
  bool _secure = false;

  List<ServerProfile> _profiles = const [];
  String? _editingId;
  bool _testing = false;

  // 局域网扫描（合同①：不再手输 IP）
  bool _scanning = false;
  List<DiscoveredServer> _found = const [];
  String? _scanNote;

  /// 展开了的分组。key 用 i18n 后的标题字符串（与设置页同一套做法）。
  ///
  /// 初始为空 = **全部分组默认收起**。
  ///
  /// 早前这里是 `{conn.groupQuick}`（快速连接默认展开），理由「它是主路径」。
  /// 但那违背了明确要求「可折叠区块**一律**默认收起」—— 规则就是规则，
  /// 觉得该破例应该先问，而不是自己替用户决定。现已改回全收起。
  final Set<String> _expanded = {};

  /// 威胁模型是否展开（默认收起：它是「要点」不是「正文」）
  bool _showThreat = false;

  /// 远程访问里选的内置隧道类型（`'cloudflare'` / `'ssh'`）。
  ///
  /// 默认 Cloudflare：实测它在国内可达。选 SSH 则走反向隧道那条兜底路线
  ///（零安装，但要求能连到外网中转）。
  String _tunnelPref = 'cloudflare';

  /// 「用你自己的工具」那个地址输入框。
  ///
  /// 不复用表单里的 `_fallback`：那个字段的语义是「出门时的备用地址」
  /// （与主地址配对做回落），而这里是「用 Tailscale / 焦月连 这类工具拿到
  /// 的外网地址」—— 两者只是长得像，填下去的结果也不同（这里会存成
  /// 一条独立连接）。
  final TextEditingController _ownRemote = TextEditingController();

  /// 电脑端两种启动方式，都能一键复制（合同④向导页）
  String? _testResult;
  bool _testOk = false;

  ServerStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
    // 进来就问一次隧道状态：电脑端可能已经用 --tunnel 起好了
    _store.loadRemote();
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _token.dispose();
    _cwd.dispose();
    _fallback.dispose();
    _ownRemote.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profiles = await ServerProfileStore.loadAll();
    final activeId = await ServerProfileStore.loadActiveId();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      final active = profiles.where((p) => p.id == activeId).firstOrNull ??
          profiles.firstOrNull;
      if (active != null) _fill(active);
    });
  }

  void _fill(ServerProfile profile) {
    _editingId = profile.id;
    _name.text = profile.name;
    _host.text = profile.host;
    _port.text = profile.port.toString();
    _token.text = profile.token;
    _cwd.text = profile.defaultCwd ?? '';
    _fallback.text = profile.fallbackHost ?? '';
    _secure = profile.secure;
  }

  ServerProfile _collect() {
    var host = _host.text.trim();
    var portText = _port.text.trim();
    // 以开关为准；粘贴完整 URL 时下面会把它改成 true（那是用户明确表达的意图）
    var secure = _secure;

    // 允许直接粘贴一整条 URL：远程隧道给用户的就是
    // `https://xxx.trycloudflare.com`，逼他自己拆域名和端口既费事又容易错。
    if (host.startsWith('https://') || host.startsWith('http://')) {
      final isHttps = host.startsWith('https://');
      final parsed = Uri.tryParse(host);
      if (parsed != null && parsed.host.isNotEmpty) {
        host = parsed.host;
        portText = parsed.hasPort ? '${parsed.port}' : (isHttps ? '443' : '80');
        secure = isHttps;
      }
    } else if (portText == '443') {
      // 手填 443 也当作 https（不然会拿 http 去打 443 端口，必失败）
      secure = true;
    }

    final port = int.tryParse(portText) ?? (secure ? 443 : 30142);
    final rawName = _name.text.trim();
    return ServerProfile(
      id: _editingId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      // 名字留空时用地址兜底：否则列表里会是一条没名字的记录
      name: rawName.isEmpty
          ? (secure ? host : '$host:$port')
          : rawName,
      host: host,
      port: port,
      token: _token.text.trim(),
      defaultCwd: _cwd.text.trim().isEmpty ? null : _cwd.text.trim(),
      secure: secure,
      fallbackHost: _fallback.text.trim().isEmpty ? null : _fallback.text.trim(),
    );
  }

  Future<void> _test() async {
    final profile = _collect();
    if (profile.host.isEmpty) {
      setState(() {
        _testResult = I18n.t('ui.69ffdd9247');
        _testOk = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });

    // 只探一次健康检查。
    // 之前这里建了个临时 ServerStore 并 connect()，会顺带把 244 条会话
    // 全扫一遍（实测 900ms），测试连接根本不需要这个。
    final probe = ServerClient(
      host: profile.host,
      port: profile.port,
      token: profile.token,
      timeout: kConnectTestTimeout,
    );
    String message;
    var ok = false;
    try {
      final health = await probe.health();
      ok = health.ok;
      message = ok ? I18n.tp('ui.57e6d24d08', {'version': health.piVersion}) : I18n.t('ui.fb58f723f1');
    } on ServerException catch (error) {
      message = error.message;
    } finally {
      await probe.dispose();
    }

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = message;
    });
  }

  Future<void> _saveAndConnect() async {
    final profile = _collect();
    if (profile.host.isEmpty) {
      NeuToast.show(context, message: I18n.t('ui.69ffdd9247'), icon: IconId.warn);
      return;
    }
    final next = [..._profiles.where((p) => p.id != profile.id), profile];
    await ServerProfileStore.saveAll(next);
    await ServerProfileStore.saveActiveId(profile.id);
    if (!mounted) return;
    setState(() {
      _profiles = next;
      _editingId = profile.id;
      // 名字被兜底成地址时，回写输入框，免得输入框仍显示为空
      if (_name.text.trim().isEmpty) _name.text = profile.name;
    });

    await _store.connect(ServerTarget(
      host: profile.host,
      port: profile.port,
      token: profile.token,
      defaultCwd: profile.defaultCwd,
      secure: profile.secure,
      fallbackHost: profile.fallbackHost,
      fallbackPort: profile.fallbackPort,
      fallbackSecure: profile.fallbackSecure,
    ));

    if (!mounted) return;
    if (_store.isConnected) {
      NeuToast.show(context, message: I18n.tp('ui.754e7e0a0b', {'endpoint': profile.endpoint}), icon: IconId.check);
      widget.onConnected?.call();
    } else {
      NeuToast.show(
        context,
        message: _store.errorMessage ?? I18n.t('common.connFailed'),
        icon: IconId.warn,
      );
    }
  }

  Future<void> _delete(ServerProfile profile) async {
    final next = _profiles.where((p) => p.id != profile.id).toList();
    await ServerProfileStore.saveAll(next);
    if (_editingId == profile.id) {
      await ServerProfileStore.saveActiveId(null);
    }
    if (!mounted) return;
    setState(() => _profiles = next);
  }

  /// 扫描局域网里的 pi-yz-server（合同①）
  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _found = const [];
      _scanNote = null;
    });
    final list = await LanDiscovery.scan(onNote: (note) => debugPrint('[scan] $note'));
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _found = list;
      _scanNote = list.isEmpty
          ? I18n.t('ui.04b4da54a3')
          : I18n.tp('ui.7ae8535227', {'n': list.length});
    });
  }

  /// 选中一台被发现的机器：能连就连，需要 token 就走配对码
  /// 扫描结果里点「选中」：能配对就先配对拿 token，然后开子页面把剩下的字段补齐。
  ///
  /// 为什么不再往内联表单里填：那块默认收起，填了用户也看不见；
  /// 而且它没有 token 的任何引导 —— 实测用户在「未开配对窗口」时就是
  /// 「不知道怎么添加 token」。改成子页面后，地址/token 能直接带过去，
  /// 剩下要补的东西旁边就有说明。
  Future<void> _useDiscovered(DiscoveredServer server) async {
    String? pairedToken;
    if (server.pairingOpen) {
      final code = await _askPairCode(server);
      if (code == null || !mounted) return;
      final outcome = await LanDiscovery.pair(
        host: server.host,
        port: server.port,
        code: code,
      );
      if (!mounted) return;
      if (outcome.ok) {
        pairedToken = outcome.token;
        NeuToast.show(context, message: I18n.t('ui.4a3d8c1f0b'), icon: IconId.check);
      } else {
        NeuToast.show(context, message: outcome.message, icon: IconId.warn);
      }
    } else {
      // 配对窗口没开：不再只弹一句「重启服务端」，而是把子页面打开、
      // 并在里面直接给出 token 的三个来源（那就写在那儿）。
      NeuToast.show(context, message: I18n.t('ui.4fa10ed005'), icon: IconId.info);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
    }

    final saved = await _openEditor(
      ServerProfile(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: server.name,
        host: server.host,
        port: server.port,
        token: pairedToken ?? _store.target?.token ?? '',
        secure: false,
      ),
      isNew: true,
    );
    if (saved) widget.onConnected?.call();
  }

  /// 打开配置子页面。返回 true = 已经保存并连上了。
  ///
  /// 页面自己管字段与测试连接；这里只负责把结果写进 store。
  Future<bool> _openEditor(ServerProfile draft, {required bool isNew}) async {
    final result = await Navigator.of(context).push<ServerProfile>(
      MaterialPageRoute(
        builder: (_) => ConnEditPage(
          initial: isNew ? null : draft,
          defaultToken: draft.token,
          draft: isNew ? draft : null,
        ),
      ),
    );
    if (result == null || !mounted) return false;

    // 已存列表以**存储**为准（不能用内存里的 _profiles，它可能还没加载完；
    // 之前拿它当基准就把用户原有的配置覆盖丢过）。
    final stored = await ServerProfileStore.loadAll();
    final base = stored.isNotEmpty ? stored : _profiles;
    final next = [...base.where((p) => p.id != result.id), result];
    await ServerProfileStore.saveAll(next);
    await ServerProfileStore.saveActiveId(result.id);
    if (!mounted) return false;
    setState(() {
      _profiles = next;
      _editingId = result.id;
    });
    await _store.connect(ServerTarget(
      host: result.host,
      port: result.port,
      token: result.token,
      defaultCwd: result.defaultCwd,
      secure: result.secure,
      fallbackHost: result.fallbackHost,
      fallbackPort: result.fallbackPort,
      fallbackSecure: result.fallbackSecure,
    ));
    if (!mounted) return false;
    if (_store.isConnected) {
      NeuToast.show(context,
          message: I18n.tp('ui.e02ef1e216', {'endpoint': result.endpoint}),
          icon: IconId.check);
      return true;
    }
    NeuToast.show(context,
        message: I18n.tp('ui.3550a72e44', {'e': _store.errorMessage ?? I18n.t('ui.31bbcc36d8')}),
        icon: IconId.warn);
    return false;
  }

  /// 配对码输入框：码只在电脑端终端上，所以要用户手输
  Future<String?> _askPairCode(DiscoveredServer server) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.neu.bg,
        title: Text(I18n.t('ui.e2a075395d'),
            style: TextStyle(color: context.neu.fg, fontSize: NeuFonts.heading)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${I18n.t('ui.1d11df355d')}'
              '${I18n.tp('ui.506c0b7cbf', {'name': server.name, 'endpoint': server.endpoint, 'version': server.piVersion})}',
              style: TextStyle(color: context.neu.muted, fontSize: NeuFonts.sub, height: 1.6),
            ),
            const SizedBox(height: NeuSpace.n10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(color: context.neu.fg),
              decoration: InputDecoration(hintText: I18n.t('ui.1483581ee7')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: context.neu.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(I18n.t('ui.e33ff6aad6'), style: TextStyle(color: context.neu.accentInk)),
          ),
        ],
      ),
    );
  }

  /// 一键切换（合同②）：点已保存的机器直接连过去，不用先点「保存并使用」
  Future<void> _switchTo(ServerProfile profile) async {
    _fill(profile);
    setState(() {});
    await ServerProfileStore.saveActiveId(profile.id);
    await _store.connect(ServerTarget(
      host: profile.host,
      port: profile.port,
      token: profile.token,
      defaultCwd: profile.defaultCwd,
      secure: profile.secure,
      fallbackHost: profile.fallbackHost,
      fallbackPort: profile.fallbackPort,
      fallbackSecure: profile.fallbackSecure,
    ));
    if (!mounted) return;
    if (_store.isConnected) {
      NeuToast.show(context, message: I18n.tp('ui.8480b01bc7', {'name': profile.displayName}), icon: IconId.check);
      widget.onConnected?.call();
    } else {
      NeuToast.show(
        context,
        message: _store.errorMessage ?? I18n.t('ui.2d5fbafe5d'),
        icon: IconId.warn,
      );
    }
  }

  /// 打开诊断页（合同③）：把当前表单里的参数带过去
  Future<void> _openDiagnose() async {
    final profile = _collect();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiagnosePage(
          host: profile.host,
          port: profile.port,
          token: profile.token,
          defaultCwd: profile.defaultCwd,
        ),
      ),
    );
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    NeuToast.show(context, message: I18n.tp('ui.eb2ee57cb4', {'label': label}), icon: IconId.check);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n8, NeuSpace.n18, 28),
          children: [
            const ConnPageHeader(),

            // ---- 远程访问（task-18）：不在同一局域网也能连 ----
            RemoteAccessCard(
              store: _store,
              tunnelPref: _tunnelPref,
              ownRemote: _ownRemote,
              showThreat: _showThreat,
              onPickTunnel: (v) => setState(() => _tunnelPref = v),
              onToggleThreat: () => setState(() => _showThreat = !_showThreat),
              onUseAddress: _useRemoteAddress,
              onSaveOwnAddress: _saveOwnAddress,
            ),
            const SizedBox(height: NeuSpace.n14),

            // ---- 快速连接：把「扫一台连上」与「查为什么连不上」归成一组 ---
            // 原来这两个大按钮和「已保存」「手动表单」平铺，看不出主次。
            QuickConnectSection(
              expanded: _expanded.contains(I18n.t('conn.groupQuick')),
              scanning: _scanning,
              onToggle: () => setState(() {
                const k = 'conn.groupQuick';
                if (_expanded.contains(k)) {
                  _expanded.remove(k);
                } else {
                  _expanded.add(k);
                }
              }),
              onScan: _scan,
              onDiagnose: _openDiagnose,
              scanNote: _scanNote,
              found: _found,
              onUseDiscovered: _useDiscovered,
            ),
            SizedBox(height: NeuSpace.n18),

            // ---- 已保存的服务器：整行点=切过去，右边笔/垃圾桶=改/删 ----
            SavedProfilesSection(
              profiles: _profiles,
              editingId: _editingId,
              expanded: _expanded.contains(I18n.t('ui.f8dfedcd8a')),
              onToggle: () => setState(() {
                const k = 'ui.f8dfedcd8a';
                if (_expanded.contains(k)) {
                  _expanded.remove(k);
                } else {
                  _expanded.add(k);
                }
              }),
              onSwitchTo: _switchTo,
              onEdit: _editProfile,
              onDelete: _delete,
              onNew: _newProfile,
            ),

            // ---- 连接动作：测试连不通、保存并连接、进诊断 ----
            // 原来这块叫「手动配置」整块默认收起，但它其实是「连不上时怎么办」的
            // 主入口，收起反而不易找。抽成组件后由页面直接平铺。
            const SizedBox(height: NeuSpace.n16),
            ConnectionActions(
              testResult: _testResult,
              testOk: _testOk,
              testing: _testing,
              onTest: _test,
              onSaveAndConnect: _saveAndConnect,
              onDiagnose: _openDiagnose,
            ),
            const SizedBox(height: NeuSpace.n16),
            // ---- 服务端启动向导（合同④）：命令可一键复制 ----
            ServerStartupGuide(onCopy: _copy),
          ],
        ),
      ),
    );
  }

  /// 发现项副标题里那句「可配对 / 未开配对窗口」。
  /// 抽出来是因为 Dart 的字符串插值里不能再嵌同种引号的三元表达式。
  /// 表单区（「手动配置」那块折叠区）的锚点，用于新增/编辑后滚过去。

  /// 新增一台机器：直接开子页面。
  ///
  /// 以前是「清空内联表单」——但表单在默认收起的折叠区里，点了等于没反应
  /// （用户报的「这两个功能无法使用」就是它）。
  void _newProfile() {
    _openEditor(
      ServerProfile(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: '',
        host: '',
        port: 30142,
        token: _store.target?.token ?? '',
        secure: false,
      ),
      isNew: true,
    );
  }

  /// 编辑已有那条：同样开子页面，把它当前的值带过去。
  void _editProfile(ServerProfile profile) {
    _openEditor(profile, isNew: false);
  }

  /// 滚到表单区。
  ///
  /// 下一帧再滚：`setState` 刚把折叠区展开，它的 `RenderObject` 要到下一帧
  /// 才布局完成，此时 `ensureVisible` 才能算出正确位置（立即调用会滚不到位）。
  /// 一行可复制的命令：整行都能点，免得手指戳不准那个小图标
  /// 把地址存成一条配置。
  ///
  /// [switchTo] = true 时存完立刻连过去（隧道那条路的语义 —— 用户开隧道
  /// 就是为了马上用它）；false 只存不切（「自己的工具」那条路：用户可能只是
  /// 想先记下来，或者手机和电脑还没都装好）。
  ///
  /// token 复用当前已连的那条（用户已经配对过了），不重复问。
  Future<void> _useRemoteAddress(String url, {bool switchTo = true}) async {
    // 裸 `host:port` 补 http:// —— 自备穿透工具（Tailscale / 焦月连 / frp）
    // 给的多半是「本机端口的转发」，没有 TLS 证书；带 scheme 的地址则原样尊重
    //（Cloudflare 隧道给的就是 https）。
    final withScheme = url.contains('://') ? url : 'http://$url';
    final parsed = Uri.tryParse(withScheme);
    if (parsed == null || parsed.host.isEmpty) {
      NeuToast.show(context, message: I18n.tp('ui.3bff752a5d', {'url': url}), icon: IconId.warn);
      return;
    }
    final token = _store.target?.token ?? _token.text.trim();
    if (token.isEmpty) {
      NeuToast.show(context, message: I18n.t('ui.8e72a51181'), icon: IconId.warn);
      return;
    }

    final profile = ServerProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: I18n.tp('ui.e96f1cf9ba', {'host': parsed.host.split('.').first}),
      host: parsed.host,
      port: parsed.hasPort
          ? parsed.port
          : (parsed.scheme == 'https' ? 443 : 80),
      token: token,
      // 有没有 TLS 看地址自己带没带，不替用户猜
      secure: parsed.scheme == 'https',
    );

    // 以**存储里的**列表为基准，而不是内存里的 `_profiles`。
    //
    // `_profiles` 是页面状态：可能还没加载完、也可能落后于别处发起的改动。
    // 拿它当基准去 saveAll，等于用一份可能不完整的快照覆盖存储 ——
    // 实测踩到过：点一次「存成一条连接」，用户原有的局域网配置直接没了
    //（存储里只剩刚存进去的那一条，App 于是只往那个连不上的地址连，
    //  表现就是「局域网连接坏了」）。
    final stored = await ServerProfileStore.loadAll();
    final base = stored.isNotEmpty ? stored : _profiles;
    final next = [...base.where((p) => p.id != profile.id), profile];
    await ServerProfileStore.saveAll(next);
    if (switchTo) {
      await ServerProfileStore.saveActiveId(profile.id);
    }
    if (!mounted) return;
    setState(() {
      _profiles = next;
      _editingId = profile.id;
      _fill(profile);
    });

    // 只存不切：告诉用户存到哪去了，否则他会以为按钮没生效
    if (!switchTo) {
      NeuToast.show(context, message: I18n.t('remote.ownSaved'), icon: IconId.check);
      return;
    }

    await _store.connect(ServerTarget(
      host: profile.host,
      port: profile.port,
      token: profile.token,
      defaultCwd: profile.defaultCwd,
      secure: profile.secure,
      fallbackHost: profile.fallbackHost,
      fallbackPort: profile.fallbackPort,
      fallbackSecure: profile.fallbackSecure,
    ));
    if (!mounted) return;
    if (_store.isConnected) {
      NeuToast.show(context,
          message: I18n.tp('ui.e02ef1e216', {'endpoint': profile.endpoint}), icon: IconId.check);
      widget.onConnected?.call();
    } else {
      NeuToast.show(context,
          message: I18n.tp('ui.3550a72e44', {'e': _store.errorMessage ?? I18n.t('ui.31bbcc36d8')}),
              icon: IconId.warn);
    }
  }

  /// 「远程访问」卡片：开/关隧道 + 地址 + 威胁模型（task-18 合同①②④⑤）
  /// 内置隧道的一个选项行：单选圆点 + 名称 + 一句代价说明。
  ///
  /// 点整行就选中，而不是只让小圆点可点：圆点只有 14dp，手指够不着，
  /// 而这一行本来就该整行是目标。
  /// 「用你自己的工具」：说明 + 地址输入 + 存成连接。
  ///
  /// 为何 App 不代管这类工具：Tailscale 是系统级 VPN，必须在电脑**和**手机
  /// 上各装一个、登录同一账号，App 装不了也点不了。所以这里只做两件事：
  /// 把「先装工具、再拿地址」的顺序讲清楚，以及把地址收下来 —— 地址又长又
  /// 随机，手拄进表单是常态性的失败来源。
  Future<void> _saveOwnAddress(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return;
    // switchTo: false —— 只存成一条连接，不悄悄把当前连接切走。
    // 「要不要改用它」是用户的决定：Tailscale / 皎月连 这类工具常见的情形是
    // 电脑装好了、手机还没装，此时切过去等于把 App 弄成离线。要切的话
    // 「已保存」里有入口，那里点一下就能连。
    await _useRemoteAddress(value, switchTo: false);
    if (!mounted) return;
    setState(() => _ownRemote.clear());
  }


  /// 折叠分组的薄包装，复用 [NeuSection]（三套折叠各写各的正是
  /// 「有的地方点了能收、有的地方点了没反应」的根源）。
}
