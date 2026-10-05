# -*- coding: utf-8 -*-
"""把 lib/server 运行时层剩余的用户可见文案接线（审计第三轮清单）。"""
import hashlib, re
from pathlib import Path
BS = chr(92)
def key(zh): return 'ui.' + hashlib.md5(zh.encode('utf-8')).hexdigest()[:10]
def esc(t): return t.replace(BS, BS + BS).replace("'", BS + "'").replace('$', BS + '$')

# (中文原文, 英文) —— 中文原文必须与代码里逐字一致
M = [
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
 ("发送到 $target 失败：$error", "Failed to send to {target}: {e}"),
 ("服务端没给出 token", "The server returned no token"), ("配对成功", "Paired"),
 ("配对被拒绝（HTTP ${response.statusCode}）", "Pairing rejected (HTTP {code})"),
 ("配对超时：电脑没响应", "Pairing timed out: no response from the computer"),
 ("连不上 $host:$port（${error.osError?.message ?? error.message}）", "Cannot reach {host}:{port} ({e})"),
 ("接口不存在：$body", "Endpoint not found: {body}"), ("(空响应)", "(empty response)"),
 ("服务端未返回会话 id：$json", "Server returned no session id: {json}"),
 ("(空会话)", "(empty session)"), ("(未命名会话)", "(untitled session)"),
 ("Cloudflare 隧道", "Cloudflare tunnel"), ("SSH 反向隧道", "SSH reverse tunnel"),
 ("…（已截断）", "…(truncated)"), ("pi agent 会话片段", "pi agent session excerpt"),
 ("（离线缓存截断）", "(offline cache truncated)"),
]

# 1) 写词条
p = Path('lib/server/i18n.dart')
s = p.read_text(encoding='utf-8')
have = set(re.findall(r"^\s*'([^']+)':\s*\('", s, re.M))
rows = ["    '" + key(zh) + "': ('" + esc(zh) + "', '" + esc(en) + "')," for zh, en in M if key(zh) not in have]
anchor = "  static const Map<String, (String zh, String en)> _strings = {"
s = s.replace(anchor, anchor + "\n    // lib/server 运行时层（审计第三轮清单）\n" + "\n".join(rows), 1)
p.write_text(s, encoding='utf-8')

# 2) 逐文件替换（中文原文 → I18n.t/tp）
FILES = ['lib/server/diagnose.dart', 'lib/server/discovery.dart', 'lib/server/server_client.dart',
         'lib/server/server_types.dart', 'lib/server/chat_models.dart',
         'lib/server/native_bridge.dart', 'lib/server/session_cache.dart']
VAR = re.compile(r'\$\{[^}]+\}|\$[A-Za-z_]\w*')
PH = re.compile(r'\{(\w+)\}')
total = 0
for f in FILES:
    t = Path(f).read_text(encoding='utf-8')
    for zh, en in M:
        if "'" + zh + "'" not in t:
            continue
        vs = VAR.findall(zh)
        phs = PH.findall(en)
        if vs and len(vs) == len(phs):
            args = ', '.join("'" + a + "': " + b.replace('${', '').replace('}', '').replace('$', '')
                             for a, b in zip(phs, vs))
            rep = "I18n.tp('" + key(zh) + "', {" + args + "})"
        elif not vs:
            rep = "I18n.t('" + key(zh) + "')"
        else:
            continue
        n = t.count("'" + zh + "'")
        t = t.replace("'" + zh + "'", rep)
        total += n
    if 'I18n.t' in t and "import 'i18n.dart';" not in t:
        t = re.sub(r"^(import [^\n]+\n)", r"\1import 'i18n.dart';\n", t, count=1, flags=re.M)
    Path(f).write_text(t, encoding='utf-8')
print('词条', len(rows), '· 替换', total)
