import io

p = 'lib/ui/server/chat_page.dart'
s = io.open(p, encoding='utf-8').read()

# ---------- 1) 消息列表：接回调 + 横滑拉回输入框 ----------
old = """                        final message = chat.messages[
                            chat.historyHasMore ? index - 1 : index];
                        return MessageTile(
                          // 必须给 key：否则 ListView 复用 widget 时，
                          // 上一条消息的「思考展开/工具展开」状态会串到这一条上
                          key: ValueKey<String>(message.key),
                          message: message,
                          toolRun: chat.toolRunOf(message.toolCallId),
                          runOf: chat.toolRunOf,
                        );"""
new = """                        final message = chat.messages[
                            chat.historyHasMore ? index - 1 : index];
                        final tile = MessageTile(
                          // 必须给 key：否则 ListView 复用 widget 时，
                          // 上一条消息的「思考展开/工具展开」状态会串到这一条上
                          key: ValueKey<String>(message.key),
                          message: message,
                          toolRun: chat.toolRunOf(message.toolCallId),
                          runOf: chat.toolRunOf,
                          onQuote: _quoteText,
                          onEditResend: _editResend,
                        );
                        // 横滑用户消息＝把这条拉回输入框改写再发（左滑右滑都认，
                        // 手机上不用记住方向是哪个）。只对用户消息开放：拉回自己的话才有意义。
                        if (!message.isUser || message.text.trim().isEmpty) {
                          return tile;
                        }
                        return GestureDetector(
                          onHorizontalDragEnd: (details) {
                            final velocity = details.primaryVelocity ?? 0;
                            if (velocity.abs() < 260) return;
                            _editResend(message.text);
                          },
                          child: tile,
                        );"""
assert old in s, '找不到消息列表构造'
s = s.replace(old, new, 1)

# ---------- 2) 跑完 / 换会话时刷新本轮改动速览 ----------
s = s.replace("""      // 跑完再拉一次，拿到最后一轮的准确数字
      _store.loadSessionUsage();""",
"""      // 跑完再拉一次，拿到最后一轮的准确数字
      _store.loadSessionUsage();
      // 顺带数一遍本轮改了哪些文件（从 JSONL 里数，不猜）
      _store.loadTurnSummary();""", 1)

