# -*- coding: utf-8 -*-
"""把剩余中文接线到已有词表（键 = 代码原文，精确匹配）。"""
import hashlib
from pathlib import Path
BS = chr(92); NL = chr(10)

def key(zh): return 'ui.' + hashlib.md5(zh.encode('utf-8')).hexdigest()[:10]
def esc(t): return t.replace(BS, BS + BS).replace("'", BS + "'").replace('$', BS + '$')

# (代码原文, 英文, 中文里用 $ 表示真钱符号时的显示)
JOBS = [
 ("本轮 ${snap.toolCount} 次工具调用${snap.fileCount > 0 ? ' · ${snap.fileCount} 个文件' : ''}",
  "This turn: {n} tool calls{files}"),
 ("会新建一条会话，从「${preview.isEmpty ? entryId.substring(0, 8) : preview}」往后继续。"+BS+"n",
  "Creates a new session continuing after “{preview}”."),
 ("后续对话将接在「${preview.isEmpty ? targetId.substring(0, 8) : preview}」之后。"+BS+"n",
  "Follow-up messages continue after “{preview}”."),
 (" · 整文件写入 ${file.writes}", " · {n} whole-file writes"),
 (" · 编辑 ${file.edits} 处", " · {n} edits"),
 ("插件（pi 包）${_packages.isEmpty ? '' : '（${_packages.length}）'}", "Plugins (pi packages){count}"),
 (BS+"n检查更新失败：$_packageUpdateError", "Update check failed: {e}"),
 ("${model.provider} · 上下文 ${model.contextWindow ?? '?'}", "{provider} · context {window}"),
 ("会执行 pi 的 removeAndPersist：${item.source}"+BS+"n", "Runs pi's removeAndPersist: {s}"),
 ("远程 · ${parsed.host.split('.').first}", "Remote · {host}"),
 ("公网连接失败：${_store.errorMessage ?? '未知原因'}", "Public connection failed: {e}"),
 ("手机端不内嵌预览 ${ext.replaceFirst('.', '').toUpperCase()} 文件。"+BS+"n",
  "No inline preview for {ext} files on mobile."),
 ("「${s.title}」"+BS+"n${humanBytes(s.bytes)} · ${s.messages} 条消息"+BS+"n"+BS+"n",
  "“{title}”"+BS+"n{size} · {n} messages"+BS+"n"+BS+"n"),
 ("文件会从电脑上删掉，无法恢复。${g.workspaceName} 会腾出 ${humanBytes(s.bytes)}。",
  "The file is deleted from your computer and cannot be recovered. {ws} frees {size}."),
 ("删除失败：${_store.lastError ?? '未知原因'}", "Delete failed: {e}"),
 ("失败原因：${status?.error ?? '未知'}", "Reason: {e}"),
 ("已连接 · pi ${store.health?.piVersion ?? ''}", "Connected · pi {v}"),
 ("通知已开启${notif.inDndWindow ? I18n.t('ui.13b31d4b3e') : ''}",
  "Notifications on{dnd}"),
 (" · ${entry.messageCount} 条 · ${entry.sizeLabel}", " · {n} messages · {size}"),
 ("当前默认：${store.defaultModelId ?? '—'} · ${store.defaultModelProvider ?? '—'}",
  "Current default: {name} · {provider}"),
 ("⚠ 这是**按本机落盘用量**做的估算，不是服务商官方额度。"+BS+"n",
  "⚠ Estimated from on-disk usage on this machine, not the provider's official quota."+BS+"n"),
 ("阈值：今天 "+BS+"$5 变黄、"+BS+"$10 变红。真正要紧的是「别在半夜卡住」——",
  "Threshold: $5 today turns yellow, $10 red. What matters is not stalling overnight —"),
]

rows = []
for zh, en in JOBS:
    rows.append("    '" + key(zh) + "': ('" + esc(zh) + "', '" + esc(en) + "'),")
p = Path('lib/server/i18n.dart')
s = p.read_text(encoding='utf-8')
anchor = "    'tab.start': ('开始', 'Home'),"
if '// 收尾接线' not in s:
    s = s.replace(anchor, "    // 收尾接线（键 = 代码原文，task-23）" + NL + NL.join(rows) + NL + NL + anchor, 1)
    p.write_text(s, encoding='utf-8')
print('词条:', len(rows))
for zh, en in JOBS:
    print(key(zh), '|', zh[:44])
