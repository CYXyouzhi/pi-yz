# -*- coding: utf-8 -*-
"""把 22 处中文接线到 I18n（键 = 代码原文）。"""
import sys

# Windows 控制台默认编码是 GBK，而本脚本的输出里有 ✓ ✗ ⚠ ↔ 这类不在
# GBK 字符集内的符号 —— 直接 print 不是显示乱码，而是整个脚本抛
# UnicodeEncodeError 退出（用户直接跑就会崩）。统一把标准输出重设为 UTF-8，
# 并用 errors="replace" 兜底：万一终端仍不支持，也只是把个别字符显示成 ?，
# 不会中断脚本。
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import hashlib
from pathlib import Path
BS = chr(92)
def key(zh): return 'ui.' + hashlib.md5(zh.encode('utf-8')).hexdigest()[:10]

# (文件, 旧代码, 新代码模板 —— K 会被替换成 key)
R = []
def add(f, old, new): R.append((f, old, new))

add('lib/ui/server/activity_view.dart',
 """      ? '本轮 ${snap.toolCount} 次工具调用${snap.fileCount > 0 ? ' · ${snap.fileCount} 个文件' : ''}'""",
 """      ? I18n.tp('K', {
          'n': snap.toolCount,
          'files': snap.fileCount > 0
              ? I18n.tp('ui.038edd57e7'.replace('038edd57e7', 'x'), {'n': snap.fileCount})
              : '',
        })""")

add('lib/ui/server/chat_page.dart',
 """                        '会新建一条会话，从「${preview.isEmpty ? entryId.substring(0, 8) : preview}」往后继续。"""+BS+"""n'""",
 """                        I18n.tp('K', {
                          'preview':
                              preview.isEmpty ? entryId.substring(0, 8) : preview,
                        })""")

add('lib/ui/server/chat_page.dart',
 """                        '后续对话将接在「${preview.isEmpty ? targetId.substring(0, 8) : preview}」之后。"""+BS+"""n'""",
 """                        I18n.tp('K', {
                          'preview':
                              preview.isEmpty ? targetId.substring(0, 8) : preview,
                        })""")

add('lib/ui/server/chat_page.dart',
 """                      '${file.writes > 0 ? ' · 整文件写入 ${file.writes}' : ''}'""",
 """                      file.writes > 0
                          ? I18n.tp('K', {'n': file.writes})
                          : ''""")

add('lib/ui/server/chat_page.dart',
 """                      '${file.edits > 0 ? ' · 编辑 ${file.edits} 处' : ''}',""",
 """                      file.edits > 0 ? I18n.tp('K', {'n': file.edits}) : '',""")

add('lib/ui/server/config_page.dart',
 """_section(t, '插件（pi 包）${_packages.isEmpty ? '' : '（${_packages.length}）'}'),""",
 """_section(
          t,
          I18n.tp('K', {
            'count': _packages.isEmpty ? '' : '（${_packages.length}）',
          }),
        ),""")

add('lib/ui/server/config_page.dart',
 """child: Text('"""+BS+"""n检查更新失败：$_packageUpdateError',""",
 """child: Text(I18n.tp('K', {'e': _packageUpdateError}),""")

add('lib/ui/server/config_page.dart',
 """                '${model.provider} · 上下文 ${model.contextWindow ?? '?'}'""",
 """                I18n.tp('K',
                    {'provider': model.provider, 'window': model.contextWindow ?? '?'}),""")

add('lib/ui/server/config_page.dart',
 """      '会执行 pi 的 removeAndPersist：${item.source}"""+BS+"""n'""",
 """      I18n.tp('K', {'s': item.source})""")

add('lib/ui/server/conn_page.dart',
 """name: '远程 · ${parsed.host.split('.').first}',""",
 """name: I18n.tp('K', {'host': parsed.host.split('.').first}),""")

add('lib/ui/server/conn_page.dart',
 """message: '公网连接失败：${_store.errorMessage ?? '未知原因'}', icon: IconId.warn);""",
 """message: I18n.tp('K', {'e': _store.errorMessage ?? I18n.t('ui.31bbcc36d8')}),
              icon: IconId.warn);""")