# ---------- 3) 新增方法（插在 _buildComposer 之前） ----------
methods = '''
  /// 引用：把这段文字带上引用标记塞回输入框（引用后还能补一句自己的话）
  void _quoteText(String text) {
    final quoted = text
        .trim()
        .split('\\n')
        .map((line) => '> $line')
        .join('\\n');
    final current = _input.text;
    _setInput(current.isEmpty ? '$quoted\\n\\n' : '$current\\n$quoted\\n\\n');
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
    NeuToast.show(context, message: '已拉回输入框，改完点发送', icon: IconId.pen);
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
    final ok = await _store.sendPrompt('继续');
    if (!mounted) return;
    if (!ok) {
      NeuToast.show(context, message: _store.lastError ?? '发送失败', icon: IconId.warn);
    }
  }

  /// 再来一次：重发最近一条用户消息
  Future<void> _redoLast(ChatReducer chat) async {
    final text = _lastUserText(chat);
    if (text.isEmpty) {
      NeuToast.show(context, message: '还没发过消息', icon: IconId.info);
      return;
    }
    final ok = await _store.sendPrompt(text);
    if (!mounted) return;
    if (!ok) {
      NeuToast.show(context, message: _store.lastError ?? '发送失败', icon: IconId.warn);
    }
  }

  /// 删除类操作的可撤销入口。
  ///
  /// 用 SnackBar 而不是自家的 NeuToast：撤销必须有**一个可点的按钮**，
  /// NeuToast 是纯展示的（之前踩过「toast 上的按钮点不到」的坑）。
  void _showUndo(String message, VoidCallback onUndo) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13.5)),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: '撤销', onPressed: onUndo),
      ),
    );
  }

  /// 本轮改动速览 + 继续 / 再来一次。
  ///
  /// 放在输入框正上方：这一条说的是「刚刚这一轮做了什么」，
  /// 视线自然落在即将输入的地方，不跟消息流抢位置。
  Widget _buildTurnFooter(NeuTokens t, ChatReducer chat) {
    final summary = _store.turnSummary;
    final hasChanges = summary != null && !summary.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
      child: Row(
        children: [
          if (hasChanges)
            Flexible(
              child: NeuPressable(
                onTap: () => _showTurnSummarySheet(summary),
                flat: true,
                radius: NeuRadii.sm,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NeuIcon(IconId.pen, size: 12, color: t.accentInk),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '本轮改动 ${summary.files.length} 个文件 +${summary.added}/-${summary.removed}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: t.accentInk),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Spacer(),
          _footerAction(t, IconId.send, '继续', _continueRun),
          const SizedBox(width: 6),
          _footerAction(t, IconId.sync, '再来一次', () => _redoLast(chat)),
        ],
      ),
    );
  }

  Widget _footerAction(NeuTokens t, IconId icon, String label, VoidCallback onTap) {
    return NeuPressable(
      onTap: onTap,
      flat: true,
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeuIcon(icon, size: 12, color: t.muted),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: t.muted)),
        ],
      ),
    );
  }

  /// 本轮改动明细：逐文件 + 口径说明（口径必须显示，否则数字看起来像漏算）
  void _showTurnSummarySheet(TurnSummary summary) {
    final t = context.neu;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: EdgeInsets.fromLTRB(14, 0, 14, 14 + MediaQuery.paddingOf(sheetContext).bottom),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NeuRadii.lg),
          gradient: NeuDecorations.raisedGradient(t),
          boxShadow: NeuShadows.raise(t),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('本轮改动',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: t.fg)),
                const SizedBox(width: 8),
                Text('${summary.files.length} 个文件 +${summary.added}/-${summary.removed}',
                    style: TextStyle(fontSize: 11.5, color: t.accentInk)),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: summary.files.length,
                itemBuilder: (_, index) {
                  final file = summary.files[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.path,
                          maxLines: 2,
                          style: TextStyle(fontSize: 12.5, color: t.fg),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '+${file.added}/-${file.removed}'
                          '${file.writes > 0 ? ' · 整文件写入 ${file.writes}' : ''}'
                          '${file.edits > 0 ? ' · 编辑 ${file.edits} 处' : ''}',
                          style: TextStyle(fontSize: 11, color: t.muted),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Text(
              summary.basis.isEmpty ? '统计口径：只算 edit / write 工具' : summary.basis,
              style: TextStyle(fontSize: 10.5, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }

'''
anchor = "  Widget _buildComposer(NeuTokens t, ChatReducer chat) {"
assert anchor in s
s = s.replace(anchor, methods + anchor, 1)

# ---------- 4) 布局里插入 footer ----------
s = s.replace("""            _buildComposer(t, chat),
          ],
          ),""",
"""            // 跑完这一轮后：本轮改动速览 + 继续 / 再来一次
            if (!chat.isRunning && chat.messages.isNotEmpty)
              _buildTurnFooter(t, chat),
            _buildComposer(t, chat),
          ],
          ),""", 1)

# ---------- 5) 换会话时也刷新一次 ----------
s = s.replace("""    final sid = _store.currentSessionId;
    if (sid != _draftSessionId) {""",
"""    final sid = _store.currentSessionId;
    if (sid != _draftSessionId) {
      // 换会话：这条速览也得跟着换
      _store.loadTurnSummary();""", 1)

# ---------- 6) 移除待发图片 → 可撤销 ----------
s = s.replace("""              child: NeuPressable(
                // 点缩略图就是移除（想反悔）
                onTap: () => setState(() => _pendingImages.remove(image)),""",
"""              child: NeuPressable(
                // 点缩略图就是移除，但给一条可撤销的提示 ——
                // 手机上误触缩略图太容易了，直接没了会让人重新选一遍图
                onTap: () {
                  final index = _pendingImages.indexOf(image);
                  setState(() => _pendingImages.remove(image));
                  _showUndo('已移除「${image.name}」', () {
                    if (!mounted) return;
                    setState(() => _pendingImages.insert(
                        index.clamp(0, _pendingImages.length), image));
                  });
                },""", 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('chat_page.dart 已改（task-9）')
