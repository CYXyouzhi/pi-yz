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
import '../../theme/design_tokens.dart';
import '../key_bar.dart';
import '../neu_icons.dart';
import '../neu_toast.dart';
// slashPanelMaxHeight 搬到了 chat/widgets.dart，但测试还从本文件引用它 ——
// export 回去保持兼容（纯函数搬家，不改行为）。
export 'chat/widgets.dart' show slashPanelMaxHeight, modelChipLabel;

import 'chat/sheets.dart';
import 'chat/widgets.dart';

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

  /// 上一次渲染时的会话 id。
  ///
  /// 用来在**换会话时重置滚动派生状态**：`_headerCollapsed` / `_atBottom` 只在
  /// `_onScroll`（滚动监听）里更新，而新建/切到一个只有一两条消息的会话时
  /// 列表根本没有可滚区间、一行滚动事件都不会发 —— 于是上一个会话留下的
  /// 「标题栏已收起」就一直生效，新会话顶部干干净净没有标题栏，也点不到
  /// 会话信息/新建会话。2026-10-09 实测：滚过长会话 → 新建会话 → 标题栏不见了。
  String? _lastSessionId;

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
      await showUiDialog(context, _store, request);
      _uiDialogOpen = false;
      _maybeShowUiDialog(); // 可能还排着下一个
    });
  }

  /// 选择：底部面板列表（手机上比中间弹窗好点）
  /// 确认：居中弹窗（默认焦点在「取消」，避免误点确认）
  /// 文本输入 / 多行编辑
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
  void _onKeyBarKey(String seq) {
    final key = decodeKey(seq);
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
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final chat = _store.chat;
        // 会话换了：滚动派生状态属于上一个会话的位置，必须重置。
        // 在这里直接赋值（不 setState）—— 本次 build 马上就会用到新值，
        // 再触发一轮重建是多余的。
        if (_store.currentSessionId != _lastSessionId) {
          _lastSessionId = _store.currentSessionId;
          _headerCollapsed = false;
          _atBottom = true;
        }
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
              if (!_headerCollapsed) ChatHeader(
            store: _store,
            chat: chat,
            runStartedAt: _runStartedAt,
            onShare: _shareLastAnswer,
            onShowInfo: () => showSessionInfoSheet(
            context,
            _store,
            focusMode: _focusMode,
            onToggleFocusMode: () => setState(() => _focusMode = !_focusMode),
            onFork: _forkFrom,
            onNavigate: _navigateTo,
          ),
            onNewSession: _newSessionInCurrentWorkspace,
            onShowModelSwitcher: () => showModelSwitcherSheet(context, _store),
          ),
              // 活动条只在「跑着」或「有待确认」时占行：
              // 空闲时它显示「你好 · 空闲 · 本轮 N 次工具调用」，信息量低却照样
              // 吃掉约 37 逻辑高。入口没丢 —— 点标题栏的会话名就能打开活动视图。
              if (chat.isRunning || _store.uiRequests.any((r) => r.needsResponse))
                ChatActivityBar(store: _store, chat: chat),
              // 离线缓存提示：有缓存时界面不空，但必须说清楚「你看到的是旧的」
              if (_store.cacheShownAt != null) OfflineBanner(store: _store),
                            ChatMessageArea(
                store: _store,
                chat: chat,
                focusMode: _focusMode,
                atBottom: _atBottom,
                scroll: _scroll,
                elapsed: _elapsed,
                scrollProgress: _scrollProgress,
                onQuote: _quoteText,
                onEditResend: _editResend,
                onScrollToBottom: _scrollToBottom,
              ),
              if (chat.notice != null) ChatNoticeRow(notice: chat.notice!),
              if (chat.queuedSteering > 0 || chat.queuedFollowUp > 0)
                QueuedMessagesRow(
                  steering: chat.queuedSteering,
                  followUp: chat.queuedFollowUp,
                  onClear: () => _store.runCommand({
                    'id': 'cq${DateTime.now().microsecondsSinceEpoch}',
                    'type': 'clear_queue',
                  }),
                ),
              if (_showSuggestions)
                Suggestions(
                  commands: _matchingCommands,
                  onApply: _applyCommand,
                  store: _store,
                ),
              if (_showFileRefs) FileRefs(refs: _fileRefs, onApply: _applyFileRef),
              // 按键条放在输入框上方、参与布局（不是浮层）：
              // 既不遮挡输入框，也不遮消息
              if (_pendingImages.isNotEmpty)
                PendingImages(
                  images: _pendingImages,
                  onShowUndo: (message, onUndo) => showUndoSnack(context, message, onUndo),
                  onRemove: (img) => setState(() => _pendingImages.remove(img)),
                  onInsert: (i, img) => setState(
                    () => _pendingImages.insert(i.clamp(0, _pendingImages.length), img),
                  ),
                ),
              // 误发保护：发送后的几秒里给一条看得见、点得到的「撤回」
              if (_undoText != null) UndoBar(onUndo: _undoLastSend),
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
                TurnFooter(
                  store: _store,
                  chat: chat,
                  onContinue: _continueRun,
                  onRedo: () => _redoLast(chat),
                  onSummary: () => showTurnSummarySheet(context, _store.turnSummary!),
                ),
              ChatComposer(
                input: _input,
                inputFocus: _inputFocus,
                running: chat.isRunning,
                keyBarVisible: _keyBarVisible,
                onSend: _send,
                onAbort: () => _store.abort(),
                onShowMenu: () => showInputMenuSheet(
                context,
                input: _input,
                templates: _templates,
                onTemplatesChanged: (items) => setState(() => _templates = items),
                onInsert: _insertIntoInput,
                onPickImage: _pickImage,
                onPickFile: _pickFile,
                onPaste: _pasteClipboardText,
                ),
                onToggleKeyBar: _toggleKeyBar,
                ),
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
  /// 模型 + 思考等级的浮动切换器。
  ///
  /// 只改**当前会话**：pi 的 set_model / set_thinking_level 写的是会话记录，
  /// 不动设置文件里的默认值 —— 所以「重启后保持」是会话级别保持，
  /// 新会话仍然用你配的默认模型（这一条在验证记录里实测过）。
  /// 待发送图片的缩略行（在输入框上方）：让用户看清「这条消息带了什么」
  /// ＋ 菜单：素材（相册 / 文件 / 剪贴板）+ 常用语模板。
  ///
  /// 手机上没有文件管理器可用，「把东西给 agent」就这三条路，
  /// 所以合成一个入口，而不是在输入框旁摆三个小图标。
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

  /// 会话信息 + 分支树。
  ///
  /// pi 的会话是一棵树（fork / 编辑重发都会长出分支），
  /// 手机上先用一个只读列表把它展示出来（切换分支需要 AgentSessionRuntime，待接）。
  /// 从某条历史消息分出一条新会话。
  ///
  /// 与「切换分支」的区别：切换是同一个会话内换路径，
  /// 这里是**另开一条会话**从该点往后走，原会话保持不动。
  Future<void> _forkFrom(String entryId, String preview) async {
    final confirmed = await confirmForkDialog(context, entryId: entryId, preview: preview);
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
    final choice = await confirmNavigateDialog(context, targetId: targetId, preview: preview);
    final summarize = choice?.summarize ?? false;
    final confirmed = choice != null;
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
  /// 把树压成带缩进的列表（深度优先）
  /// @ 引用候选列表（与命令面板同一套样式，只是数据源是工作区文件）
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

  /// 本轮改动明细：逐文件 + 口径说明（口径必须显示，否则数字看起来像漏算）
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