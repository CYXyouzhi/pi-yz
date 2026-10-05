# -*- coding: utf-8 -*-
"""补齐 28 个被误删、备份里也没有的在用 key（中文按代码语义还原）。"""
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

import re
from pathlib import Path
BS = chr(92)
def esc(t): return t.replace(BS, BS + BS).replace("'", BS + "'").replace('$', BS + '$')

PAIRS = [
 ('ui.038edd57e7', " · 编辑 ${file.edits} 处", " · {n} edits"),
 ('ui.03dd98a903', "已复制 ${_entries.length} 条日志", "Copied {n} log entries"),
 ('ui.18cd90baad', "${chat.cwd} · 已载入 ${chat.messages.length}", "{cwd} · {n} loaded"),
 ('ui.1c4dd927c8', "${diff.inHours} 小时前", "{n} h ago"),
 ('ui.2e2b64d0b1', "（图片不入缓存）", "(images are not cached)"),
 ('ui.31bbcc36d8', "未知原因", "unknown"),
 ('ui.33716d0005', "${diff.inDays} 天前", "{n} d ago"),
 ('ui.3550a72e44', "已缓存 ${list.length} 条会话 · 共 $sizeLabel", "Cached {n} sessions · {size}"),
 ('ui.3b07ed0da7', "· 未开配对窗口", "· pairing window closed"),
 ('ui.5283a21d5b', "每条 ${SessionCache.maxMessages} 条消息、", "{n} messages each,"),
 ('ui.5bbb1a9d41', "  ⇢ $childCount 条分支", "  ⇢ {n} branches"),
 ('ui.6b1e5ff3a1', "正文合计", "text total"),
 ('ui.73c4742417', "${model.provider} · 上下文 ${model.contextWindow ?? '?'}", "{provider} · context {window}"),
 ('ui.86b3ddbe40', "文件会从电脑上删掉，无法恢复。${g.workspaceName} 会腾出 ${humanBytes(s.bytes)}。",
  "The file is deleted from your computer and cannot be recovered. {ws} frees {size}."),
 ('ui.86f594ad37', "上限：最多 ${SessionCache.maxSessions} 条会话、", "Limit: at most {n} sessions,"),
 ('ui.96738eb2aa', " · ${entry.messageCount} 条 · ${entry.sizeLabel}", " · {n} messages · {size}"),
 ('ui.9aa63cf775', "${entry.key.toUpperCase()} 路径", "{key} path"),
 ('ui.9d3c5fe8d6', "${diff.inMinutes} 分钟前", "{n} min ago"),
 ('ui.ae4cdde650', "会执行 pi 的 removeAndPersist：${item.source}" + BS + "n",
  "Runs pi's removeAndPersist: {s}"),
 ('ui.b083df935e', "· ${entry.messageCount} 条 · ${entry.sizeLabel}", "· {n} messages · {size}"),
 ('ui.b7077d029c', "${model.provider} · 上下文 ${model.contextWindow ?? '?'}", "{provider} · context {window}"),
 ('ui.bc346bf8af', BS + "n检查更新失败：$_packageUpdateError", "Update check failed: {e}"),
 ('ui.c6729a8150', "共 ${sessions.length} 个会话活着", "{n} sessions alive"),
 ('ui.cd0d2003f0', "「${s.title}」" + BS + "n${humanBytes(s.bytes)} · ${s.messages} 条消息" + BS + "n" + BS + "n",
  "“{title}”" + BS + "n{size} · {n} messages" + BS + "n" + BS + "n"),
 ('ui.d92cca389d0', "会清掉：未发送的草稿、常用语、本地缓存。" + BS + "n", "Clears: unsent drafts, snippets, local cache."),
 ('ui.dd5666e6e0', "这是系统的要求，我们也不做偷偷保活。" + BS + "n", "This is a system requirement; we do not keep-alive secretly."),
 ('ui.ded70fe6ab', "已删除 · 腾出 ${humanBytes(s.bytes)}", "Deleted · freed {size}"),
 ('ui.eddf38f2db', " · 整文件写入 ${file.writes}", " · {n} whole-file writes"),
 ('ui.ef2e6f8ec0', "完整路径：" + BS + "n$filePath", "Full path:" + BS + "n{path}"),
]

rows = ["    '" + k + "': ('" + esc(zh) + "', '" + esc(en) + "')," for k, zh, en in PAIRS]
p = Path('lib/server/i18n.dart')
s = p.read_text(encoding='utf-8')
anchor = "  static const Map<String, (String zh, String en)> _strings = {"
have = set(re.findall(r"^\s*'([^']+)':\s*\('", s, re.M))
rows = [r for r in rows if "'" + r.split("'")[1] + "'" not in have]
s = s.replace(anchor, anchor + "\n    // 补齐误删（task-23）\n" + "\n".join(rows), 1)
p.write_text(s, encoding='utf-8')
print('补齐:', len(rows))
