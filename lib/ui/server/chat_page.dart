// 对话页。
//
// 结构照设计稿 pi-remote-app.html 的 page-chat：
//   标题栏（agent + 主机 + 状态点）→ 上下文占用条 → 消息流 → 滚动到底 → 输入条
//
// 输入 / 开头时弹出命令建议（数据来自服务端 get_commands，含扩展/技能/内置三类）。

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../server/chat_models.dart';
import '../../server/chat_reducer.dart';
import '../../server/elapsed_index.dart';
import '../../server/i18n.dart';
import '../../server/native_bridge.dart';
import '../../server/server_store.dart';
import '../../server/server_types.dart';
import '../../server/template_store.dart';
import '../../services/key_encoder.dart';
import '../../theme/design_tokens.dart';
import '../../theme/neu.dart';
import '../key_bar.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
import 'activity_view.dart';
import 'export_page.dart';
import 'files_page.dart';
import 'chat/sheets.dart';
import 'chat/widgets.dart';
import 'message_view.dart';
import 'usage_page.dart';

/// 模型胶囊上显示的**短名**。
///
/// 目标：不再出现 `DeepSe…`。它旁边还挤着会话名、状态点和三个按钮，
/// 宽度**必须**给上限；能省的只有名字里那个与型号重复的厂商词 ——
/// `DeepSeek V4.1 Flash` 真正的型号是 `V4.1 Flash`，而 `DeepSeek` 在
/// id（`deepseek-v4.1-flash`）里已经写了一遍。省掉它之后型号能完整显示，
/// 而不是切在既认不出、又像渲染坏了的位置。
///
/// 剥的条件卡得很紧，避免把真正的型号名弄丢：
/// · 名字的第一段（空格之前）要和 id 的第一段一致（忽略大小写）——
///   这条挡掉了 `opencode-go` 这种 provider 名与型号无关的情况，也挡掉了
///   厂商名与型号粘连的写法（`MiniMax-M3` 根本没有空格，不动）；
/// · 剥完剩下的部分必须**还含空格** —— 否则 `Qwen3.8 Flash` 会被剥成
///   `Flash`，反而把型号丢了，那还不如让它截断。
///
/// 放在顶层（而不是 State 的私有方法）是为了能直接写单元测试：
/// 这几条边界（剥 / 不剥）正是最容易写错的地方。
String modelChipLabel(ModelInfo? model) {
  if (model == null) return I18n.t('ui.aa50cded3a');
  final name = model.name.trim();
  final firstSpace = name.indexOf(' ');
  if (firstSpace <= 0) return name;
  final head = name.substring(0, firstSpace);
  final tail = name.substring(firstSpace + 1).trim();
  if (tail.isEmpty || !tail.contains(' ')) return name;
  final idHead = model.id.split(RegExp(r'[-_]')).first;
  if (head.toLowerCase() != idHead.toLowerCase()) return name;
  return tail;
}

class ServerChatPage extends StatefulWidget {
  const ServerChatPage({super.key, required this.store, this.onOpenSessions});

  final ServerStore store;
  final VoidCallback? onOpenSessions;

  @override
  State<ServerChatPage> createState() => _ServerChatPageState();
}

