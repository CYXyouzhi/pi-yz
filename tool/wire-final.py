# -*- coding: utf-8 -*-
"""i18n 收尾：把 lib/server 与 lib/main 剩余的运行时文案全部接线。
约定（这轮踩过的坑）：中文原文逐字匹配；英文里用 {a} {b} 按中文插值出现顺序。
"""
import hashlib, re
from pathlib import Path
BS = chr(92)

def key(zh): return 'ui.' + hashlib.md5(zh.encode('utf-8')).hexdigest()[:10]
def esc(t): return t.replace(BS, BS + BS).replace("'", BS + "'").replace('$', BS + '$')

# ---------- A. 走 i18n 词表的（用户可见） ----------
M = [
    # diagnose.dart（诊断页）
    ("连接超时（对方在 8 秒内没有应答）", "Connection timed out (no response within 8s)"),
    ("常见原因：IP 不在同一网段、电脑防火墙挡了这个端口、服务端没在监听 0.0.0.0",
     "Common causes: different subnet, firewall blocking the port, or the server not listening on 0.0.0.0"),
    ("域名解析不了（DNS 查不到这个名字）", "DNS lookup failed for this name"),
    ("检查名字有没有打错；不确定就直接填电脑的局域网 IP（形如 192.168.x.x）",
     "Check the spelling, or use the computer's LAN IP (e.g. 192.168.x.x)"),
    ("端口通到主机了，但没人监听（连接被拒绝）", "Host reachable but nothing is listening (connection refused)"),
    ("电脑上服务端可能没启动，或端口不对；在电脑上执行 pi-mobile server start 再试",
     "The server may not be running, or the port is wrong; run “pi-mobile server start” on your computer"),
    ("找不到这台主机（不在同一网络里）", "Host not found (not on the same network)"),
    ("确认手机和电脑连的是同一个 Wi-Fi，且电脑没开防火墙隔离",
     "Make sure both are on the same Wi-Fi and firewall isolation is off"),
    ("网络错误：$osMessage", "Network error: {msg}"),
    ("先在浏览器打开 http://<电脑IP>:30142/api/health 看能不能出 JSON",
     "Open http://<computer-ip>:30142/api/health in a browser and check for JSON"),
    ("未知错误：$error", "Unknown error: {e}"),
    ("把这条导出给开发者", "Export this for the developer"),
    ("(空)", "(empty)"), ("全部通过", "All passed"), ("没有采集到结果", "No results collected"),
    ("${failed.first.title} 有问题", "{title} has a problem"),
    ("pi-mobile 连接诊断", "pi-mobile connection diagnosis"),
    ("时间：${startedAt.toIso8601String()}", "Time: {t}"),
    ("耗时：${elapsed.inMilliseconds} ms", "Elapsed: {n} ms"),
    ("目标：$host:$port", "Target: {host}:{port}"),
    ("默认工作区：${defaultCwd ?? ''}", "Default workspace: {cwd}"),
    ("[通过]", "[PASS]"), ("[失败]", "[FAIL]"),
    ("        下一步：${step.hint}", "        Next: {hint}"),
    ("地址解析", "DNS resolution"), ("端口可达性", "Port reachability"),
    ("$host:$port 可连接（${tcpMs.inMilliseconds} ms）", "{host}:{port} reachable ({n} ms)"),
    ("地址没解析出来，跳过", "Address not resolved — skipped"), ("先把地址填对", "Fix the address first"),
    ("健康检查", "Health check"), ("三次请求都没成功", "All three requests failed"),
    ("端口能连上但 HTTP 不通，通常是连到了别的服务（确认端口没被别的程序占用）",
     "The port opens but HTTP fails — usually another service on that port; check it"),
    ("健康检查与延迟", "Health check & latency"),
    ("3 次取样 · 最快 ${fastest}ms · 平均 ${average}ms", "3 samples · fastest {f}ms · average {a}ms"),
    ("服务端信息", "Server info"), ("pi $piVersion · 活跃会话 $active", "pi {v} · {n} active sessions"),
    ("鉴权", "Authentication"), ("token 被接受", "Token accepted"),
    ("token 不正确（服务端拒绝了认证）", "Invalid token (the server rejected it)"),
    ("用配对码重新配对，或从电脑端启动日志里复制最新 token",
     "Pair again with the pairing code, or copy the latest token from the server log"),
    ("服务端可能版本不匹配，看看要不要更新", "Possible version mismatch — consider updating"),
    # server_store.dart（运行时 toast / 状态）
    ("没连上：${errorMessage ?? lastError ?? ''}", "Not connected: {e}"),
    ("已自动重连", "Reconnected automatically"),
    ("离开期间新增 $added 条", "{n} new while you were away"),
    ("离开了 ${away.inMinutes} 分钟", "Away for {n} minutes"),
    ("离开了 ${away.inSeconds} 秒", "Away for {n} seconds"),
    ("会话已关闭", "Session closed"),
    ("还没有工作区：先在设置里填默认工作区", "No workspace yet — set a default workspace in Settings"),
    ("会话名不能为空", "Session name cannot be empty"),
    ("重命名失败", "Rename failed"),
    ("先打开一条会话", "Open a session first"),
    ("复制会话失败", "Copying the session failed"),
    ("分出新会话失败", "Forking a new session failed"),
    ("切换分支失败", "Switching branch failed"),
    ("预览失败：${error.message}", "Preview failed: {e}"),
    ("已上传 $name（${size ?? bytes.length} 字节）", "Uploaded {n} ({s} bytes)"),
    ("上传失败：${error.message}", "Upload failed: {e}"),
    ("已新建 worktree", "Worktree created"),
    ("新建失败：${error.message}", "Create failed: {e}"),
    ("已删除 worktree", "Worktree deleted"),
    ("删除失败：${error.message}", "Delete failed: {e}"),
    ("已安装 $source", "Installed {s}"),
    ("已卸载 $source", "Uninstalled {s}"),
    ("更新完成", "Update complete"),
    ("$action 失败：${error.message}", "{a} failed: {e}"),
    ("读文件失败：${error.message}", "Reading the file failed: {e}"),
    ("git 查询失败：${error.message}", "git query failed: {e}"),
    ("取 diff 失败：${error.message}", "Fetching the diff failed: {e}"),
    ("已保存 MCP 服务器 $name", "MCP server {n} saved"),
    ("已删除 MCP 服务器 $name", "MCP server {n} deleted"),
    ("登录启动失败：${error.message}", "Login failed to start: {e}"),
    ("已退出 $provider", "Signed out of {p}"),
    ("退出失败：${error.message}", "Sign-out failed: {e}"),
    ("已保存 $provider 的 Key", "Saved the key for {p}"),
    ("保存失败：${error.message}", "Save failed: {e}"),
    ("已删除 $provider 的凭据", "Deleted the credentials for {p}"),
    ("导出失败：${error.message}", "Export failed: {e}"),
    ("没连上服务端，切不了模型", "Not connected — cannot switch models"),
    ("切换模型失败", "Switching the model failed"),
    ("没连上服务端，改不了思考等级", "Not connected — cannot change the thinking level"),
    ("设置思考等级失败", "Setting the thinking level failed"),
]

