// AI 配置页：模型、思考等级、技能与扩展命令、MCP 服务器。
//
// 为什么单独做一页：这些是「配置 pi 自己」而不是「和 pi 说话」，
// 混在对话里会让 /model 这类操作和聊天记录纠缠在一起。
// 数据来源：模型/思考等级/命令都走会话命令（需要有一条打开的会话），
// MCP 走服务端的只读接口。

import 'package:flutter/material.dart';

import '../../server/chat_models.dart';
import '../../server/i18n.dart';
import '../../server/server_store.dart';
import '../../server/server_types.dart';
import '../neu_section.dart';
import 'config/model_section.dart';
import 'config/thinking_section.dart';
import 'config/credential_section.dart';
import 'config/skill_section.dart';
import 'config/widgets.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
import 'provider_login_sheet.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key, required this.store});

  final ServerStore store;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  List<ModelInfo> _models = const [];
  List<String> _thinkingLevels = const [];
  /// 展开了的分组。key 用 i18n 后的标题字符串 ——
  /// 与设置页、连接页同一套做法（三套各写各的正是"有的能收有的不能"的根源）。
  /// 初始为空 = **全部默认收起**：AI 配置页的分组多、每组都长，全展开时
  /// 一屏塞不下、也看不出层次（用户原话："比较乱，该折叠的折叠"）。
  /// 初始为空 = **全部分组默认收起**（明确要求「一律默认收起」）。
  ///
  /// 早前这里默认展开「模型」，理由：全收起时整页只剩标题、看起来像空页（实测）。
  /// 但那个理由不成立 —— 该修的是「让人知道可以点开」，不是破例把一组展开。
  /// 所以另外加了一行提示（见 build 顶部），分组仍然全收起。
  final Set<String> _expanded = {};

  List<McpServerInfo> _mcp = const [];
  List<CredentialInfo> _credentials = const [];
  List<PiPackageInfo> _packages = const [];
  List<PackageUpdateInfo> _updates = const [];
  String? _packageUpdateError;
  bool _packagesBusy = false;
  bool _loading = true;

  ServerStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 重试：先把连接补上（断线时 store 没有客户端，直接重载只会再失败一次），再重新读配置。
  Future<void> _retry() async {
    await _store.ensureConnected();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // 没打开会话时，“技能 / 内置命令”会走会话无关接口拿 —— 先补一次。
    await _store.refreshCommandsIfNeeded();
    final models = await _store.availableModels();
    final levels = await _store.availableThinkingLevels();
    final mcp = await _store.mcpServers();
    final credentials = await _store.credentials();
    final (packages, updates, updateError) = await _store.packages();
    if (!mounted) return;
    setState(() {
      _models = models;
      _thinkingLevels = levels;
      _mcp = mcp;
      _credentials = credentials;
      _packages = packages;
      _updates = updates;
      _packageUpdateError = updateError;
      _loading = false;
    });
  }

  /// 登录 Provider（API Key 向导 / OAuth）：走服务端的登录任务
  Future<void> _loginProvider() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProviderLoginSheet(
        store: _store,
        onLoggedIn: () {
          // 登录完凭据变了，回来重读
          if (mounted) _load();
        },
      ),
    );
    if (mounted) await _load();
  }

  /// 添加一个 API Key（会真实写进 pi 的凭据库）
  Future<void> _addCredential() async {
    final providerController = TextEditingController();
    final keyController = TextEditingController();
    final t = context.neu;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: t.bg,
          title: Text(I18n.t('ui.8a31d0428f'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(t, providerController, I18n.t('ui.91e8ba4966')),
              const SizedBox(height: NeuSpace.n10),
              _dialogField(t, keyController, 'API Key'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(I18n.t('common.save'), style: TextStyle(color: t.accentInk)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      final provider = providerController.text.trim();
      final key = keyController.text.trim();
      if (provider.isEmpty || key.isEmpty) {
        NeuToast.show(context, message: I18n.t('ui.f78ec7c874'), icon: IconId.warn);
        return;
      }
      final saved = await _store.setApiKey(provider, key);
      if (saved) await _load();
    } finally {
      providerController.dispose();
      keyController.dispose();
    }
  }

  /// MCP 条目的第二行：类型 · target · args
  /// （写成方法而不是嵌套的三元插值：嵌套同种引号在这种字符串里容易把解析器带沟里）
  String _mcpSubtitle(McpServerInfo info) {
    // 中文注释：不只是把 kind 翻一遍，还说明这类 MCP 是干什么的、参数在哪（合同要求“含义/参数/副作用”）
    final isLocal = info.kind == 'local' || info.kind == 'stdio';
    final parts = <String>[
      isLocal ? I18n.t('ui.91977f0940') : I18n.t('ui.1aef0e1818'),
    ];
    if (info.target.isNotEmpty) parts.add(info.target);
    if (info.args.isNotEmpty) parts.add(info.args);
    if (info.description.isNotEmpty) parts.add(info.description);
    if (!info.enabled) parts.add(I18n.t('ui.69b0f68457'));
    return parts.join('\n');
  }

  /// 添加（或覆盖）一个 MCP 服务器。
  /// 两种形态：本地 stdio（command + args）/ 远程 http（url）—— 对应 pi 的 mcp.json。
  Future<void> _addMcpServer() async {
    final nameController = TextEditingController();
    final targetController = TextEditingController();
    final argsController = TextEditingController();
    final descController = TextEditingController();
    var scope = 'user';
    var kind = 'stdio';
    final t = context.neu;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            backgroundColor: t.bg,
            title: Text(I18n.t('ui.3bd1c146b5'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dialogField(t, nameController, I18n.t('ui.5a47c238fb')),
                  SizedBox(height: NeuSpace.n12),
                  ChoiceRow(I18n.t('ui.4705b88497'), ['user', 'project'], scope, (value) {
                    setDialogState(() => scope = value);
                  }, labels: {'user': I18n.t('ui.7b79313922'), 'project': I18n.t('ui.98a5faeeaf')}),
                  SizedBox(height: NeuSpace.n12),
                  ChoiceRow(I18n.t('ui.226b091218'), ['stdio', 'http'], kind, (value) {
                    setDialogState(() => kind = value);
                  }, labels: {'stdio': I18n.t('ui.904333d474'), 'http': I18n.t('ui.f40bb45c68')}),
                  SizedBox(height: NeuSpace.n12),
                  _dialogField(
                    t,
                    targetController,
                    kind == 'stdio' ? I18n.t('ui.c2cad6ac24') : 'url（https://…/mcp）',
                  ),
                  if (kind == 'stdio') ...[
                    SizedBox(height: NeuSpace.n10),
                    _dialogField(t, argsController, I18n.t('ui.f8d73b6d3b')),
                  ],
                  SizedBox(height: NeuSpace.n10),
                  _dialogField(t, descController, I18n.t('ui.a9f32d22fd')),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(I18n.t('common.save'), style: TextStyle(color: t.accentInk)),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;

      final name = nameController.text.trim();
      if (name.isEmpty) {
        NeuToast.show(context, message: I18n.t('ui.e20009713c'), icon: IconId.warn);
        return;
      }
      final target = targetController.text.trim();
      if (target.isEmpty) {
        NeuToast.show(context,
            message: kind == 'stdio' ? I18n.t('ui.079283b6b1') : I18n.t('ui.61d5eeff77'), icon: IconId.warn);
        return;
      }
      final config = <String, dynamic>{
        if (kind == 'stdio') 'command': target else 'url': target,
        if (kind == 'stdio' && argsController.text.trim().isNotEmpty)
          'args': argsController.text.trim().split(RegExp(r'\s+')),
        if (descController.text.trim().isNotEmpty) 'description': descController.text.trim(),
      };
      final saved = await _store.saveMcpServer(name: name, scope: scope, config: config);
      if (saved) await _load();
    } finally {
      nameController.dispose();
      targetController.dispose();
      argsController.dispose();
      descController.dispose();
    }
  }

  Future<void> _removeMcpServer(McpServerInfo server) async {
    final t = context.neu;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(I18n.t('ui.269830c1e6'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
        content: Text(
          // ignore: prefer_interpolation_to_compose_strings
          '${I18n.tp('ui.af094ee50d', {
            'scope': server.scope == 'project' ? I18n.t('ui.98a5faeeaf') : I18n.t('ui.7b79313922'),
            'name': server.name,
          })}'
          '${I18n.t('ui.2e8c13741c')}',
          style: TextStyle(color: t.muted, fontSize: NeuFonts.bodyMid, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('common.delete'), style: TextStyle(color: t.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = await _store.removeMcpServer(server.name, scope: server.scope);
    if (removed) await _load();
  }

  /// 一排二选一的 chips（作用域 / 类型）
  Future<void> _removeCredential(String provider) async {
    final t = context.neu;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(I18n.t('ui.db5f3f8829'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
        content: Text(
          I18n.tp('ui.e772a04b44', {'provider': provider}),
          style: TextStyle(color: t.muted, fontSize: NeuFonts.bodyMid, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('common.delete'), style: TextStyle(color: t.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _store.removeApiKey(provider);
    if (ok && mounted) await _load();
  }

  Widget _dialogField(NeuTokens t, TextEditingController controller, String hint) => NeuInset(
        radius: NeuRadii.sm,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12),
        child: TextField(
          controller: controller,
          style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.fg),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted),
            contentPadding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final chat = _store.chat;
            final hasSession = _store.currentSessionId != null;

            return ListView(
              padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n8, NeuSpace.n18, 40),
              children: [
                // 失败要有重试入口，而不是只给一句“读不到”
                if (!_loading &&
                    _models.isEmpty &&
                    _mcp.isEmpty &&
                    _credentials.isEmpty &&
                    _packages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: NeuSpace.n10),
                    child: NeuPressable(
                      onTap: _retry,
                      radius: NeuRadii.sm,
                      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                      child: Row(
                        children: [
                          NeuIcon(IconId.warn, size: 15, color: t.danger),
                          SizedBox(width: NeuSpace.n8),
                          Expanded(
                            child: Text(
                              I18n.t('ui.f28ba9e525'),
                              style: TextStyle(fontSize: NeuFonts.sub, color: t.danger),
                            ),
                          ),
                          Text(I18n.t('common.retry'),
                              style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk)),
                        ],
                      ),
                    ),
                  ),
                Row(
                  children: [
                    NeuPressable(
                      onTap: () => Navigator.of(context).maybePop(),
                      radius: 12,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                        child: NeuIcon(IconId.chevronLeft, size: 16),
                      ),
                    ),
                    SizedBox(width: NeuSpace.n8),
                    Expanded(
                      child: Text(
                        I18n.t('ui.5258ce61e8'),
                        style: TextStyle(
                          fontSize: NeuFonts.pageTitle,
                          fontWeight: FontWeight.w700,
                          color: t.onBg,
                        ),
                      ),
                    ),
                    NeuPressable(
                      onTap: _load,
                      radius: 12,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n12),
                        child: NeuIcon(IconId.sync, size: 16),
                      ),
                    ),
                  ],
                ),

                if (!hasSession)
                  Padding(
                    padding: const EdgeInsets.only(top: NeuSpace.n14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: NeuSpace.n2),
                          child: NeuIcon(IconId.warn, size: 14, color: t.warn),
                        ),
                        SizedBox(width: NeuSpace.n8),
                        Expanded(
                          child: Text(
                            // 这里只在“真正读不到”时提醒：改模型/思考等级要会话做通道，
                            // 扩展命令要会话启动时才注册；其余项都能直接读。 +
                            I18n.t('ui.c32f83502e'),
                            style: TextStyle(fontSize: NeuFonts.small, height: 1.6, color: t.muted),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 分组内容默认收起：AI 配置页分组多、每组都长，全展开看不出层次
              ModelSection(
                chat: chat,
                models: _models,
                loading: _loading,
                store: _store,
                open: _expanded.contains(I18n.t('common.model')),
                onToggle: () => setState(() {
                  final k = I18n.t('common.model');
                  _expanded.contains(k) ? _expanded.remove(k) : _expanded.add(k);
                }),
              ),
                // 分组内容默认收起：AI 配置页分组多、每组都长，全展开看不出层次
              ThinkingSection(
                thinkingLevels: _thinkingLevels,
                store: _store,
                chat: chat,
                open: _expanded.contains(I18n.t('ui.11eead2c33')),
                onToggle: () => setState(() {
                  const k = 'ui.11eead2c33';
                  _expanded.contains(k) ? _expanded.remove(k) : _expanded.add(k);
                }),
              ),
              CredentialSection(
                credentials: _credentials,
                // 增删凭据与登录 provider 要动服务端，留在页面侧
                onRemoveCredential: _removeCredential,
                onLoginProvider: _loginProvider,
                onAddCredential: _addCredential,
                open: _expanded.contains(I18n.t('ui.c4d89641a1')),
                onToggle: () => setState(() {
                  const k = 'ui.c4d89641a1';
                  _expanded.contains(k) ? _expanded.remove(k) : _expanded.add(k);
                }),
              ),
              SkillSection(
                isSectionOpen: _isOpen,
                onToggleSection: _openGroup,
                onRemovePackage: _removePackage,
                onInstallPackage: _installPackageDialog,
                onUpdatePackages: _updatePackages,
                isOpen: _isOpen,
                onOpenGroup: _openGroup,
                onViewSkill: _viewSkill,
                packageUpdateError: _packageUpdateError,
                packages: _packages,
                packagesBusy: _packagesBusy,
                updates: _updates,
                store: _store,
                open: _expanded.contains(I18n.t('ui.a9cec18e05')),
                onToggle: () => setState(() {
                  const k = 'ui.a9cec18e05';
                  _expanded.contains(k) ? _expanded.remove(k) : _expanded.add(k);
                }),
              ),
                _section(t, I18n.t('ui.d7911f414c'), icon: IconId.server),
                if (_expanded.contains(I18n.t('ui.d7911f414c'))) ...[
                NeuRaised(
                  radius: NeuRadii.md,
                  level: NeuLevel.small,
                  padding: const EdgeInsets.all(NeuSpace.n6),
                  child: Column(
                    children: [
                      if (_mcp.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
                          child: Center(
                            child: Text(
                              I18n.t('ui.5ab2668c03'),
                              style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                            ),
                          ),
                        )
                      else
                        for (var i = 0; i < _mcp.length; i++) ...[
                          if (i > 0) Container(height: 1, color: t.border),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n10, vertical: NeuSpace.n8),
                            child: Row(
                              children: [
                                NeuIcon(
                                  _mcp[i].kind == 'remote' ? IconId.download : IconId.server,
                                  size: 15,
                                  color: _mcp[i].enabled ? t.accentInk : t.muted,
                                ),
                                const SizedBox(width: NeuSpace.n10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _mcp[i].name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: NeuFonts.bodySmall,
                                                color: _mcp[i].enabled ? t.fg : t.muted,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: NeuSpace.n6),
                                          Text(
                                            _mcp[i].scope == 'project' ? I18n.t('ui.98a5faeeaf') : I18n.t('ui.7b79313922'),
                                            style: TextStyle(fontSize: NeuFonts.tiny, color: t.muted),
                                          ),
                                          if (!_mcp[i].enabled) ...[
                                            SizedBox(width: NeuSpace.n6),
                                            Text(I18n.t('ui.69b0f68457'),
                                                style: TextStyle(fontSize: NeuFonts.tiny, color: t.warn)),
                                          ],
                                        ],
                                      ),
                                      Text(
                                        _mcpSubtitle(_mcp[i]),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: NeuFonts.badge, color: t.muted, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                                // 启用/停用：pi 侧 enabled:false = 保留条目但不连接
                                NeuPressable(
                                  onTap: () async {
                                    final ok = await _store.setMcpServerEnabled(
                                      _mcp[i].name,
                                      scope: _mcp[i].scope,
                                      enabled: !_mcp[i].enabled,
                                    );
                                    if (ok) await _load();
                                  },
                                  radius: 10,
                                  padding: EdgeInsets.all(NeuSpace.n6),
                                  child: Text(
                                    _mcp[i].enabled ? I18n.t('ui.5c56a88945') : I18n.t('ui.7854b52a88'),
                                    style: TextStyle(fontSize: NeuFonts.badge, color: t.accentInk),
                                  ),
                                ),
                                NeuPressable(
                                  onTap: () => _removeMcpServer(_mcp[i]),
                                  radius: 10,
                                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                                  child: NeuIcon(IconId.trash, size: 14, color: t.danger),
                                ),
                              ],
                            ),
                          ),
                        ],
                      if (_mcp.isNotEmpty) Container(height: 1, color: t.border),
                      NeuPressable(
                        onTap: _addMcpServer,
                        flat: true,
                        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            NeuIcon(IconId.plus, size: 15, color: t.accentInk),
                            SizedBox(width: NeuSpace.n8),
                            Text(I18n.t('ui.3bd1c146b5'),
                                style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// 一行命令/技能；可点时整行可点（技能就是靠这个点开 SKILL.md）
  /// 看一个技能的内容：直接读它的 SKILL.md（路径由服务端在命令列表里给出）
  Future<void> _viewSkill(SlashCommand item) async {
    final path = item.sourcePath;
    if (path == null || path.isEmpty) {
      NeuToast.show(context, message: I18n.t('ui.58fea6ab1a'), icon: IconId.warn);
      return;
    }
    final file = await _store.readFile(path);
    if (!mounted) return;
    if (file == null) return;
    final t = context.neu;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(NeuRadii.lg)),
        ),
        padding: const EdgeInsets.fromLTRB(NeuSpace.n16, NeuSpace.n10, NeuSpace.n16, NeuSpace.n18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(NeuRadii.hairline),
                ),
              ),
            ),
            const SizedBox(height: NeuSpace.n12),
            Text('/${item.name}',
                style: TextStyle(fontSize: NeuFonts.bodyLg, fontWeight: FontWeight.w700, color: t.fg)),
            Text(path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: NeuFonts.micro, color: t.muted)),
            const SizedBox(height: NeuSpace.n10),
            Flexible(
              child: NeuInset(
                radius: NeuRadii.md,
                padding: const EdgeInsets.all(NeuSpace.n12),
                child: SingleChildScrollView(
                  child: Text(
                    file.text,
                    style: TextStyle(
                        fontSize: NeuFonts.small, fontFamily: 'monospace', height: 1.6, color: t.fg),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _installPackageDialog() async {
    final sourceController = TextEditingController();
    var local = false;
    final t = context.neu;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            backgroundColor: t.bg,
            title: Text(I18n.t('ui.00c35d4155'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogField(t, sourceController, I18n.t('ui.ae38520cd9')),
                SizedBox(height: NeuSpace.n12),
                ChoiceRow(I18n.t('ui.df011658c3'), ['user', 'project'], local ? 'project' : 'user',
                    (value) => setDialogState(() => local = value == 'project'),
                    labels: {'user': I18n.t('ui.7b79313922'), 'project': I18n.t('ui.98a5faeeaf')}),
                SizedBox(height: NeuSpace.n8),
                Text(I18n.t('ui.62b8ab7e30'),
                    style: TextStyle(fontSize: NeuFonts.badge, color: t.muted, height: 1.5)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(I18n.t('ui.e655a410ff'), style: TextStyle(color: t.accentInk)),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
      final source = sourceController.text.trim();
      if (source.isEmpty) {
        NeuToast.show(context, message: I18n.t('ui.dc50378aea'), icon: IconId.warn);
        return;
      }
      setState(() => _packagesBusy = true);
      final done = await _store.runPackageAction(action: 'install', source: source, local: local);
      if (!mounted) return;
      setState(() => _packagesBusy = false);
      if (done) await _load();
    } finally {
      sourceController.dispose();
    }
  }

  Future<void> _removePackage(PiPackageInfo item) async {
    final t = context.neu;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(I18n.t('ui.75f7c9f130'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
        content: Text(
          // ignore: prefer_interpolation_to_compose_strings
          '${I18n.tp('ui.ae4cdde650', {'s': item.source})}'
          '${I18n.t('ui.8d63f5a87f')}',
          style: TextStyle(color: t.muted, fontSize: NeuFonts.bodySmall, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('ui.81824cff24'), style: TextStyle(color: t.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _packagesBusy = true);
    final done = await _store.runPackageAction(action: 'remove', source: item.source);
    if (!mounted) return;
    setState(() => _packagesBusy = false);
    if (done) await _load();
  }

  Future<void> _updatePackages() async {
    setState(() => _packagesBusy = true);
    final done = await _store.runPackageAction(action: 'update');
    if (!mounted) return;
    setState(() => _packagesBusy = false);
    if (done) await _load();
  }

  /// 折叠分组标题。视觉与交互复用 [NeuSection]，状态在本页。
  /// 折叠分组。
  ///
  /// [stateKey] 是**展开状态的键**，默认取标题。标题里带可变内容时必须显式给：
  ///「pi 插件（10）」的计数一变标题就变，用标题当键会让展开状态凭空丢失；
  ///更糟的是内容判定若还按固定串写（原来是 `'plugins'`），两边永远对不上 ——
  ///点了箭头会翻转，但内容一个都不显示。
  /// 某个分组是否展开 / 展开它 —— 给抽出去的组件用。
  ///
  /// 为什么只有「开」没有「关」：命令子组（技能/扩展/内置）点标题就是展开，
  /// 收起由外层分组整体控制，所以只需要 add。
  bool _isOpen(String key) => _expanded.contains(key);

  void _openGroup(String key) => setState(() => _expanded.add(key));

  Widget _section(
    NeuTokens t,
    String title, {
    IconId icon = IconId.circle,
    String? summary,
    String? stateKey,
  }) {
    final key = stateKey ?? title;
    final open = _expanded.contains(key);
    return ConfigSection(
      title: title,
      icon: icon,
      summary: summary,
      open: open,
      onToggle: () => setState(() {
        if (open) {
          _expanded.remove(key);
        } else {
          _expanded.add(key);
        }
      }),
    );
  }
}