add('lib/ui/server/files_page.dart',
 """                '手机端不内嵌预览 ${ext.replaceFirst('.', '').toUpperCase()} 文件。"""+BS+"""n'""",
 """                I18n.tp('K',
                    {'ext': ext.replaceFirst('.', '').toUpperCase()})""")

add('lib/ui/server/pool_view.dart',
 """          '「${s.title}」"""+BS+"""n${humanBytes(s.bytes)} · ${s.messages} 条消息"""+BS+"""n"""+BS+"""n'""",
 """          I18n.tp('K', {
            'title': s.title,
            'size': humanBytes(s.bytes),
            'n': s.messages,
          })""")

add('lib/ui/server/pool_view.dart',
 """          '文件会从电脑上删掉，无法恢复。${g.workspaceName} 会腾出 ${humanBytes(s.bytes)}。',""",
 """          I18n.tp('K', {
            'ws': g.workspaceName,
            'size': humanBytes(s.bytes),
          }),""")

add('lib/ui/server/pool_view.dart',
 """NeuToast.show(context, message: '删除失败：${_store.lastError ?? '未知原因'}',""",
 """NeuToast.show(context,
          message: I18n.tp('K',
              {'e': _store.lastError ?? I18n.t('ui.31bbcc36d8')}),""")

add('lib/ui/server/provider_login_sheet.dart',
 """_note(t, '失败原因：${status?.error ?? '未知'}', danger: true),""",
 """_note(t, I18n.tp('K', {'e': status?.error ?? I18n.t('ui.31bbcc36d8')}), danger: true),""")

add('lib/ui/server/settings_page.dart',
 """'已连接 · pi ${store.health?.piVersion ?? ''}',""",
 """I18n.tp('K', {'v': store.health?.piVersion ?? ''}),""")

add('lib/ui/server/settings_page.dart',
 """? '通知已开启${notif.inDndWindow ? I18n.t('ui.13b31d4b3e') : ''}'""",
 """? I18n.tp('K', {
                        'dnd': notif.inDndWindow ? I18n.t('ui.13b31d4b3e') : '',
                      })""")

add('lib/ui/server/settings_page.dart',
 """' · ${entry.messageCount} 条 · ${entry.sizeLabel}',""",
 """I18n.tp('K', {'n': entry.messageCount, 'size': entry.sizeLabel}),""")

add('lib/ui/server/settings_page.dart',
 """'当前默认：${store.defaultModelId ?? '—'} · ${store.defaultModelProvider ?? '—'}',""",
 """I18n.tp('K', {
                    'name': store.defaultModelId ?? '—',
                    'provider': store.defaultModelProvider ?? '—',
                  }),""")

add('lib/ui/server/settings_page.dart',
 """                '${model.provider} · 上下文 ${model.contextWindow ?? '?'}'""",
 """                I18n.tp('K',
                    {'provider': model.provider, 'window': model.contextWindow ?? '?'}),""")

add('lib/ui/server/usage_page.dart',
 """                        '⚠ 这是**按本机落盘用量**做的估算，不是服务商官方额度。"""+BS+"""n'\n                        // ignore: prefer_interpolation_to_compose_strings\n                        '阈值：今天 """+BS+"""$5 变黄、"""+BS+"""$10 变红。真正要紧的是「别在半夜卡住」——'""",
 """                        I18n.t('K')""")

ok = miss = 0
for f, old, new in R:
    zh = None
    for cand, _ in []:
        pass
    p = Path(f); t = p.read_text(encoding='utf-8')
    if old in t:
        # 用旧代码里第一段字符串字面量当键来源：直接对 old 内提取中文
        import re
        m = re.search(r"'([^'\n]*[\u4e00-\u9fa5][^'\n]*)'", old)
        kk = key(m.group(1)) if m else None
        if kk is None:
            print('跳过（取不到中文）:', f); miss += 1; continue
        t = t.replace(old, new.replace("'K'", "'" + kk + "'"), 1)
        p.write_text(t, encoding='utf-8'); ok += 1
    else:
        miss += 1; print('未匹配:', f, '|', old.strip().split(chr(10))[0][:52])
print(f'替换成功 {ok} · 未匹配 {miss}')