VAR = re.compile(r'\$\{[^}]+\}|\$[A-Za-z_]\w*')
PH = re.compile(r'\{(\w+)\}')

# 1) 写词条
p = Path('lib/server/i18n.dart')
s = p.read_text(encoding='utf-8')
have = set(re.findall(r"^\s*'([^']+)':\s*\('", s, re.M))
rows = []
for zh, en in M:
    k = key(zh)
    if k in have: continue
    rows.append("    '" + k + "': ('" + esc(zh) + "', '" + esc(en) + "'),")
anchor = "  static const Map<String, (String zh, String en)> _strings = {"
if rows:
    s = s.replace(anchor, anchor + "\n    // lib/server 运行时层（收尾轮）\n" + "\n".join(rows), 1)
    p.write_text(s, encoding='utf-8')

# 2) 接线
FILES = ['lib/server/diagnose.dart', 'lib/server/server_store.dart']
total = 0
for f in FILES:
    t = Path(f).read_text(encoding='utf-8')
    for zh, en in M:
        lit = "'" + zh + "'"
        if lit not in t: continue
        vs, phs = VAR.findall(zh), PH.findall(en)
        if vs and len(vs) == len(phs):
            args = ', '.join("'" + a + "': " + b.replace('${', '').replace('}', '').replace('$', '')
                             for a, b in zip(phs, vs))
            rep = "I18n.tp('" + key(zh) + "', {" + args + "})"
        elif not vs:
            rep = "I18n.t('" + key(zh) + "')"
        else:
            continue
        total += t.count(lit)
        t = t.replace(lit, rep)
    if 'I18n.t' in t and "import 'i18n.dart';" not in t:
        t = re.sub(r"^(import [^\n]+\n)", r"\1import 'i18n.dart';\n", t, count=1, flags=re.M)
    Path(f).write_text(t, encoding='utf-8')