class _ServerChatPageState extends State<ServerChatPage> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  bool _showSuggestions = false;

  /// 是否贴着底部（决定「回到底部」按钮要不要显示）
  bool _atBottom = true;

  /// 滚动进度 0..1。用 ValueNotifier 驱动进度条，
  /// 免得每帧都 setState 重建整个列表。
  final _scrollProgress = ValueNotifier<double>(1);

  /// 标题栏自动收起的滚动阈值（逻辑像素）。
  ///
  /// 40 的来历：标题栏约 44 逻辑高，滚过「差不多它自己一个高度」时，
  /// 用户就已经在读下面的内容了，这时收掉标题栏收益最大；取值更小会在
  /// 刚动一下时就闪收起，更大则几乎要滚半屏才生效、等于没做。
  static const double _headerCollapseAt = 40;

  /// 标题栏是否因滚动而收起：滚过 `_headerCollapseAt` 收起、回到顶部恢复。
  /// （标题栏在本 widget 内，setState 直接生效 —— 不像底部导航栏那样要走全局开关。）
  bool _headerCollapsed = false;

  // ==================== 按键条（手机打不出的那些键） ====================

  /// 按键条是否显示。点输入框左侧的 ⌘ 按钮切换 ——
  /// 用户的原话：那个按钮「本来应该是用来加载手机上无法输出的键盘按键的」。
  bool _keyBarVisible = false;
  bool _keyBarExpanded = false;
  ModifierState _keyMods = const ModifierState();

  /// 发过的消息（最新在前），供 ↑ / ↓ 翻历史。只存内存，不落盘。
  final List<String> _history = [];
  int _historyIndex = -1;

  /// 待发送的图片（拍照/相册选的）—— 发出去后就清空
  final List<({String name, String base64, String mime})> _pendingImages = [];

  /// 常用语 / 快捷模板（本地存，重启保留）
  List<String> _templates = const [];

  /// 误发保护：刚发出去的那条（非空时显示「已发送 · 撤回」条）
  String? _undoText;
  Timer? _undoTimer;

  /// 运行中：本轮开始时间 + 定时拉用量（用落盘时间戳算本轮速度）
  DateTime? _runStartedAt;
  Timer? _usageTimer;

  /// 重点模式（task-21 合同①）：只看对话主干，把思考/工具调用/工具结果收掉。
  /// 长时间跟 agent 干活时，一屏里工具条比正文还多，主干会被冲散。
  bool _focusMode = false;

  /// @ 文件引用：输入 @ 时列出工作区文件
  List<FileRef> _fileRefs = const [];
  bool _showFileRefs = false;
  Timer? _refDebounce;

  ServerStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _input.addListener(_onInputChanged);
    // 滚动要主动监听：以前 _nearBottom 只在 build 时算一次，
    // 而滚动不会触发 build —— 所以「回到底部」按钮时灵时不灵（用户报的就是这个）。
    _scroll.addListener(_onScroll);
    // 常用语是本地存的，启动时读一次（失败也不能影响输入区）
    TemplateStore.instance.load().then((items) {
      if (mounted) setState(() => _templates = items);
    });
    // 内置命令的返回结果回调只挂一次。
    // 放在监听里挂的话，store 每次通知都会重新赋值，而 store 的通知
    // 可能发生在 build 期间，容易触发「build 中改状态」的错误。
    _store.onBuiltinResult = _handleBuiltinResult;
  }

  @override
  void dispose() {
    _refDebounce?.cancel();
    _undoTimer?.cancel();
    _usageTimer?.cancel();
    _store.removeListener(_onStoreChanged);
    _store.onBuiltinResult = null;
    _input.removeListener(_onInputChanged);
    _scroll.removeListener(_onScroll);
    _scrollProgress.dispose();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 运行中每 3 秒按落盘记录重算一次用量。
  ///
  /// 为什么是按落盘：流式过程中的 token 数只能靠字符数猜，会骗人；
  /// 而 assistant 条目一旦落盘，output 与时间戳就是准的 —— 用它算本轮速度。
  void _syncUsagePolling() {
    // 这个方法是**在 store 的通知回调里**被调用的，所以里面任何会同步 notify 的调用
    // 都会重入：loadSessionUsage() 第一行就是 loadingUsage=true + _notify()，
    // 于是 _onStoreChanged → _syncUsagePolling → loadSessionUsage → _notify → … 无限递归。
    // 实测后果是 App 卡死（ANR「输入 25 秒没被消费」）、主线程 512 层栈、113% CPU、内存涨到 3GB。
    // 因此：①先把定时器装上（它是这个分支的重入闸门）②再拉数据。
    final running = _store.chat.isRunning;
    if (running && _usageTimer == null) {
      _runStartedAt = DateTime.now();
      _usageTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!_store.chat.isRunning) return;
        _store.loadSessionUsage();
      });
      setState(() {});
      _store.loadSessionUsage();
    } else if (!running && _usageTimer != null) {
      _usageTimer?.cancel();
      _usageTimer = null;
      _runStartedAt = null;
      setState(() {});
      // 闸门已清空后再拉数据（同上面的重入理由）
      // 跑完再拉一次，拿到最后一轮的准确数字
      _store.loadSessionUsage();
      // 顺带数一遍本轮改了哪些文件（从 JSONL 里数，不猜）
      _store.loadTurnSummary();
    }
  }

  void _onStoreChanged() {
    _syncUsagePolling();
    // 换会话时把输入框换成该会话的草稿（草稿存在 store 里，切 tab / 切页也不丢）
    final sid = _store.currentSessionId;
    if (sid != _draftSessionId) {
      // 换会话：这条速览也得跟着换
      _store.loadTurnSummary();
      _draftSessionId = sid;
      final draft = _store.draftFor(sid);
      if (draft != _input.text) {
        _input.text = draft;
        _input.selection = TextSelection.collapsed(offset: draft.length);
      }
    }
    if (_atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    }
    _maybeShowUiDialog();
  }

  // ==================== 扩展对话框 ====================
  //
  // 扩展可以随时弹对话框（ctx.ui.select / confirm / input / editor），
  // 服务端会把它作为 extension_ui_request 事件推过来。
  // 不把这些请求展示出来并回传结果的话，扩展会一直等到超时 ——
  // 这正是「/汉化 这类扩展命令没反应」的原因。

  bool _uiDialogOpen = false;

  void _maybeShowUiDialog() {
    if (_uiDialogOpen || !mounted) return;
    final pending = _store.uiRequests;
    if (pending.isEmpty) return;

    final request = pending.first;
    _uiDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _uiDialogOpen = false;
        return;
      }
      await _showUiDialog(request);
      _uiDialogOpen = false;
      _maybeShowUiDialog(); // 可能还排着下一个
    });
  }

  Future<void> _showUiDialog(UiRequest request) async {
    switch (request.method) {
      case 'select':
        final picked = await _askSelect(request);
        await _store.respondUi(
          request.id,
          picked == null ? {'cancelled': true} : {'value': picked},
        );
      case 'confirm':
        final confirmed = await _askConfirm(request);
        await _store.respondUi(
          request.id,
          confirmed == null ? {'cancelled': true} : {'confirmed': confirmed},
        );
      case 'input':
        final text = await _askText(
          title: request.title ?? I18n.t('common.input'),
          placeholder: request.placeholder,
          multiline: false,
        );
        await _store.respondUi(
          request.id,
          text == null ? {'cancelled': true} : {'value': text},
        );
      case 'editor':
        final text = await _askText(
          title: request.title ?? I18n.t('ui.95b351c862'),
          prefill: request.prefill,
          multiline: true,
        );
        await _store.respondUi(
          request.id,
          text == null ? {'cancelled': true} : {'value': text},
        );
      default:
        // 未知类型直接取消：宁可扩展提前退出，也不要它干等
        await _store.respondUi(request.id, {'cancelled': true});
    }
  }

  /// 选择：底部面板列表（手机上比中间弹窗好点）
  Future<String?> _askSelect(UiRequest request) async {
    return showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = sheetContext.neu;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(NeuRadii.lg),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, NeuSpace.n24),
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
              SizedBox(height: NeuSpace.n14),
              Text(
                request.title ?? I18n.t('ui.708c9d6d2a'),
                style: TextStyle(
                  fontSize: NeuFonts.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: t.onBg,
                ),
              ),
              if (request.message != null && request.message!.isNotEmpty) ...[
                const SizedBox(height: NeuSpace.n4),
                Text(
                  request.message!,
                  style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                ),
              ],
              const SizedBox(height: NeuSpace.n14),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: request.options.length,
                  itemBuilder: (_, index) {
                    final option = request.options[index];
                    return NeuPressable(
                      onTap: () => Navigator.of(sheetContext).pop(option),
                      flat: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NeuSpace.n14,
                        vertical: NeuSpace.n12,
                      ),
                      margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                      child: Text(
                        option,
                        style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 确认：居中弹窗（默认焦点在「取消」，避免误点确认）
  Future<bool?> _askConfirm(UiRequest request) async {
    final t = context.neu;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(
          request.title ?? I18n.t('ui.e83a256e4f'),
          style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle),
        ),
        content: Text(
          request.message ?? '',
          style: TextStyle(color: t.muted, fontSize: NeuFonts.bodyMid, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('common.ok'), style: TextStyle(color: t.accentInk)),
          ),
        ],
      ),
    );
  }

  /// 文本输入 / 多行编辑
  Future<String?> _askText({
    required String title,
    String? placeholder,
    String? prefill,
    required bool multiline,
  }) async {
    final controller = TextEditingController(text: prefill ?? '');
    final t = context.neu;
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: t.bg,
          title: Text(title, style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
          content: NeuInset(
            radius: NeuRadii.sm,
            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12),
            child: TextField(
              controller: controller,
              autofocus: true,
              minLines: multiline ? 4 : 1,
              maxLines: multiline ? 10 : 1,
              style: TextStyle(fontSize: NeuFonts.bodyTight, color: t.fg),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: placeholder,
                hintStyle: TextStyle(fontSize: NeuFonts.bodySmall, color: t.muted),
                contentPadding: const EdgeInsets.symmetric(vertical: NeuSpace.n12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(I18n.t('common.ok'), style: TextStyle(color: t.accentInk)),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  /// 内置命令执行完毕（服务端在 data.builtin 里给出结果）
  void _handleBuiltinResult(Map<String, dynamic> builtin) {
    if (!mounted) return;
    final kind = builtin['kind'] as String?;
    if (kind == 'text') {
      NeuToast.show(
        context,
        message: builtin['text'] as String? ?? '',
        icon: IconId.info,
      );
    } else if (kind == 'picker') {
      showPickerSheet(context, _store, builtin);
    } else if (kind == 'data') {
      final title = builtin['title'] as String? ?? I18n.t('ui.0d83078816');
      showDataSheet(context, title, builtin['data']);
    }
  }

  /// 内置命令返回的结构化数据（会话统计、分支树等）。
  ///
  /// 之前这里只弹一句「N 项」，等于没显示 —— /session 统计的内容全丢了。
  /// 把结构化数据排成可读的键值行
  /// 草稿归属的会话 id：用来判断什么时候该把输入框换成另一条会话的草稿
  String? _draftSessionId;

  void _onInputChanged() {
    final text = _input.text;
    // 草稿实时存进 store：切 tab / 切页 / 退回列表都不会丢（页面本身也不再被销毁）
    _store.saveDraft(_store.currentSessionId, text);
    final shouldShow = text.startsWith('/') && !text.contains('\n');
    // 没打开会话时 store.commands 可能是空的（以前就是这样，导致输入 / 什么也看不到），
    // 这里补一次「会话无关」的命令清单：技能 / 模板 / 内置命令。
    if (shouldShow) _store.refreshCommandsIfNeeded();
    if (shouldShow != _showSuggestions) {
      setState(() => _showSuggestions = shouldShow);
    } else if (shouldShow) {
      setState(() {});
    }
    _syncFileRefs(text);
  }

  /// 输入里最后一个 @ 后面还没打空格时，当作文件引用查询（带防抖）
  void _syncFileRefs(String text) {
    final match = RegExp(r'@([^\s@]*)$').firstMatch(text);
    if (match == null) {
      _refDebounce?.cancel();
      if (_showFileRefs) setState(() => _showFileRefs = false);
      return;
    }
    final query = match.group(1) ?? '';
    _refDebounce?.cancel();
    _refDebounce = Timer(NeuMotion.base, () async {
      final refs = await _store.fileRefs(query);
      if (!mounted) return;
      setState(() {
        _fileRefs = refs.take(20).toList();
        _showFileRefs = _fileRefs.isNotEmpty;
      });
    });
  }

  /// 选中一个文件：把尾部的 @query 换成 @相对路径
  void _applyFileRef(FileRef ref) {
    final text = _input.text;
    final replaced = text.replaceFirst(
      RegExp(r'@([^\s@]*)$'),
      '@${ref.relative} ',
    );
    _input.text = replaced;
    _input.selection = TextSelection.collapsed(offset: replaced.length);
    setState(() {
      _showFileRefs = false;
      _fileRefs = const [];
    });
    _inputFocus.requestFocus();
  }

  /// 滚动监听：维护「是否贴底」与进度条两个状态。
  ///
  /// 判定留 80px 容差（手指滑出一点点不算离开底部），
  /// 否则在底部附近轻微拖动时按钮会疯狂闪烁。
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final max = position.maxScrollExtent;
    final atBottom = max <= 0 || (max - position.pixels) < 80;
    _scrollProgress.value = max <= 0
        ? 1
        : (position.pixels / max).clamp(0.0, 1.0);
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
    final collapsed = position.pixels > _headerCollapseAt;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    unawaited(_scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: NeuMotion.base,
      curve: Curves.easeOut,
    ));
  }

  /// 在当前工作区新开一条会话。
  ///
  /// 标题栏那个 + 就是这个意思：不跳去选工作区，直接在正在聊的这个目录下开新的。
  Future<void> _newSessionInCurrentWorkspace() async {
    final cwd = _store.chat.cwd.isNotEmpty
        ? _store.chat.cwd
        : (_store.target?.defaultCwd ?? '');
    if (cwd.isEmpty) {
      NeuToast.show(
        context,
        message: I18n.t('ui.0a50893ad0'),
        icon: IconId.warn,
      );
      return;
    }
    final id = await _store.createSession(cwd);
    if (!mounted) return;
    if (id == null) {
      NeuToast.show(
        context,
        message: _store.lastError ?? I18n.t('ui.96a6a6ca0f'),
        icon: IconId.warn,
      );
      return;
    }
    NeuToast.show(context, message: I18n.t('ui.b244d633d4'), icon: IconId.check);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final images = [
      for (final image in _pendingImages)
        {'type': 'image', 'data': image.base64, 'mimeType': image.mime},
    ];
    // 只有图片没有文字也允许：拍张报错截图直接发，是最常见的用法
    if (text.isEmpty && images.isEmpty) return;

    _input.clear();
    setState(() {
      _showSuggestions = false;
      _pendingImages.clear();
    });

    // 运行中发消息必须指定 streamingBehavior，
    // 否则 pi 会直接拒绝（"must specify whether to steer or follow up"）。
    // 输入框提示的是「可输入以插话」，所以用 steer。
    final ok = await _store.sendPrompt(
      text,
      streamingBehavior: _store.chat.isRunning ? 'steer' : null,
      images: images.isEmpty ? null : images,
    );
    if (!mounted) return;

    if (!ok) {
      // 失败要把文字还给用户，不然白打一串字（实测发失败时输入框已经清了）
      if (text.isNotEmpty) _setInput(text);
      NeuToast.show(
        context,
        message: _store.lastError ?? I18n.t('ui.9ca6a3440e'),
        icon: IconId.warn,
      );
      return;
    }

    // 记住发过的内容，供按键条的 ↑ / ↓ 翻历史
    _history.insert(0, text);
    if (_history.length > 50) _history.removeLast();
    _historyIndex = -1;

    // 误发保护：发出去后的几秒内可撤回。
    // 撤回 = 中断刚起的那一轮 + 把文字放回输入框；
    // 说清楚一点：**已经写进会话历史的那条不会消失**（真要回退得走分支树，
    // 那是任务⑨的事），所以这里不假装它是「删除」。
    // 误发保护：发出去后 6 秒内可以撤回。
    //
    // 为什么不用 toast 里的行动按钮：实测在设备上那个 action 点不到
    // （SnackBarAction 的命中区与我们的自动化/手势区对不上），
    // 而「误发保护」这种东西必须真的能点到。改成输入框上方的一条，
    // 整条都是按钮，手指不会点空。
    _undoText = text;
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _undoText = null);
    });
    setState(() {});
    _scrollToBottom();
  }

  /// 撤回：中断刚起的那一轮 + 把文字放回输入框。
  ///
  /// 说清楚一点：**已经写进会话历史的那条不会消失**
  /// （真要回退得走分支树 / 编辑重发，那是任务⑨的事），所以不假装它是删除。
  void _undoLastSend() {
    final text = _undoText;
    _undoTimer?.cancel();
    setState(() => _undoText = null);
    if (_store.chat.isRunning) _store.abort();
    if (text != null && text.isNotEmpty) _setInput(text);
    NeuToast.show(
      context,
      message: I18n.t('ui.59afc7c239'),
      icon: IconId.warn,
    );
  }

  Widget _buildUndoBar(NeuTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n4, NeuSpace.n18, 0),
      child: NeuPressable(
        onTap: _undoLastSend,
        radius: 10,
        flat: true,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
        child: Row(
          children: [
            NeuIcon(IconId.check, size: 14, color: t.accentInk),
            SizedBox(width: NeuSpace.n8),
            Expanded(
              child: Text(I18n.t('ui.93d159228b'), style: TextStyle(fontSize: NeuFonts.sub, color: t.fg)),
            ),
            Text(I18n.t('ui.2305051ed0'), style: TextStyle(fontSize: NeuFonts.sub, color: t.accentInk)),
            const SizedBox(width: NeuSpace.n4),
            NeuIcon(IconId.close, size: 13, color: t.accentInk),
          ],
        ),
      ),
    );
  }

  // ==================== 按键条的动作 ====================

  void _toggleKeyBar() {
    setState(() {
      _keyBarVisible = !_keyBarVisible;
      if (!_keyBarVisible) _keyBarExpanded = false;
    });
  }

  /// 命令面板（按键条里的「命令」键与手打 / 都走这里）
  void _openCommandPanel() {
    _store.refreshCommandsIfNeeded();
    _setInput('/');
    setState(() => _showSuggestions = true);
    _inputFocus.requestFocus();
  }

  void _setInput(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  /// 把按键条发来的终端转义序列还原成「按了哪个键」。
  ///
  /// 为什么要还原：按键条是终端时代写的，`onKey` 给的是转义字节；
  /// 而我们的通道是 pi（一个 agent，不是终端），转义字节本身没有意义。
  /// 所以序列只在 App 里被解释成动作，**绝不原样发给会话**。
  String _decodeKey(String seq) {
    if (seq == KeyEncoder.esc) return 'esc';
    if (seq == KeyEncoder.tab) return 'tab';
    if (seq == KeyEncoder.shiftTab) return 'shift-tab';
    if (seq == '\x1b[Z') return 'shift-tab';
    if (seq == '\x03' || seq == KeyEncoder.ctrlLetter('c')) return 'ctrl-c';
    if (seq == '\r' || seq == '\n') return 'enter';
    // CSI 序列：ESC [ 参数? 终结符 —— 参数可能带修饰键（如 1;5A = Ctrl+↑）
    final m = RegExp(r'^\x1b\[(?:(\d+)(?:;(\d+))?)?([A-Za-z~])$')
        .firstMatch(seq);
    if (m == null) return '';
    final tail = m.group(3)!;
    return switch (tail) {
      'A' => 'up',
      'B' => 'down',
      'C' => 'right',
      'D' => 'left',
      'H' => 'home',
      'F' => 'end',
      'Z' => 'shift-tab',
      '~' => switch (m.group(1)) {
        '1' => 'home',
        '3' => 'delete',
        '4' => 'end',
        '5' => 'page-up',
        '6' => 'page-down',
        _ => '',
      },
      _ => '',
    };
  }

  void _onKeyBarKey(String seq) {
    final key = _decodeKey(seq);
    if (key == 'esc') {
      // Esc 三级退让：先收面板 → 再中断任务 → 最后清输入
      if (_showSuggestions || _showFileRefs) {
        setState(() {
          _showSuggestions = false;
          _showFileRefs = false;
        });
      } else if (_store.chat.isRunning) {
        _store.abort();
      } else if (_input.text.isNotEmpty) {
        _setInput('');
      }
      return;
    }
    if (key == 'ctrl-c') {
      if (_store.chat.isRunning) _store.abort();
      return;
    }
    if (key == 'tab' || key == 'shift-tab') {
      _completeTopSuggestion();
      return;
    }
    if (key == 'up') {
      _historyPrev();
      return;
    }
    if (key == 'down') {
      _historyNext();
      return;
    }
    if (key == 'left') {
      _moveCursor(-1);
      return;
    }
    if (key == 'right') {
      _moveCursor(1);
      return;
    }
    if (key == 'home') {
      _input.selection = const TextSelection.collapsed(offset: 0);
      return;
    }
    if (key == 'end') {
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      return;
    }
    if (key == 'delete') {
      _deleteForward();
      return;
    }
    if (key == 'page-up') {
      _pageScroll(up: true);
      return;
    }
    if (key == 'page-down') {
      _pageScroll(up: false);
      return;
    }
    if (key == 'enter') _send();
  }

  /// Tab：把当前匹配到的第一条命令 / 文件填进输入框
  void _completeTopSuggestion() {
    if (_showSuggestions && _matchingCommands.isNotEmpty) {
      _applyCommand(_matchingCommands.first);
      return;
    }
    if (_showFileRefs && _fileRefs.isNotEmpty) {
      _applyFileRef(_fileRefs.first);
      return;
    }
    if (_input.text.startsWith('/')) {
      setState(() => _showSuggestions = true);
    }
  }

  void _historyPrev() {
    if (_history.isEmpty) return;
    _historyIndex = (_historyIndex + 1).clamp(0, _history.length - 1);
    _setInput(_history[_historyIndex]);
  }

  void _historyNext() {
    if (_historyIndex <= 0) {
      _historyIndex = -1;
      _setInput('');
      return;
    }
    _historyIndex -= 1;
    _setInput(_history[_historyIndex]);
  }

  void _moveCursor(int delta) {
    final sel = _input.selection;
    final base = sel.isValid ? sel.end : _input.text.length;
    final next = (base + delta).clamp(0, _input.text.length);
    _input.selection = TextSelection.collapsed(offset: next);
  }

  void _deleteForward() {
    final sel = _input.selection;
    final pos = sel.isValid ? sel.end : _input.text.length;
    final text = _input.text;
    if (pos >= text.length) return;
    _setInput(text.substring(0, pos) + text.substring(pos + 1));
    _input.selection = TextSelection.collapsed(offset: pos);
  }

  /// 翻页：按视口高度滚，不按像素拍脑袋
  void _pageScroll({required bool up}) {
    if (!_scroll.hasClients) return;
    final delta = _scroll.position.viewportDimension * 0.85;
    final target = (_scroll.position.pixels + (up ? -delta : delta)).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: NeuMotion.base,
      curve: Curves.easeOut,
    );
  }

  /// 内置命令返回的选择器（模型、思考等级）
  /// 输入框内容匹配到的命令
  ///
  /// 不再 take(12)：命令总数是几十条（内置 + 扩展 + 技能 + 模板），
  /// 截断到 12 条会让第 13 条以后永远选不到，底部计数也是假的。
  /// 面板本身能滑，全给出来。
  List<SlashCommand> get _matchingCommands {
    final text = _input.text;
    if (!text.startsWith('/')) return const [];
    final query = text.substring(1).split(' ').first.toLowerCase();
    return _store.commands
        .where((c) => query.isEmpty || c.name.toLowerCase().contains(query))
        .toList();
  }

  void _applyCommand(SlashCommand command) {
    _input.text = '/${command.name} ';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    setState(() => _showSuggestions = false);
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.neu;
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final chat = _store.chat;
        return PopScope(
          // 手机上返回键应该先收起命令面板，而不是直接把 App 退掉
          // （实测：面板打开时按返回，直接退到了系统设置页）
          canPop: !_showSuggestions,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _showSuggestions) {
              setState(() => _showSuggestions = false);
            }
          },
          child: Column(
            children: [
              // 滚动时标题栏自动收起（省约 44 逻辑高），回到顶部自动恢复
              if (!_headerCollapsed) _buildHeader(t, chat),
              // 活动条只在「跑着」或「有待确认」时占行：
              // 空闲时它显示「你好 · 空闲 · 本轮 N 次工具调用」，信息量低却照样
              // 吃掉约 37 逻辑高。入口没丢 —— 点标题栏的会话名就能打开活动视图。
              if (chat.isRunning || _store.uiRequests.any((r) => r.needsResponse))
                ChatActivityBar(store: _store, chat: chat),
              // 离线缓存提示：有缓存时界面不空，但必须说清楚「你看到的是旧的」
              if (_store.cacheShownAt != null) OfflineBanner(store: _store),
              Expanded(
                child: Stack(
                  children: [
                    if (_store.loadingSession && chat.messages.isEmpty)
                      ChatLoading(store: _store)
                    else if (_store.lastError != null && chat.messages.isEmpty)
                      // 会话没拉起来：说清楚 + 给一条重试的路
                      _buildLoadFailed(t)
                    else if (chat.messages.isEmpty)
                      ChatEmptyState(store: _store)
                    else
                      Builder(
                        builder: (context) {
                          // 重点模式只过滤**渲染**，不动 chat.messages ——
                          // 过滤掉数据会让「加载更早」「本轮耗时」这些基于相邻消息的
                          // 计算跟着变，模式一开关数字就跳。
                          final visible = _focusMode
                              ? chat.messages
                                    .where(
                                      (m) =>
                                          m.isUser ||
                                          (!m.isToolResult &&
                                              m.toolCalls.isEmpty &&
                                              m.thinking.trim().isEmpty &&
                                              m.text.trim().isNotEmpty),
                                    )
                                    .toList()
                              : chat.messages;
                          final elapsedMap = _elapsed.of(chat);
                          return ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(NeuSpace.n14, NeuSpace.n10, NeuSpace.n14, NeuSpace.n10),
                            // 列表顶部多一格：还有更早的消息时放「加载更早」
                            itemCount:
                                visible.length + (chat.historyHasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (chat.historyHasMore && index == 0) {
                                return LoadMoreRow(store: _store, chat: chat);
                              }
                              final message =
                                  visible[chat.historyHasMore
                                      ? index - 1
                                      : index];
                              final tile = MessageTile(
                                // 必须给 key：否则 ListView 复用 widget 时，
                                // 上一条消息的「思考展开/工具展开」状态会串到这一条上
                                key: ValueKey<String>(message.key),
                                message: message,
                                elapsed: elapsedMap[message.key],
                                toolRun: chat.toolRunOf(message.toolCallId),
                                runOf: chat.toolRunOf,
                                onQuote: _quoteText,
                                onEditResend: _editResend,
                              );
                              // 横滑用户消息＝把这条拉回输入框改写再发（左滑右滑都认，
                              // 手机上不用记住方向是哪个）。只对用户消息开放：拉回自己的话才有意义。
                              if (!message.isUser ||
                                  message.text.trim().isEmpty) {
                                return tile;
                              }
                              return GestureDetector(
                                onHorizontalDragEnd: (details) {
                                  final velocity = details.primaryVelocity ?? 0;
                                  if (velocity.abs() < 260) return;
                                  _editResend(message.text);
                                },
                                child: tile,
                              );
                            },
                          );
                        },
                      ),
                    // 顶部细进度条：列表能滚的时候常驻，一眼看出读到哪儿了。
                    // 以前根本没有进度条，只有一个时灵时不灵的回底按钮。
                    if (chat.messages.isNotEmpty)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ValueListenableBuilder<double>(
                          valueListenable: _scrollProgress,
                          builder: (context, value, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: value.clamp(0.02, 1.0),
                              child: Container(
                                height: 2.5,
                                decoration: BoxDecoration(
                                  color: t.accentInk.withValues(alpha: 0.55),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!_atBottom)
                      Positioned(
                        right: 16,
                        bottom: 12,
                        child: NeuPressable(
                          onTap: _scrollToBottom,
                          radius: 20,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: NeuSpace.n11, vertical: NeuSpace.n11),
                            child: NeuIcon(IconId.chevronDown, size: 18),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (chat.notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NeuSpace.n18,
                    vertical: NeuSpace.n4,
                  ),
                  child: Row(
                    children: [
                      NeuIcon(IconId.spinner, size: 13, color: t.muted),
                      const SizedBox(width: NeuSpace.n6),
                      Expanded(
                        child: Text(
                          chat.notice!,
                          style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              if (chat.queuedSteering > 0 || chat.queuedFollowUp > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n4, NeuSpace.n18, NeuSpace.n2),
                  child: Row(
                    children: [
                      NeuIcon(IconId.info, size: 13, color: t.accentInk),
                      SizedBox(width: NeuSpace.n6),
                      Expanded(
                        child: Text(
                          I18n.tp('ui.ae9a52e8c8', {'a': chat.queuedSteering, 'b': chat.queuedFollowUp}),
                          style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                        ),
                      ),
                      NeuPressable(
                        onTap: () => _store.runCommand({
                          'id': 'cq${DateTime.now().microsecondsSinceEpoch}',
                          'type': 'clear_queue',
                        }),
                        radius: 10,
                        padding: const EdgeInsets.symmetric(
                          horizontal: NeuSpace.n10,
                          vertical: NeuSpace.n6,
                        ),
                        child: Text(
                          I18n.t('common.clear'),
                          style: TextStyle(fontSize: NeuFonts.small, color: t.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_showSuggestions) _buildSuggestions(t, _matchingCommands),
              if (_showFileRefs) _buildFileRefs(t),
              // 按键条放在输入框上方、参与布局（不是浮层）：
              // 既不遮挡输入框，也不遮消息
              if (_pendingImages.isNotEmpty) _buildPendingImages(t),
              // 误发保护：发送后的几秒里给一条看得见、点得到的「撤回」
              if (_undoText != null) _buildUndoBar(t),
              if (_keyBarVisible)
                NeuKeyBar(
                  visible: _keyBarVisible,
                  expanded: _keyBarExpanded,
                  onExpandedChanged: (v) => setState(() => _keyBarExpanded = v),
                  onVisibleChanged: (v) => setState(() => _keyBarVisible = v),
                  modifiers: _keyMods,
                  onModifiersChanged: (m) => setState(() => _keyMods = m),
                  onKey: _onKeyBarKey,
                  onCommands: _openCommandPanel,
                  onEnter: _send,
                  // 聊天通道是 pi（agent），修饰键组合除了 Ctrl+C 都没有语义，
                  // 留着那一行只会骗人，所以隐藏
                  showModifiers: false,
                ),
              // 本轮速览 + 继续/再来一次：只在「真的有东西要看」时出现。
              // 之前是「没在跑 + 有消息」就常驻，空闲时白占约 40 逻辑高 ——
              // 而「继续」这件事在输入框发一句话同样能做到，不值得常占一行。
              if (!chat.isRunning && _turnFooterWorthShowing(chat))
                _buildTurnFooter(t, chat),
              _buildComposer(t, chat),
            ],
          ),
        );
      },
    );
  }

  /// 每条消息与「前一条**有时间的**消息」之间的间隔（带缓存，见 `ElapsedIndex`）。
  ///
  /// 为什么按相邻消息算而不是按轮：一轮里思考、工具调用、回复是好几条消息，
  /// 用「轮」只能给出整轮总时长；按相邻条给的是**每一步花了多久**，
  /// 卡在哪一步一眼能看出来（task-21 合同①）。
  ///
  /// **为什么要缓存**：这个索引原来在 `build()` 里无条件重算 —— 每帧遍历全部
  /// 消息。会话上千条时，连流式输出期间的每一帧都在主 isolate 上跑上千次循环。
  /// 输入只有 `(key, timestamp)`，列表不变结果必然不变，没有重算的理由。
  final _elapsed = ElapsedIndex();

  /// 停靠在标题栏下的实时活动条（task-14）：一眼看清 agent 在干什么。
  ///
  /// 空会话且没在跑时不占地方；其余情况都显示 —— 「结束态」本身也是信息
  /// （合同④：空态与结束态都要明确）。
  Widget _buildHeader(NeuTokens t, ChatReducer chat) {
    final connected = _store.isConnected;
    return Padding(
      // 垂直 8 → 5：标题栏已并成一行，上下再多留就是白占竖向空间
      padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n5, NeuSpace.n12, NeuSpace.n5),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NeuRadii.chip),
              gradient: NeuDecorations.raisedGradient(t),
              boxShadow: NeuShadows.raiseSm(t),
            ),
            alignment: Alignment.center,
            child: Text(
              'p',
              style: TextStyle(fontWeight: FontWeight.w700, color: t.accentInk),
            ),
          ),
          const SizedBox(width: NeuSpace.n10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 会话名与地址都要能收缩：右侧还有分享/详情/新建三个按钮，
                    // 不收缩时长会话名会把地址挤到按钮底下（看起来像被遮住）。
                    Flexible(
                      // 会话名可点：打开实时活动视图。
                      // 活动条空闲时不再占行（见 build 里的条件），入口落在这里 ——
                      // 省空间不能把入口弄丢。
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showActivitySheet(context, _store),
                        child: Text(
                          // 会话名可能是空串（用户没命名）：只判 null 标题栏会空一块
                          // （实测被挤成「p ● 模型」），空串也要回落到默认名
                          (chat.sessionName ?? '').trim().isEmpty
                              ? 'pi agent'
                              : chat.sessionName!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: NeuFonts.bodyLg,
                            fontWeight: FontWeight.w700,
                            color: t.onBg,
                          ),
                        ),
                      ),
                    ),
                    // 地址胶囊从标题栏拿掉：一行里要塞下「会话名 + 地址 + 状态点 +
                    // 模型 + 四个按钮」，谁都不够宽（实测会话名和地址一起被挤成 0）。
                    // 连的是哪台机器，活动条和连接页都能看到，这里让位给会话名。
                    const SizedBox(width: NeuSpace.n6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connected ? t.success : t.muted,
                      ),
                    ),
                    const SizedBox(width: NeuSpace.n6),
                    // 会话内一键切模型/思考等级：不用离开会话，也不用记命令
                    _buildModelChip(t, chat),
                    if (chat.isRunning) ...[
                      const SizedBox(width: NeuSpace.n6),
                      LiveSpeed(store: _store, runStartedAt: _runStartedAt),
                    ],
                  ],
                ),
              ],
            ),
          ),
          NeuPressable(
            // 分享这条回复（⑩）：走系统分享面板。
            // 放在头部而不是只藏在消息菜单里 —— 手机上「把这段发给同事」
            // 是高频动作，值得一个一眼可见的入口。
            onTap: _shareLastAnswer,
            radius: 14,
            child: const Padding(
              padding: EdgeInsets.all(NeuSpace.n11),
              child: NeuIcon(IconId.share, size: 18),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          NeuPressable(
            onTap: _showSessionInfo,
            radius: 14,
            child: const Padding(
              padding: EdgeInsets.all(NeuSpace.n11),
              child: NeuIcon(IconId.info, size: 18),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          NeuPressable(
            onTap: _newSessionInCurrentWorkspace,
            radius: 14,
            child: const Padding(
              padding: EdgeInsets.all(NeuSpace.n11),
              child: NeuIcon(IconId.plus, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  /// 分享最后一条 agent 回复的正文（走系统分享面板）。
  ///
  /// 只分享**正文**，不带工具调用与思考 —— 那些是过程，不是结论，
  /// 发给别人只会让对方困惑；要完整会话用导出。
  Future<void> _shareLastAnswer() async {
    String text = '';
    for (final message in _store.chat.messages.reversed) {
      if (!message.isUser && message.text.trim().isNotEmpty) {
        text = message.text.trim();
        break;
      }
    }
    if (text.isEmpty) {
      NeuToast.show(context, message: I18n.t('ui.814d5316b2'), icon: IconId.info);
      return;
    }
    final ok = await NativeBridge.shareText(
      text: text,
      subject: 'pi agent · ${_store.chat.sessionName ?? I18n.t('ui.7914a459b5')}',
    );
    if (!mounted) return;
    NeuToast.show(
      context,
      message: ok ? I18n.t('ui.06a3c99161') : I18n.t('ui.56ed8b49c3'),
      icon: ok ? IconId.share : IconId.warn,
    );
  }

  /// 运行中的实时用量：本轮速度（按落盘时间戳算）+ 已跑时长。
  ///
  /// 明确标「落盘」：流式途中还没落盘时，这里显示的是**上一轮**的值，
  /// 不假装它是实时的字符级速度。
  /// 顶部的模型胶囊：一眼看出现在用的是哪个模型、属于哪个 provider，
  /// 点一下就能换（不必打 /model，也不用离开会话）。
  Widget _buildModelChip(NeuTokens t, ChatReducer chat) {
    // 只显示模型名：`模型 · provider` 太长，会把会话名挤到看不见
    //（provider 在点开的切换器里能看到）
    final label = modelChipLabel(chat.model);
    return ConstrainedBox(
      // 宽度：一行里还要放会话名 + 状态点 + 三个按钮，所以必须给上限。
      // 76 是更早的值 —— 实测它把「DeepSeek V4.1 Flash」截成 Dee…，用户的原话是
      // 「太杂乱了一点也不美观」：一个只剩三个字母的截断，既认不出是哪个模型，
      // 看起来也像渲染坏了。
      //
      // 96 配上面剥掉厂商词之后的型号（`V4.1 Flash`，10 个字符）刚好装得下，
      // 不用再抢会话名的空间。
      constraints: const BoxConstraints(maxWidth: 96),
      child: NeuPressable(
        onTap: _showModelSwitcher,
        radius: 8,
        flat: true,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              // 缩放而不是截断。用户的原话是「在这里显示缩小的不就好了」——
              // 截成 `DeepSe…` 只剩三个字母，既认不出是哪个模型、又像渲染坏了；
              // 缩到小一号至少把名字完整给出来。
              //
              // 配合 modelChipLabel 剥掉冗余厂商词，缩的幅度通常很小
              //（`V4.1 Flash` 在 96dp 里几乎不用缩）；即使遇到特别长的名字
              //（`DeepSeek V4 Flash Vision Exp`），也只是变小，不会丢字。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: NeuFonts.badge, color: t.accentInk),
                ),
              ),
            ),
            const SizedBox(width: NeuSpace.n4),
            NeuIcon(IconId.chevronDown, size: 12, color: t.accentInk),
          ],
        ),
      ),
    );
  }

  /// 模型 + 思考等级的浮动切换器。
  ///
  /// 只改**当前会话**：pi 的 set_model / set_thinking_level 写的是会话记录，
  /// 不动设置文件里的默认值 —— 所以「重启后保持」是会话级别保持，
  /// 新会话仍然用你配的默认模型（这一条在验证记录里实测过）。
  Future<void> _showModelSwitcher() async {
    final models = await _store.availableModels();
    final levels = await _store.availableThinkingLevels();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = sheetContext.neu;
        // 弹层内部的错误行。
        // 为什么不用 NeuToast：底部弹层也在 overlay 里且盖在上面，
        // 弹层里弹出的 toast 会被自己挡住 —— 实测「切模型失败但什么都看不到」。
        String? inSheetError;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final chat = _store.chat;
            final current = chat.model;
            // 按 provider 分组，切换时能一眼看出「这条是官方还是中转」
            final byProvider = <String, List<ModelInfo>>{};
            for (final model in models) {
              byProvider.putIfAbsent(model.provider, () => []).add(model);
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
              ),
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(NeuRadii.lg),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n12, NeuSpace.n18, NeuSpace.n24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.t('ui.29f830c6dd'),
                      style: TextStyle(
                        fontSize: NeuFonts.sectionTitle,
                        fontWeight: FontWeight.w700,
                        color: t.onBg,
                      ),
                    ),
                    SizedBox(height: NeuSpace.n4),
                    Text(
                      current == null
                          ? I18n.t('ui.6e6f9563b7')
                          : I18n.tp('ui.9fa88d5d6f', {'name': current.name, 'provider': current.provider}),
                      style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                    ),
                    if (inSheetError != null) ...[
                      const SizedBox(height: NeuSpace.n8),
                      Row(
                        children: [
                          NeuIcon(IconId.warn, size: 14, color: t.danger),
                          const SizedBox(width: NeuSpace.n6),
                          Expanded(
                            child: Text(
                              inSheetError!,
                              style: TextStyle(fontSize: NeuFonts.small, color: t.danger),
                            ),
                          ),
                        ],
                      ),
                    ],
                    SizedBox(height: NeuSpace.n14),
                    Text(
                      I18n.t('ui.11eead2c33'),
                      style: TextStyle(
                        fontSize: NeuFonts.sub,
                        fontWeight: FontWeight.w700,
                        color: t.accentInk,
                      ),
                    ),
                    const SizedBox(height: NeuSpace.n8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final level in levels)
                          NeuPressable(
                            onTap: () async {
                              final ok = await _store.setThinkingLevel(level);
                              if (!sheetContext.mounted) return;
                              setSheetState(() {
                                inSheetError = ok ? null : _store.lastError;
                              });
                              if (ok) {
                                NeuToast.show(
                                  sheetContext,
                                  message: I18n.tp('ui.944e771000', {'level': level}),
                                  icon: IconId.check,
                                );
                              }
                            },
                            flat: chat.thinkingLevel != level,
                            alwaysInset: chat.thinkingLevel == level,
                            radius: 8,
                            padding: const EdgeInsets.symmetric(
                              horizontal: NeuSpace.n12,
                              vertical: NeuSpace.n7,
                            ),
                            child: Text(
                              level,
                              style: TextStyle(
                                fontSize: NeuFonts.sub,
                                color: chat.thinkingLevel == level
                                    ? t.accentInk
                                    : t.fg,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: NeuSpace.n16),
                    Text(
                      I18n.t('ui.41f1f2fb0e'),
                      style: TextStyle(
                        fontSize: NeuFonts.sub,
                        fontWeight: FontWeight.w700,
                        color: t.accentInk,
                      ),
                    ),
                    const SizedBox(height: NeuSpace.n8),
                    for (final entry in byProvider.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: NeuSpace.n8, bottom: NeuSpace.n4),
                        child: Text(
                          entry.key,
                          style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                        ),
                      ),
                      for (final model in entry.value)
                        _modelRow(
                          t,
                          sheetContext,
                          setSheetState,
                          model,
                          current,
                          (message) => inSheetError = message,
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _modelRow(
    NeuTokens t,
    BuildContext sheetContext,
    StateSetter setSheetState,
    ModelInfo model,
    ModelInfo? current,
    void Function(String?) reportError,
  ) {
    final isCurrent =
        current != null &&
        current.provider == model.provider &&
        current.id == model.id;
    return NeuPressable(
      flat: !isCurrent,
      alwaysInset: isCurrent,
      radius: 10,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n9),
      margin: const EdgeInsets.only(bottom: NeuSpace.n6),
      onTap: () async {
        final ok = await _store.setModel(model.provider, model.id);
        if (!sheetContext.mounted) return;
        setSheetState(() {
          reportError(ok ? null : (_store.lastError ?? I18n.t('ui.2d5fbafe5d')));
        });
        if (ok) {
          NeuToast.show(
            sheetContext,
            message: I18n.tp('ui.97523d250a', {'name': model.name, 'provider': model.provider}),
            icon: IconId.check,
          );
        }
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(model.name, style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg)),
                Text(
                  '${I18n.tp('ui.b7077d029c', {
                    'provider': model.provider,
                    'window': model.contextWindow ?? '?',
                  })}'
                  '${model.reasoning ? I18n.t('ui.af181ac8b2') : ''}',
                  style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
                ),
              ],
            ),
          ),
          if (isCurrent) NeuIcon(IconId.check, size: 15, color: t.accentInk),
        ],
      ),
    );
  }

  /// 待发送图片的缩略行（在输入框上方）：让用户看清「这条消息带了什么」
  Widget _buildPendingImages(NeuTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n4, NeuSpace.n18, 0),
      child: Row(
        children: [
          for (final image in _pendingImages)
            Padding(
              padding: const EdgeInsets.only(right: NeuSpace.n6),
              child: NeuPressable(
                // 点缩略图就是移除，但给一条可撤销的提示 ——
                // 手机上误触缩略图太容易了，直接没了会让人重新选一遍图
                onTap: () {
                  final index = _pendingImages.indexOf(image);
                  setState(() => _pendingImages.remove(image));
                  showUndoSnack(context, I18n.tp('ui.8dc0a54c3c', {'name': image.name}), () {
                    if (!mounted) return;
                    setState(
                      () => _pendingImages.insert(
                        index.clamp(0, _pendingImages.length),
                        image,
                      ),
                    );
                  });
                },
                radius: 8,
                flat: true,
                // 触控目标：图标 13 + 14×2 = 41dp（原来 vertical n5 只有 23dp）
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n8, vertical: NeuSpace.n14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NeuIcon(IconId.download, size: 13, color: t.accentInk),
                    const SizedBox(width: NeuSpace.n5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        image.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: NeuFonts.label, color: t.fg),
                      ),
                    ),
                    const SizedBox(width: NeuSpace.n5),
                    NeuIcon(IconId.close, size: 12, color: t.muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// ＋ 菜单：素材（相册 / 文件 / 剪贴板）+ 常用语模板。
  ///
  /// 手机上没有文件管理器可用，「把东西给 agent」就这三条路，
  /// 所以合成一个入口，而不是在输入框旁摆三个小图标。
  Future<void> _showInputMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = sheetContext.neu;
        return StatefulBuilder(
          builder: (context, setSheetState) => Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
            ),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(NeuRadii.lg),
              ),
            ),
            padding: EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n14, NeuSpace.n18, NeuSpace.n24),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    I18n.t('ui.54d363afee'),
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      fontWeight: FontWeight.w700,
                      color: t.accentInk,
                    ),
                  ),
                  const SizedBox(height: NeuSpace.n8),
                  Row(
                    children: [
                      _menuTile(
                        t,
                        sheetContext,
                        IconId.download,
                        I18n.t('ui.824949be5b'),
                        _pickImage,
                      ),
                      SizedBox(width: NeuSpace.n8),
                      _menuTile(
                        t,
                        sheetContext,
                        IconId.folder,
                        I18n.t('ui.2a0c4740f1'),
                        _pickFile,
                      ),
                      SizedBox(width: NeuSpace.n8),
                      _menuTile(
                        t,
                        sheetContext,
                        IconId.pen,
                        I18n.t('ui.32249be96d'),
                        _pasteClipboardText,
                      ),
                    ],
                  ),
                  SizedBox(height: NeuSpace.n6),
                  Text(
                    I18n.t('ui.6b8e604809'),
                    style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                  ),
                  SizedBox(height: NeuSpace.n16),
                  Row(
                    children: [
                      Text(
                        I18n.t('ui.64dfcf277f'),
                        style: TextStyle(
                          fontSize: NeuFonts.sub,
                          fontWeight: FontWeight.w700,
                          color: t.accentInk,
                        ),
                      ),
                      SizedBox(width: NeuSpace.n8),
                      Text(
                        I18n.t('ui.14768ed565'),
                        style: TextStyle(fontSize: NeuFonts.badge, color: t.muted),
                      ),
                    ],
                  ),
                  SizedBox(height: NeuSpace.n8),
                  if (_templates.isEmpty)
                    Text(
                      I18n.t('ui.d0f489e127'),
                      style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                    )
                  else
                    for (final item in _templates)
                      NeuPressable(
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _insertIntoInput(item);
                        },
                        radius: 10,
                        padding: const EdgeInsets.symmetric(
                          horizontal: NeuSpace.n12,
                          vertical: NeuSpace.n9,
                        ),
                        margin: const EdgeInsets.only(bottom: NeuSpace.n6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.fg),
                              ),
                            ),
                            NeuPressable(
                              onTap: () async {
                                await TemplateStore.instance.remove(item);
                                final items = await TemplateStore.instance
                                    .load();
                                if (!sheetContext.mounted) return;
                                setSheetState(() {});
                                setState(() => _templates = List.of(items));
                              },
                              radius: 8,
                              flat: true,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
                                child: NeuIcon(
                                  IconId.close,
                                  size: 13,
                                  color: t.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: NeuSpace.n8),
                  NeuPressable(
                    onTap: () async {
                      final text = _input.text.trim();
                      if (text.isEmpty) {
                        NeuToast.show(
                          sheetContext,
                          message: I18n.t('ui.37dba61d9d'),
                          icon: IconId.warn,
                        );
                        return;
                      }
                      await TemplateStore.instance.add(text);
                      final items = await TemplateStore.instance.load();
                      if (!sheetContext.mounted) return;
                      setSheetState(() {});
                      setState(() => _templates = List.of(items));
                      NeuToast.show(
                        sheetContext,
                        message: I18n.t('ui.17ab7240c1'),
                        icon: IconId.check,
                      );
                    },
                    radius: NeuRadii.sm,
                    padding: const EdgeInsets.symmetric(vertical: NeuSpace.n11),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NeuIcon(IconId.plus, size: 14, color: t.accentInk),
                        SizedBox(width: NeuSpace.n6),
                        Text(
                          I18n.t('ui.8551ea0b22'),
                          style: TextStyle(fontSize: NeuFonts.bodySmall, color: t.accentInk),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _menuTile(
    NeuTokens t,
    BuildContext sheetContext,
    IconId icon,
    String label,
    Future<void> Function() action,
  ) {
    return Expanded(
      child: NeuPressable(
        onTap: () async {
          Navigator.of(sheetContext).pop();
          await action();
        },
        radius: 10,
        padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n11),
        child: Column(
          children: [
            NeuIcon(icon, size: 18, color: t.accentInk),
            const SizedBox(height: NeuSpace.n6),
            Text(label, style: TextStyle(fontSize: NeuFonts.label, color: t.fg)),
          ],
        ),
      ),
    );
  }

  /// 相册/图片：读成 base64 挂在这条消息上（pi 的 prompt 支持 images）
  Future<void> _pickImage() async {
    try {
      // file_picker 13 的 API：静态 pickFile() + readAsBytes()
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          NeuToast.show(context, message: I18n.t('ui.e849a32234'), icon: IconId.warn);
        }
        return;
      }
      final ext = (file.extension ?? 'png').toLowerCase();
      final mime = ext == 'jpg' || ext == 'jpeg'
          ? 'image/jpeg'
          : (ext == 'webp' ? 'image/webp' : 'image/$ext');
      if (!mounted) return;
      setState(
        () => _pendingImages.add((
          name: file.name,
          base64: base64Encode(bytes),
          mime: mime,
        )),
      );
      NeuToast.show(context, message: I18n.tp('ui.42ccfeb789', {'name': file.name}), icon: IconId.check);
    } catch (error) {
      if (mounted) {
        NeuToast.show(context, message: I18n.tp('ui.1afcd77a58', {'error': error}), icon: IconId.warn);
      }
    }
  }

  /// 其他文件：先传到工作区，再把路径写进输入框（pi 靠路径读文件）
  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          NeuToast.show(context, message: I18n.t('ui.b16350e431'), icon: IconId.warn);
        }
        return;
      }
      final cwd = _store.chat.cwd.isNotEmpty
          ? _store.chat.cwd
          : (_store.target?.defaultCwd ?? '');
      if (cwd.isEmpty) {
        if (mounted) {
          NeuToast.show(
            context,
            message: I18n.t('ui.0f4c3ea1dd'),
            icon: IconId.warn,
          );
        }
        return;
      }
      final ok = await _store.uploadFile(
        dir: cwd,
        name: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      if (ok && _store.lastUploadedPath != null) {
        _insertIntoInput('${_store.lastUploadedPath} ');
      }
    } catch (error) {
      if (mounted) {
        NeuToast.show(context, message: I18n.tp('ui.723126c430', {'error': error}), icon: IconId.warn);
      }
    }
  }

  /// 剪贴板文本。
  ///
  /// 诚实说明一句：Android 里读**图片**剪贴板需要额外的原生能力，
  /// Flutter 自带的 Clipboard 只有文本 —— 所以这里只做文本，
  /// 图片请走「相册 / 图片」（两者效果一样，都是把图给 pi 看）。
  Future<void> _pasteClipboardText() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        NeuToast.show(context, message: I18n.t('ui.7bf84c8cd4'), icon: IconId.warn);
      }
      return;
    }
    _insertIntoInput(text);
  }

  void _insertIntoInput(String text) {
    final current = _input.text;
    final needsSpace = current.isNotEmpty && !current.endsWith(' ');
    _setInput('$current${needsSpace ? ' ' : ''}$text');
    _inputFocus.requestFocus();
  }

  /// 顶部「加载更早的消息」。
  ///
  /// 快照只带最近几十条（实测一个大会话有 523 条上下文消息），
  /// 更早的用 get_history 往上翻。
  /// 离线提示条：说清楚三件事 —— 现在没连上、看到的是几点的缓存、怎么重试。
  /// 「更早的 N 条未缓存」也要写出来，否则用户会以为消息被弄丢了。
  /// 会话没拉起来：错误文案 + 「重新载入」入口（复用加载态的失败样式）。
  /// 单独留一个方法，是为了让「失败」这个状态在代码里显式存在，不再被当成空会话。
  Widget _buildLoadFailed(NeuTokens t) => ChatLoading(store: _store);

  /// 会话信息 + 分支树。
  ///
  /// pi 的会话是一棵树（fork / 编辑重发都会长出分支），
  /// 手机上先用一个只读列表把它展示出来（切换分支需要 AgentSessionRuntime，待接）。
  Future<void> _showSessionInfo() async {
    // 这里以前是裸 await：一旦取数抛出，面板会「点了没反应」——
    // 这类静默失败比报错难查得多，所以先接住再提示。
    Map<String, dynamic>? tree;
    SessionStats? stats;
    try {
      tree = await _store.fetchTree();
      // 用量/花费/上下文占用：跟分支树一起拉，别让面板分两次刷新
      stats = await _store.sessionStats();
    } catch (error) {
      if (!mounted) return;
      NeuToast.show(context, message: I18n.tp('ui.a6664f495a', {'error': error}), icon: IconId.warn);
      return;
    }
    if (!mounted) return;
    final chat = _store.chat;
    final nodes = tree?['tree'];
    final leafId = tree?['leafId'] as String?;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final t = sheetContext.neu;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
          ),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(NeuRadii.lg),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(NeuSpace.n18, NeuSpace.n10, NeuSpace.n18, NeuSpace.n24),
          // 整张面板可滚动。
          // 以前只有分支树那一小块能滑，上面的「用量」一多就把下面按钮顶出屏幕，
          // 怎么滑都够不到（实测过：三指上推都不动）。
          child: SingleChildScrollView(
            child: Column(
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
                SizedBox(height: NeuSpace.n14),
                Text(
                  I18n.t('ui.155e26ceeb'),
                  style: TextStyle(
                    fontSize: NeuFonts.sectionTitle,
                    fontWeight: FontWeight.w700,
                    color: t.onBg,
                  ),
                ),
                SizedBox(height: NeuSpace.n10),
                _infoLine(
                  t,
                  I18n.t('common.model'),
                  chat.model == null
                      ? '—'
                      : '${chat.model!.name} (${chat.model!.provider})',
                ),
                _infoLine(t, I18n.t('ui.11eead2c33'), chat.thinkingLevel),
                _infoLine(
                  t,
                  I18n.t('ui.ff692f04ac'),
                  I18n.tp('ui.7622b8adf0', {'n': chat.messages.length, 'total': chat.historyTotal}),
                ),
                _infoLine(t, I18n.t('settings.workspace'), chat.cwd),
                if (chat.sessionName != null)
                  _infoLine(t, I18n.t('ui.20c94429e5'), chat.sessionName!),
                if (stats != null) ...[
                  SizedBox(height: NeuSpace.n6),
                  Text(
                    I18n.t('ui.743735721a'),
                    style: TextStyle(
                      fontSize: NeuFonts.small,
                      fontWeight: FontWeight.w700,
                      color: t.accentInk,
                    ),
                  ),
                  SizedBox(height: NeuSpace.n4),
                  _infoLine(
                    t,
                    I18n.t('ui.50f198f07f'),
                    stats.contextPercent != null
                        ? '${stats.contextPercent!.toStringAsFixed(1)}% · ${_tokens(stats.contextTokens)} / ${_tokens(stats.contextWindow)}'
                        : I18n.t('ui.4f23e4de2b'),
                  ),
                  _infoLine(
                    t,
                    'tokens',
                    I18n.tp('ui.37e8f35792', {'total': _tokens(stats.totalTokens), 'input': _tokens(stats.inputTokens), 'output': _tokens(stats.outputTokens), 'cr': _tokens(stats.cacheReadTokens), 'cw': _tokens(stats.cacheWriteTokens)}),
                  ),
                  if (stats.costTotal > 0)
                    _infoLine(
                      t,
                      I18n.t('ui.f970d0272c'),
                      '\$${stats.costTotal.toStringAsFixed(4)}',
                    ),
                  _infoLine(
                    t,
                    I18n.t('ui.8fd578b58a'),
                    I18n.tp('ui.d8deeeee4c', {'u': stats.userMessages, 'a': stats.assistantMessages, 'tc': stats.toolCalls, 'tr': stats.toolResults}),
                  ),
                  _infoLine(
                    t,
                    I18n.t('ui.dc0f2e515f'),
                    chat.autoCompactionEnabled ? I18n.t('ui.9db7a84fcd') : I18n.t('ui.9c58505de3'),
                  ),
                  const SizedBox(height: NeuSpace.n4),
                  // 「重点模式」从标题栏下沉到这里：标题栏一行要塞下
                  // 会话名 + 状态点 + 模型 + 按钮，四个按钮里它最低频，
                  // 却是把会话名挤到 0 宽的元凶之一（实测）。
                  NeuPressable(
                    onTap: () {
                      setState(() => _focusMode = !_focusMode);
                      Navigator.of(sheetContext).pop();
                      NeuToast.show(
                        context,
                        message: _focusMode ? I18n.t('ui.d03d895f04') : I18n.t('ui.13261adf5f'),
                        icon: IconId.bubble,
                      );
                    },
                    radius: NeuRadii.sm,
                    flat: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n6,
                      vertical: NeuSpace.n10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            I18n.t('ui.d03d895f04'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: NeuFonts.small, color: t.fg),
                          ),
                        ),
                        Text(
                          _focusMode ? I18n.t('ui.9db7a84fcd') : I18n.t('ui.9c58505de3'),
                          style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: NeuSpace.n12),
                NeuPressable(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SessionExportPage(store: _store),
                      ),
                    );
                  },
                  radius: NeuRadii.sm,
                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NeuIcon(IconId.download, size: 15, color: t.accentInk),
                      SizedBox(width: NeuSpace.n8),
                      Text(
                        I18n.t('ui.cb9bf0e70e'),
                        style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NeuSpace.n8),
                NeuPressable(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => UsagePage(
                          store: _store,
                          contextPercent: stats?.contextPercent,
                          contextTokens: stats?.contextTokens,
                          contextWindow: stats?.contextWindow,
                          autoCompactEnabled: chat.autoCompactionEnabled,
                        ),
                      ),
                    );
                  },
                  radius: NeuRadii.sm,
                  padding: const EdgeInsets.symmetric(vertical: NeuSpace.n11),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NeuIcon(IconId.info, size: 15, color: t.accentInk),
                      SizedBox(width: NeuSpace.n8),
                      Text(
                        I18n.t('ui.f0d15d56eb'),
                        style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NeuSpace.n8),
                NeuPressable(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            WorkspaceFilesPage(store: _store, cwd: chat.cwd),
                      ),
                    );
                  },
                  radius: NeuRadii.sm,
                  padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NeuIcon(IconId.folder, size: 15, color: t.accentInk),
                      SizedBox(width: NeuSpace.n8),
                      Text(
                        I18n.t('ui.480b698883'),
                        style: TextStyle(fontSize: NeuFonts.bodyMid, color: t.accentInk),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: NeuSpace.n16),
                Text(
                  I18n.t('ui.19b5e0a26e'),
                  style: TextStyle(
                    fontSize: NeuFonts.sectionTitle,
                    fontWeight: FontWeight.w700,
                    color: t.onBg,
                  ),
                ),
                SizedBox(height: NeuSpace.n6),
                Text(
                  nodes == null
                      ? I18n.t('ui.dd55c97800')
                      : I18n.tp('ui.d7320b9231', {'n': _countTree(nodes)}),
                  style: TextStyle(fontSize: NeuFonts.label, color: t.muted),
                ),
                const SizedBox(height: NeuSpace.n10),
                if (nodes != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _treeRows(t, nodes, 0, leafId),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 从某条历史消息分出一条新会话。
  ///
  /// 与「切换分支」的区别：切换是同一个会话内换路径，
  /// 这里是**另开一条会话**从该点往后走，原会话保持不动。
  Future<void> _forkFrom(String entryId, String preview) async {
    final t = context.neu;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text(I18n.t('ui.a1c0a7962b'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
        content: Text(
          // ignore: prefer_interpolation_to_compose_strings
          '${I18n.tp('ui.124ba57d80', {
            'preview': preview.isEmpty ? entryId.substring(0, 8) : preview,
          })}'
          '${I18n.t('ui.1263de37a0')}',
          style: TextStyle(color: t.muted, fontSize: NeuFonts.bodySmall, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(I18n.t('ui.bfc04cfda7'), style: TextStyle(color: t.accentInk)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final newId = await _store.forkFromMessage(entryId);
    if (!mounted) return;
    if (newId == null) return;
    _applyPendingEditorText();
    Navigator.of(context).pop(); // 关掉树面板
    NeuToast.show(context, message: I18n.t('ui.cd7349bbde'), icon: IconId.check);
  }

  /// 切到树里的另一个节点。
  ///
  /// 会改变模型上下文（后续对话接在另一条分支上），所以先确认。
  /// 可选「生成摘要」：把被舍弃的那条分支压缩成摘要带过去（pi 的 /tree summarize）。
  Future<void> _navigateTo(String targetId, String preview) async {
    final t = context.neu;
    var summarize = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: t.bg,
          title: Text(I18n.t('ui.4956c9f6d6'), style: TextStyle(color: t.fg, fontSize: NeuFonts.sectionTitle)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // ignore: prefer_interpolation_to_compose_strings
                '${I18n.tp('ui.558ac73c08', {
                  'preview': preview.isEmpty ? targetId.substring(0, 8) : preview,
                })}'
                '${I18n.t('ui.68af09ffe6')}',
                style: TextStyle(color: t.muted, fontSize: NeuFonts.bodySmall, height: 1.6),
              ),
              const SizedBox(height: NeuSpace.n14),
              GestureDetector(
                onTap: () => setDialogState(() => summarize = !summarize),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Icon(
                      summarize
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: summarize ? t.accentInk : t.muted,
                    ),
                    SizedBox(width: NeuSpace.n8),
                    Expanded(
                      child: Text(
                        I18n.t('ui.e949f0cedd'),
                        style: TextStyle(
                          color: summarize ? t.fg : t.muted,
                          fontSize: NeuFonts.sub,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(I18n.t('common.cancel'), style: TextStyle(color: t.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(I18n.t('ui.bec7e4d621'), style: TextStyle(color: t.accentInk)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    // 生成摘要要跑一次模型，耗时明显，先告知再等
    if (summarize) {
      NeuToast.show(context, message: I18n.t('ui.74596dca8e'), icon: IconId.spinner);
    }
    final ok = await _store.navigateTree(targetId, summarize: summarize);
    if (!mounted) return;
    if (!ok) return;
    // 被切走的那条用户消息放回输入框（pi 的 editorText 行为），想接着改就直接改
    _applyPendingEditorText();
    Navigator.of(context).pop(); // 关掉树面板
    NeuToast.show(
      context,
      message: summarize ? I18n.t('ui.53c4ba1558') : I18n.t('ui.7fd5122d71'),
      icon: IconId.check,
    );
  }

  /// 把 pi 回传的 editorText 放进输入框（切分支 / 从历史分叉之后调用）
  void _applyPendingEditorText() {
    final text = _store.pendingEditorText;
    if (text == null || text.isEmpty) return;
    _store.pendingEditorText = null;
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  /// 把 token 数按人类读法缩短（1.2M / 34.5k / 900）
  static String _tokens(int? value) {
    if (value == null) return '?';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '$value';
  }

  Widget _infoLine(NeuTokens t, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NeuSpace.n3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(label, style: TextStyle(fontSize: NeuFonts.sub, color: t.muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: NeuFonts.sub, color: t.fg, height: 1.5),
          ),
        ),
      ],
    ),
  );

  static int _countTree(List<dynamic> nodes) {
    var total = 0;
    for (final node in nodes) {
      if (node is! Map) continue;
      total += 1;
      final children = node['children'];
      if (children is List) total += _countTree(children);
    }
    return total;
  }

  /// 把树压成带缩进的列表（深度优先）
  List<Widget> _treeRows(
    NeuTokens t,
    List<dynamic> nodes,
    int depth,
    String? leafId,
  ) {
    final rows = <Widget>[];
    for (final node in nodes) {
      if (node is! Map) continue;
      final entry = (node['entry'] ?? node) as Map;
      final id = entry['id']?.toString();
      final message = entry['message'] as Map?;
      final role =
          message?['role']?.toString() ?? entry['type']?.toString() ?? '?';

      String preview = '';
      final content = message?['content'];
      if (content is String) {
        preview = content;
      } else if (content is List) {
        for (final block in content) {
          if (block is Map && block['type'] == 'text') {
            preview = block['text']?.toString() ?? '';
            break;
          }
        }
      }
      // 把所有空白（含换行）压成单个空格；用正则避免在源码里写转义换行
      preview = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (preview.length > 42) preview = '${preview.substring(0, 42)}…';

      final isLeaf = id != null && id == leafId;
      final children = node['children'];
      final childCount = children is List ? children.length : 0;
      // 分叉点标出来：这里曾经有过另一条路
      final branchHint =
          childCount > 1 ? I18n.tp('ui.5bbb1a9d41', {'n': childCount}) : '';

      final rowContent = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (depth > 0)
            Padding(
              padding: const EdgeInsets.only(right: NeuSpace.n6, top: NeuSpace.n1),
              child: NeuIcon(IconId.chevronRight, size: 12, color: t.muted),
            ),
          Expanded(
            child: Text(
              '${isLeaf ? '● ' : ''}$role${preview.isEmpty ? '' : ' · $preview'}$branchHint',
              style: TextStyle(
                fontSize: NeuFonts.small,
                height: 1.5,
                color: isLeaf ? t.accentInk : t.fg,
                fontWeight: isLeaf ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          // 从这里分出一条新会话（复制历史 + 回退到该节点）
          if (id != null && !isLeaf)
            NeuPressable(
              onTap: () => _forkFrom(id, preview),
              radius: 10,
              // 触控目标 13 + 14×2 = 41dp；原本 23dp（13+5×2），手指按不准
              padding: const EdgeInsets.all(NeuSpace.n14),
              child: NeuIcon(IconId.plus, size: 13, color: t.muted),
            ),
        ],
      );

      rows.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 14.0),
          child: isLeaf || id == null
              // 当前节点不可点；其余节点点一下切过去
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: NeuSpace.n3),
                  child: rowContent,
                )
              : NeuPressable(
                  flat: true,
                  onTap: () => _navigateTo(id, preview),
                  padding: const EdgeInsets.symmetric(
                    vertical: NeuSpace.n6,
                    horizontal: NeuSpace.n4,
                  ),
                  child: rowContent,
                ),
        ),
      );

      if (children is List && children.isNotEmpty) {
        rows.addAll(_treeRows(t, children, depth + 1, leafId));
      }
    }
    return rows;
  }

  /// @ 引用候选列表（与命令面板同一套样式，只是数据源是工作区文件）
  Widget _buildFileRefs(NeuTokens t) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.symmetric(horizontal: NeuSpace.n18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NeuRadii.md),
        gradient: NeuDecorations.wellGradient(t),
        boxShadow: NeuShadows.inset(t),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(NeuSpace.n6),
        itemCount: _fileRefs.length,
        itemBuilder: (context, index) {
          final ref = _fileRefs[index];
          return NeuPressable(
            onTap: () => _applyFileRef(ref),
            flat: true,
            padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n13, vertical: NeuSpace.n13),
            child: Row(
              children: [
                NeuIcon(IconId.terminal, size: 14, color: t.accentInk),
                const SizedBox(width: NeuSpace.n8),
                Expanded(
                  child: Text(
                    ref.relative,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: NeuFonts.sub,
                      fontFamily: 'monospace',
                      color: t.fg,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSuggestions(NeuTokens t, List<SlashCommand> commands) {
    // 面板高度跟屏幕走。以前写死 200：手机上只能看到 4 条，
    // 12 条命令得一直滑，看起来就像「显示不完全」。
    // 必须减掉键盘高度（viewInsets.bottom）：否则软键盘弹起来会盖住面板底部几条，
    // 用户会以为「命令就这些」。
    final maxHeight = slashPanelMaxHeight(MediaQuery.of(context));
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      margin: const EdgeInsets.symmetric(horizontal: NeuSpace.n18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NeuRadii.md),
        gradient: NeuDecorations.wellGradient(t),
        boxShadow: NeuShadows.inset(t),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (commands.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n12, vertical: NeuSpace.n16),
              child: Row(
                children: [
                  NeuIcon(IconId.spinner, size: 14, color: t.muted),
                  SizedBox(width: NeuSpace.n8),
                  Expanded(
                    child: Text(
                      I18n.t('ui.8109beab3c'),
                      style: TextStyle(fontSize: NeuFonts.small, color: t.muted),
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(NeuSpace.n6),
                itemCount: commands.length,
                itemBuilder: (context, index) {
                  final command = commands[index];
                  // 中文模式优先中文说明；没有就原文 + 标注（不假装翻过）
                  final description = I18n.describe(
                    command.description,
                    command.descriptionZh,
                    context: context,
                  );
                  return NeuPressable(
                    onTap: () => _applyCommand(command),
                    flat: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NeuSpace.n10,
                      vertical: NeuSpace.n8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: NeuSpace.n2),
                          child: NeuIcon(
                            switch (command.source) {
                              'builtin' => IconId.cmd,
                              'skill' => IconId.spinner,
                              'prompt' => IconId.pen,
                              _ => IconId.terminal,
                            },
                            size: 15,
                            color: t.accentInk,
                          ),
                        ),
                        const SizedBox(width: NeuSpace.n8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 命令名长短不一（扩展命令可以是长路径），
                              // 所以给一行横向滚动：名字再长也能滑着读完，不截断
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '/${command.name}',
                                        style: TextStyle(
                                          fontSize: NeuFonts.bodyMid,
                                          fontFamily: 'monospace',
                                          color: t.fg,
                                        ),
                                      ),
                                      if (command.argHint != null &&
                                          command.argHint!.isNotEmpty)
                                        TextSpan(
                                          text: '  ${command.argHint}',
                                          style: TextStyle(
                                            fontSize: NeuFonts.badge,
                                            color: t.muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: NeuSpace.n2),
                                  child: Text(
                                    description,
                                    // 说明不再截断：面板本身可以滚，读全比好看重要
                                    style: TextStyle(
                                      fontSize: NeuFonts.label,
                                      height: 1.45,
                                      color: t.muted,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (commands.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: NeuSpace.n6),
              child: Text(
                // 数字必须是真话：显示了多少 / 一共多少（筛选时两个数不一样）
                commands.length == _store.commands.length
                    ? I18n.tp('ui.a977d99ebd', {'n': commands.length})
                    : I18n.tp('ui.6e9ce7a03e', {'a': commands.length, 'b': _store.commands.length}),
                style: TextStyle(fontSize: NeuFonts.micro, color: t.muted),
              ),
            ),
        ],
      ),
    );
  }

  /// 引用：把这段文字带上引用标记塞回输入框（引用后还能补一句自己的话）
  void _quoteText(String text) {
    final quoted = text.trim().split('\n').map((line) => '> $line').join('\n');
    final current = _input.text;
    _setInput(current.isEmpty ? '$quoted\n\n' : '$current\n$quoted\n\n');
    _inputFocus.requestFocus();
  }

  /// 编辑重发：把一条用户消息拉回输入框改写，再发出去就是新一轮
  void _editResend(String text) {
    if (_store.chat.isRunning) {
      // 正在跑的时候拉回来，user 期望是「这条别跑了」——
      // 只说不动会更困惑，所以直接停掉当前运行
      _store.abort();
    }
    _setInput(text);
    _inputFocus.requestFocus();
    NeuToast.show(context, message: I18n.t('ui.b13542f798'), icon: IconId.pen);
    setState(() {});
  }

  /// 最近一条用户消息的正文（「再来一次」要重发它）
  String _lastUserText(ChatReducer chat) {
    for (final message in chat.messages.reversed) {
      if (message.isUser && message.text.trim().isNotEmpty) {
        return message.text.trim();
      }
    }
    return '';
  }

  /// 继续：把「继续」当作一条普通消息发出去（pi 侧接着干）
  Future<void> _continueRun() async {
    final ok = await _store.sendPrompt(I18n.t('ui.27ca568be2'));
    if (!mounted) return;
    if (!ok) {
      NeuToast.show(
        context,
        message: _store.lastError ?? I18n.t('ui.9ca6a3440e'),
        icon: IconId.warn,
      );
    }
  }

  /// 再来一次：重发最近一条用户消息
  Future<void> _redoLast(ChatReducer chat) async {
    final text = _lastUserText(chat);
    if (text.isEmpty) {
      NeuToast.show(context, message: I18n.t('ui.9a75eed25e'), icon: IconId.info);
      return;
    }
    final ok = await _store.sendPrompt(text);
    if (!mounted) return;
    if (!ok) {
      NeuToast.show(
        context,
        message: _store.lastError ?? I18n.t('ui.9ca6a3440e'),
        icon: IconId.warn,
      );
    }
  }

  /// 删除类操作的可撤销入口。
  ///
  /// 用 SnackBar 而不是自家的 NeuToast：撤销必须有**一个可点的按钮**，
  /// NeuToast 是纯展示的（之前踩过「toast 上的按钮点不到」的坑）。
  /// 本轮改动速览 + 继续 / 再来一次。
  ///
  /// 放在输入框正上方：这一条说的是「刚刚这一轮做了什么」，
  /// 视线自然落在即将输入的地方，不跟消息流抢位置。
  /// 底部「本轮速览 + 继续/再来一次」是否值得占一行。
  ///
  /// 判据只有两条：**有本轮改动可看**，或**最后一步出错需要用户处理**。
  /// 其余情况（正常跑完、纯聊天）收起来 —— 它常驻约占 40 逻辑高，
  /// 而手机竖屏的竖向空间是最稀缺的资源。
  bool _turnFooterWorthShowing(ChatReducer chat) {
    final summary = _store.turnSummary;
    if (summary != null && !summary.isEmpty) return true;
    if (chat.messages.isEmpty) return false;
    return chat.messages.last.isError;
  }

  Widget _buildTurnFooter(NeuTokens t, ChatReducer chat) {
    final summary = _store.turnSummary;
    final hasChanges = summary != null && !summary.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(NeuSpace.n18, 0, NeuSpace.n18, NeuSpace.n4),
      child: Row(
        children: [
          if (hasChanges)
            Expanded(
              child: NeuPressable(
                onTap: () => showTurnSummarySheet(context, summary),
                flat: true,
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NeuIcon(IconId.pen, size: 12, color: t.accentInk),
                    SizedBox(width: NeuSpace.n5),
                    Flexible(
                      child: Text(
                        I18n.tp('ui.9069e11411', {'files': summary.files.length, 'added': summary.added, 'removed': summary.removed}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: NeuFonts.badge, color: t.accentInk),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SizedBox(width: NeuSpace.n8),
          _footerAction(t, IconId.send, I18n.t('ui.27ca568be2'), _continueRun),
          SizedBox(width: NeuSpace.n6),
          _footerAction(t, IconId.sync, I18n.t('ui.7f7c7dcf89'), () => _redoLast(chat)),
        ],
      ),
    );
  }

  Widget _footerAction(
    NeuTokens t,
    IconId icon,
    String label,
    VoidCallback onTap,
  ) {
    return NeuPressable(
      onTap: onTap,
      flat: true,
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n14, vertical: NeuSpace.n14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeuIcon(icon, size: 12, color: t.muted),
          const SizedBox(width: NeuSpace.n4),
          Text(label, style: TextStyle(fontSize: NeuFonts.badge, color: t.muted)),
        ],
      ),
    );
  }

  /// 本轮改动明细：逐文件 + 口径说明（口径必须显示，否则数字看起来像漏算）
  Widget _buildComposer(NeuTokens t, ChatReducer chat) {
    final running = chat.isRunning;
    return Container(
      // 上下各收一点：输入区常驻，竖向每一像素都是从消息区里扣的
      margin: EdgeInsets.fromLTRB(
        NeuSpace.n12,
        NeuSpace.n2,
        NeuSpace.n12,
        MediaQuery.paddingOf(context).bottom + NeuSpace.n4,
      ),
      padding: const EdgeInsets.all(NeuSpace.n2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NeuRadii.md),
        gradient: NeuDecorations.wellGradient(t),
        boxShadow: NeuShadows.inset(t),
      ),
      child: Row(
        children: [
          NeuPressable(
            // ＋：一个入口装两类东西 —— 素材（相册/文件/剪贴板）与常用语模板。
            // 聊天区拆两个按钮会很挤，手机上也难分。
            onTap: _showInputMenu,
            radius: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n11, vertical: NeuSpace.n11),
              child: NeuIcon(IconId.plus, size: 18, color: t.muted),
            ),
          ),
          const SizedBox(width: NeuSpace.n2),
          NeuPressable(
            // ⌘ 的语义按用户预期来：调出手机软键盘打不出的那些键
            // （命令面板改成按键条里的「命令」键 + 手打 /）
            onTap: _toggleKeyBar,
            radius: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n11, vertical: NeuSpace.n11),
              child: NeuIcon(
                IconId.cmd,
                size: 18,
                color: _keyBarVisible ? t.accentInk : t.muted,
              ),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: NeuFonts.body, color: t.fg),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: running
                    ? I18n.t('chat.inputHintRunning', context: context)
                    : I18n.t('chat.inputHint', context: context),
                hintStyle: TextStyle(fontSize: NeuFonts.bodyTight, color: t.muted),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: NeuSpace.n6),
          NeuPressable(
            onTap: running ? () => _store.abort() : _send,
            radius: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NeuSpace.n11, vertical: NeuSpace.n11),
              child: NeuIcon(
                running ? IconId.close : IconId.send,
                size: 18,
                color: running ? t.danger : t.accentInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 全屏对话页（从会话列表进入）。
///
/// 独立成屏而不是塞进 Tab：输入框、消息滚动、软键盘三者抢同一块高度，
/// 全屏才够用。
class ServerChatScreen extends StatelessWidget {
  const ServerChatScreen({super.key, required this.store});

  final ServerStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(bottom: false, child: ServerChatPage(store: store)),
    );
  }
}


/// `/` 命令面板的最大高度。
///
/// 抽成纯函数是为了能被单测钉住：面板高度必须按「键盘之上的可用高度」算，
/// 否则软键盘弹起会盖住底部几条命令，用户会以为「命令就这些」。
/// 上下限的来历：以前写死 200，手机上只能看到 4 条、12 条命令得一直滑。
double slashPanelMaxHeight(MediaQueryData media) {
  final available = media.size.height - media.viewInsets.bottom;
  return (available * 0.45).clamp(160.0, 420.0);
}
