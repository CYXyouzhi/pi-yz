import io

p = 'lib/ui/server/sessions_page.dart'
s = io.open(p, encoding='utf-8').read()

# ---------- 1) 新会话按钮：长按选模板 ----------
s = s.replace("""  Widget _buildNewSession(NeuTokens t) {
    return NeuPressable(
      onTap: _createSession,""",
"""  Widget _buildNewSession(NeuTokens t) {
    return NeuPressable(
      onTap: _createSession,
      // 长按 = 带模板新建（空会话还是点一下，老习惯不变）
      onLongPress: _creating ? null : _showTemplateSheet,""", 1)

# 按钮下方补一行说明（不然没人知道能长按）
s = s.replace("""              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 新建但未落盘的会话：pi 要等第一条消息才写文件，""",
"""              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 长按「新会话」：选一个常用语模板当开场白，或者就开个空会话。
  ///
  /// 模板直接复用输入区 ＋ 菜单里存的那份（TemplateStore），
  /// 不另建一套「会话模板」，免得同一个概念在 App 里有两份数据。
  Future<void> _showTemplateSheet() async {
    final t = context.neu;
    final templates = await TemplateStore().load();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: EdgeInsets.fromLTRB(
            14, 0, 14, 14 + MediaQuery.paddingOf(sheetContext).bottom),
        padding: const EdgeInsets.symmetric(vertical: 10),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Text('用哪句开场？',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: t.fg)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _templateRow(sheetContext, t, '空会话（自己打第一句）', ''),
                  for (final item in templates)
                    _templateRow(sheetContext, t, item, item),
                  if (templates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                      child: Text(
                        '还没有常用语。在会话页输入区的 ＋ 菜单里可以收藏（存本地，重启保留）。',
                        style: TextStyle(fontSize: 11.5, color: t.muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    await _createSession(firstMessage: picked.isEmpty ? null : picked);
  }

  Widget _templateRow(
      BuildContext sheetContext, NeuTokens t, String label, String value) {
    return NeuPressable(
      onTap: () => Navigator.of(sheetContext).pop(value),
      flat: true,
      radius: NeuRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        children: [
          NeuIcon(value.isEmpty ? IconId.bubble : IconId.pen,
              size: 15, color: t.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: t.fg),
            ),
          ),
        ],
      ),
    );
  }

  /// 新建但未落盘的会话：pi 要等第一条消息才写文件，""", 1)

# ---------- 2) _createSession 支持首句 ----------
s = s.replace("""  Future<void> _createSession() async {""",
"""  Future<void> _createSession({String? firstMessage}) async {""", 1)

s = s.replace("""    // 当前会话已经是空的（上一次点「新会话」留下的）就直接切过去。
    // 不加这一步的话，连点会造出一堆空会话（实测点 10 次就真的建了 10 条）。
    if (_store.currentSessionId != null
        && _store.chat.messages.isEmpty
        && !_store.chat.isRunning) {
      widget.onOpenChat?.call();
      return;
    }""",
"""    // 当前会话已经是空的（上一次点「新会话」留下的）就直接切过去。
    // 不加这一步的话，连点会造出一堆空会话（实测点 10 次就真的建了 10 条）。
    // 带模板时不走这条捷径：模板是要发出去的，切到旧空会话会让人以为模板没生效。
    if (firstMessage == null &&
        _store.currentSessionId != null &&
        _store.chat.messages.isEmpty &&
        !_store.chat.isRunning) {
      widget.onOpenChat?.call();
      return;
    }""", 1)

s = s.replace("""    NeuToast.show(context, message: '已新建会话', icon: IconId.check);
    widget.onOpenChat?.call();
  }""",
"""    // 模板开场白：建完会话立刻发出去，省掉「再打一遍」
    if (firstMessage != null) {
      final sent = await _store.sendPrompt(firstMessage);
      if (!mounted) return;
      if (!sent) {
        NeuToast.show(context,
            message: _store.lastError ?? '开场白没发出去', icon: IconId.warn);
      }
    }
    NeuToast.show(context, message: '已新建会话', icon: IconId.check);
    widget.onOpenChat?.call();
  }""", 1)

# ---------- 3) import ----------
if "template_store.dart" not in s:
    s = s.replace("import '../../server/server_store.dart';",
                  "import '../../server/server_store.dart';\nimport '../../server/template_store.dart';", 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('sessions_page.dart 已改（新会话模板）')