# ---------- B. notification_center 的调试日志：直接改英文（面向开发者，不进词表） ----------
B = [
    ('通知栏快速回复：', 'quick reply from notification: '),
    ('通知点击直达会话 ', 'notification tap → session '),
    ('压掉一条：', 'suppressed one: '),
    ('发送失败：', 'send failed: '),
    (' · store变更=', ' · storeChanged='),
    (' · 阈值=', ' · threshold='),
    (' · 最近通知=', ' · lastNotified='),
    (' · 运行中=', ' · running='),
    (' · 距上次输出 ', ' · idle for '),
    (' · 已提醒过=', ' · alreadyNotified='),
    (' · 压掉 ', ' · suppressed '),
]
p = Path('lib/server/notification_center.dart')
s = p.read_text(encoding='utf-8')
b = 0
for zh, en in B:
    b += s.count(zh); s = s.replace(zh, en)
b += s.count(" 条');"); s = s.replace(" 条');", "');")
p.write_text(s, encoding='utf-8')

# ---------- C. 截断标记与 App 标题（插值里嵌 I18n.t） ----------
C = []
p = Path('lib/server/chat_models.dart')
s = p.read_text(encoding='utf-8')
for zh, en, k in [("…（已截断）", "…(truncated)", 'ui.trunc1')]:
    pat = "'" + zh + BS + "n" + "${"
    if pat in s:
        # 词条
        s = s.replace(pat, "'${I18n.t('" + k + "')}" + BS + "n" + "${")
        C.append((k, en))
p.write_text(s, encoding='utf-8')

p = Path('lib/server/session_cache.dart')
s = p.read_text(encoding='utf-8')
zh = "（离线缓存截断）"
if "'${text.substring(0, max)}" + zh + "'" in s:
    s = s.replace("'${text.substring(0, max)}" + zh + "'", "'${text.substring(0, max)}${I18n.t('ui.offcut')}'")
    C.append(('ui.offcut', "(offline cache truncated)"))
p.write_text(s, encoding='utf-8')

p = Path('lib/main.dart')
s = p.read_text(encoding='utf-8')
if "'pi 远程'" in s:
    s = s.replace("'pi 远程'", "I18n.t('ui.appshort')")
    C.append(('ui.appshort', "pi remote"))
    if "server/i18n.dart" not in s:
        s = re.sub(r"^(import [^\n]+\n)", r"\1import 'server/i18n.dart';\n", s, count=1, flags=re.M)
p.write_text(s, encoding='utf-8')

# C 的词条补进词表
if C:
    p = Path('lib/server/i18n.dart')
    s = p.read_text(encoding='utf-8')
    have = set(re.findall(r"^\s*'([^']+)':\s*\('", s, re.M))
    add = ["    '" + k + "': ('" + esc(zh_) + "', '" + esc(en_) + "'),"
           for (k, en_), zh_ in zip(C, ["…（已截断）", "（离线缓存截断）", "pi 远程"]) if k not in have]
    if add:
        s = s.replace(anchor, anchor + "\n    // 截断标记与 App 标题\n" + "\n".join(add), 1)
        p.write_text(s, encoding='utf-8')

print('词条新增', len(rows) + len(C), '· A 段替换', total, '· B 段', b, '· C 段', len(C))
