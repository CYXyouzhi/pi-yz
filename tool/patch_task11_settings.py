import io

p = 'lib/ui/server/settings_page.dart'
s = io.open(p, encoding='utf-8').read()

# ---------- 1) 通知段：插在「界面语言」之前 ----------
anchor = "          const SizedBox(height: 20),\n          ListenableBuilder(\n            listenable: AppPrefs.instance,\n            builder: (context, _) {\n              final lang = AppPrefs.instance.lang;"
assert anchor in s, '找不到界面语言锚点'

section = '''          const SizedBox(height: 20),
          // ==================== 通知（task-11） ====================
          ListenableBuilder(
            listenable: NotificationCenter.instance,
            builder: (context, _) {
              final notif = NotificationCenter.instance;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(t, '通知'),
                  NeuRaised(
                    radius: NeuRadii.lg,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _notifToggle(
                          t,
                          '跑完提醒',
                          notif.notifyOnDone,
                          (v) async {
                            notif.notifyOnDone = v;
                            await notif.setEnabled(notif.enabled);
                          },
                        ),
                        _notifToggle(
                          t,
                          '出错提醒',
                          notif.notifyOnError,
                          (v) async {
                            notif.notifyOnError = v;
                            await notif.setEnabled(notif.enabled);
                          },
                        ),
                        _notifToggle(
                          t,
                          '需要确认时提醒',
                          notif.notifyOnNeedInput,
                          (v) async {
                            notif.notifyOnNeedInput = v;
                            await notif.setEnabled(notif.enabled);
                          },
                        ),
                        _notifToggle(
                          t,
                          '长任务看护（只在需要人时提醒）',
                          notif.watchOnly,
                          notif.setWatchOnly,
                        ),
                        _notifToggle(
                          t,
                          '通知栏快速回复',
                          notif.quickReply,
                          notif.setQuickReply,
                        ),
                        const SizedBox(height: 6),
                        _prefLabel(t, '卡住提醒（多久没新输出就提醒）'),
                        _prefChips(
                          t,
                          const [
                            ('1 分钟', 60),
                            ('2 分钟', 120),
                            ('5 分钟', 300),
                            ('10 分钟', 600),
                          ],
                          current: notif.stallSeconds.toDouble(),
                          onPick: (v) => notif.setStallSeconds(v.round()),
                        ),
                        const SizedBox(height: 10),
                        _prefLabel(t, '免打扰时段'),
                        Row(
                          children: [
                            Expanded(
                              child: _prefChips(
                                t,
                                const [
                                  ('不启用', 0),
                                  ('23→8', 1),
                                  ('22→7', 2),
                                  ('0→7', 3),
                                ],
                                current: !notif.dndEnabled
                                    ? 0
                                    : notif.dndStartHour == 22
                                        ? 2
                                        : notif.dndStartHour == 0
                                            ? 3
                                            : 1,
                                onPick: (v) {
                                  switch (v.round()) {
                                    case 0:
                                      notif.setDnd(on: false);
                                    case 1:
                                      notif.setDnd(on: true, startHour: 23, endHour: 8);
                                    case 2:
                                      notif.setDnd(on: true, startHour: 22, endHour: 7);
                                    default:
                                      notif.setDnd(on: true, startHour: 0, endHour: 7);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 权限与「被压掉的提醒」都要看得见：不然用户只会觉得「没提醒」
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notif.enabled
                                    ? '通知已开启${notif.inDndWindow ? '（当前在免打扰时段）' : ''}'
                                    : '通知已关闭',
                                style: TextStyle(fontSize: 12, color: t.muted),
                              ),
                            ),
                            NeuPressable(
                              onTap: () => notif.setEnabled(!notif.enabled),
                              radius: NeuRadii.sm,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Text(
                                notif.enabled ? '关掉通知' : '开启通知',
                                style: TextStyle(fontSize: 12.5, color: t.accentInk),
                              ),
                            ),
                          ],
                        ),
                        if (notif.suppressed.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '最近被压掉的提醒（${notif.suppressed.length} 条）',
                            style: TextStyle(fontSize: 11.5, color: t.muted),
                          ),
                          for (final item in notif.suppressed.take(3))
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '· $item',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: t.muted),
                              ),
                            ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: NeuPressable(
                                onTap: () => _testNotification(context, t),
                                radius: NeuRadii.sm,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Center(
                                  child: Text('发一条测试通知',
                                      style: TextStyle(fontSize: 12.5, color: t.accentInk)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: NeuPressable(
                                onTap: () => _pickStuckSeconds(context, t),
                                radius: NeuRadii.sm,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Center(
                                  child: Text('卡住阈值自定义…',
                                      style: TextStyle(fontSize: 12.5, color: t.muted)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),
'''
s = s.replace(anchor, section + anchor, 1)

# ---------- 2) 辅助方法 ----------
anchor2 = "  Widget _prefChips("
assert anchor2 in s
helpers = '''  /// 通知项的一行开关（开关状态直接写在右侧，不靠颜色猜）
  Widget _notifToggle(
    NeuTokens t,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13.5, color: t.fg)),
          ),
          NeuPressable(
            onTap: () => onChanged(!value),
            radius: NeuRadii.sm,
            flat: !value,
            alwaysInset: value,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              value ? '开' : '关',
              style: TextStyle(
                fontSize: 12.5,
                color: value ? t.accentInk : t.muted,
                fontWeight: value ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 卡住阈值自定义：直接输入秒数（同时验证「默认值界面可见」之外的灵活性）
  Future<void> _pickStuckSeconds(BuildContext context, NeuTokens t) async {
    final controller = TextEditingController(
      text: '${NotificationCenter.instance.stallSeconds}',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.bg,
        title: Text('卡住阈值（秒）', style: TextStyle(color: t.fg, fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: TextStyle(color: t.fg),
          decoration: const InputDecoration(hintText: '例如 90'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('取消', style: TextStyle(color: t.muted)),
          ),
          TextButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(parsed);
            },
            child: Text('保存', style: TextStyle(color: t.accentInk)),
          ),
        ],
      ),
    );
    if (value == null || value < 10) return;
    await NotificationCenter.instance.setStallSeconds(value);
  }

  /// 发一条测试通知：用户自己能确认「通知这条路是通的」
  Future<void> _testNotification(BuildContext context, NeuTokens t) async {
    final notif = NotificationCenter.instance;
    final granted = await notif.hasPermission();
    if (!granted) {
      await notif.requestPermission();
      if (!context.mounted) return;
      NeuToast.show(context,
          message: '已申请通知权限，授权后再点一次', icon: IconId.info);
      return;
    }
    final ok = await notif.sendTest();
    if (!context.mounted) return;
    NeuToast.show(
      context,
      message: ok ? '已发送（下拉通知栏看看）' : '发送失败：通知被系统拦了',
      icon: ok ? IconId.check : IconId.warn,
    );
  }

'''
s = s.replace(anchor2, helpers + anchor2, 1)

# ---------- 3) import ----------
if 'notification_center.dart' not in s:
    s = s.replace("import '../../server/i18n.dart';",
                  "import '../../server/i18n.dart';\nimport '../../server/notification_center.dart';", 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('设置页通知段已加')
