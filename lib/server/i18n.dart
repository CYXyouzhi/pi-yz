// 界面语言包。
//
// 原则（跟任务⑲的要求对齐）：
//   1. 文案集中在这里，界面文件里不再硬编码新文案；
//   2. 没翻的项**不假装翻过**：`t()` 找不到 key 会返回 key 本身，
//      调用处看到 key 就知道漏了；命令说明那类“有原文”的地方则显示原文 + 「未翻译」；
//   3. 只覆盖主路径（Tab、开始页、设置页、输入框、命令说明）——
//      剩下的中文仍是中文，这一点在文档里写清楚，不糊过去。
//

import 'package:flutter/widgets.dart';

import 'app_prefs.dart';

class I18n {
  I18n._();

  static const Map<String, (String zh, String en)> _strings = {
    'common.untranslated': ('未翻译', 'not translated'),
    // describe() 的「原文＋未翻译」标注（曾被误删，中文模式会漏出 key）
    // 服务端错误正文可能含中文，界面上只保留安全正文
    'ui.588c5be1a0': ('接口不存在', 'Endpoint not found'),
    'ui.a1a3b0d3e1': ('HTTP {code}：{body}', 'HTTP {code}: {body}'),
    // 语言切换器的三个选项（动态取用 I18n.t(option.$2)，曾被误删）
    'lang.zh': ('中文', '中文'),
    'lang.en': ('English', 'English'),
    'lang.system': ('跟随系统', 'System'),
    'ui.diagnoseBtn': ('连接诊断', 'Diagnose connection'),
    // 收尾补漏
    'ui.offcut': ('（离线缓存截断）', '(offline cache truncated)'),
    // 收尾：短片段
    'ui.9d2957f54f': ('默认工作区：', 'Default workspace: '),
    'ui.23ab4cb7b6': ('没连上：', 'Not connected: '),
    'ui.8027d6f830': ('原因未知', '(reason unknown)'),
    // 截断标记与 App 标题
    'ui.trunc1': ('…（已截断）', '…(truncated)'),
    'ui.appshort': ('pi remote', 'pi remote'),
    // lib/server 运行时层（收尾轮）
    'ui.0569d5987b': ('已自动重连', 'Reconnected automatically'),
    'ui.bb45590174': ('离开期间新增 {n} 条', '{n} new while you were away'),
    'ui.fe3338e328': ('离开了 {n} 分钟', 'Away for {n} min'),
    'ui.ec9f506f82': ('离开了 {n} 秒', 'Away for {n} sec'),
    'ui.166cc5d6de': (
      '还没有工作区：先在设置里填默认工作区',
      'No workspace yet — set a default workspace in Settings',
    ),
    'ui.f1c5acdc4a': ('会话名不能为空', 'Session name cannot be empty'),
    'ui.37ba51a4c6': ('重命名失败', 'Rename failed'),
    'ui.e410196151': ('先打开一条会话', 'Open a session first'),
    'ui.cd2f6e9c3f': ('复制会话失败', 'Copying the session failed'),
    'ui.fd86967e02': ('分出新会话失败', 'Forking a new session failed'),
    'ui.5b9eb774d9': ('切换分支失败', 'Switching branch failed'),
    'ui.c621e5e25b': ('预览失败：{e}', 'Preview failed: {e}'),
    'ui.78b07cb72a': ('已上传 {n}（{s} 字节）', 'Uploaded {n} ({s} bytes)'),
    'ui.384e5130bb': ('上传失败：{e}', 'Upload failed: {e}'),
    'ui.f8e34f3543': ('已新建 worktree', 'Worktree created'),
    'ui.106406ad4d': ('新建失败：{e}', 'Create failed: {e}'),
    'ui.3e6c4f97df': ('已删除 worktree', 'Worktree deleted'),
    'ui.e5d81c0a03': ('删除失败：{e}', 'Delete failed: {e}'),
    'ui.53ff7b7c01': ('已安装 {s}', 'Installed {s}'),
    'ui.9e1bfdc29d': ('已卸载 {s}', 'Uninstalled {s}'),
    'ui.56a851859a': ('更新完成', 'Update complete'),
    'ui.274b2eafab': ('{a} 失败：{e}', '{a} failed: {e}'),
    'ui.f55e153cb5': ('读文件失败：{e}', 'Reading the file failed: {e}'),
    'ui.5e541876ac': ('git 查询失败：{e}', 'git query failed: {e}'),
    'ui.151f0ad89b': ('取 diff 失败：{e}', 'Fetching the diff failed: {e}'),
    'ui.68e0c6d05e': ('已保存 MCP 服务器 {n}', 'MCP server {n} saved'),
    'ui.24fa0cd945': ('已删除 MCP 服务器 {n}', 'MCP server {n} deleted'),
    'ui.6076ca52e7': ('登录启动失败：{e}', 'Login failed to start: {e}'),
    'ui.ae61e7d374': ('已退出 {p}', 'Signed out of {p}'),
    'ui.ffbd30b3e8': ('退出失败：{e}', 'Sign-out failed: {e}'),
    'ui.a234cc694b': ('已保存 {p} 的 Key', 'Saved the key for {p}'),
    'ui.e1ecbe92e3': ('保存失败：{e}', 'Save failed: {e}'),
    'ui.8ec238cd15': ('已删除 {p} 的凭据', 'Deleted the credentials for {p}'),
    'ui.eb0814d40c': ('导出失败：{e}', 'Export failed: {e}'),
    'ui.c0e94b1077': ('没连上服务端，切不了模型', 'Not connected — cannot switch models'),
    'ui.929511ecf0': ('切换模型失败', 'Switching the model failed'),
    'ui.4eb6435474': (
      '没连上服务端，改不了思考等级',
      'Not connected — cannot change the thinking level',
    ),
    'ui.0867017254': ('设置思考等级失败', 'Setting the thinking level failed'),
    // lib/server 运行时层（审计第三轮清单）

    // lib/server 运行时层（审计第三轮清单）
    'ui.4ac56645f2': (
      '连接超时（对方在 8 秒内没有应答）',
      'Connection timed out (no response within 8s)',
    ),
    'ui.ec95d46034': (
      '常见原因：IP 不在同一网段、电脑防火墙挡了这个端口、服务端没在监听 0.0.0.0',
      'Common causes: different subnet, firewall blocking the port, or the server not listening on 0.0.0.0',
    ),
    'ui.357bb00861': ('域名解析不了（DNS 查不到这个名字）', 'DNS lookup failed for this name'),
    'ui.5590f8562f': (
      '检查名字有没有打错；不确定就直接填电脑的局域网 IP（形如 192.168.x.x）',
      'Check the spelling, or use the computer\'s LAN IP (e.g. 192.168.x.x)',
    ),
    'ui.b1f0198098': (
      '端口通到主机了，但没人监听（连接被拒绝）',
      'Host reachable but nothing is listening (connection refused)',
    ),
    'ui.fa0b5ce725': (
      '电脑上服务端可能没启动，或端口不对；在电脑上执行 pi-yz server start 再试',
      'The server may not be running, or the port is wrong; run “pi-yz server start” on your computer',
    ),
    'ui.e952bae0ad': (
      '找不到这台主机（不在同一网络里）',
      'Host not found (not on the same network)',
    ),
    'ui.f9f149dbc2': (
      '确认手机和电脑连的是同一个 Wi-Fi，且电脑没开防火墙隔离',
      'Make sure both are on the same Wi-Fi and firewall isolation is off',
    ),
    'ui.def254a2e0': ('网络错误：{msg}', 'Network error: {msg}'),
    'ui.d057f4b6c9': (
      '先在浏览器打开 http://<电脑IP>:30142/api/health 看能不能出 JSON',
      'Open http://<computer-ip>:30142/api/health in a browser and check for JSON',
    ),
    'ui.3dafb8747f': ('未知错误：{e}', 'Unknown error: {e}'),
    'ui.8cf5b87a5a': ('把这条导出给开发者', 'Export this for the developer'),
    'ui.669d30fa77': ('全部通过', 'All passed'),
    'ui.145eaa2097': ('没有采集到结果', 'No results collected'),
    'ui.602e8032ea': ('{title} 有问题', '{title} has a problem'),
    'ui.516289bc09': ('时间：{t}', 'Time: {t}'),
    'ui.b5ed9e3f60': ('耗时：{n} ms', 'Elapsed: {n} ms'),
    'ui.6416d2cfda': ('目标：{host}:{port}', 'Target: {host}:{port}'),
    'ui.17513e53f2': ('[通过]', '[PASS]'),
    'ui.7b0b07b98f': ('[失败]', '[FAIL]'),
    'ui.62e1c6d089': ('        下一步：{hint}', '        Next: {hint}'),
    'ui.7c27423840': ('地址解析', 'DNS resolution'),
    'ui.0cd14773ed': ('端口可达性', 'Port reachability'),
    'ui.9fa43bc9a3': (
      '{host}:{port} 可连接（{n} ms）',
      '{host}:{port} reachable ({n} ms)',
    ),
    'ui.469c7e631a': ('地址没解析出来，跳过', 'Address not resolved — skipped'),
    'ui.391fd0df8f': ('先把地址填对', 'Fix the address first'),
    'ui.a0da7db9e8': ('健康检查', 'Health check'),
    'ui.6c95da9a4c': ('三次请求都没成功', 'All three requests failed'),
    'ui.032d279244': (
      '端口能连上但 HTTP 不通，通常是连到了别的服务（确认端口没被别的程序占用）',
      'The port opens but HTTP fails — usually another service on that port; check it',
    ),
    'ui.eabef5aeca': ('健康检查与延迟', 'Health check & latency'),
    'ui.0f83db566b': (
      '3 次取样 · 最快 {f}ms · 平均 {a}ms',
      '3 samples · fastest {f}ms · average {a}ms',
    ),
    'ui.62f64d669e': ('服务端信息', 'Server info'),
    'ui.5c1455e056': ('pi {v} · 活跃会话 {n}', 'pi {v} · {n} active sessions'),
    'ui.1abcfdd7b6': ('鉴权', 'Authentication'),
    'ui.97d3f39246': ('token 被接受', 'Token accepted'),
    'ui.0264d45a05': (
      'token 不正确（服务端拒绝了认证）',
      'Invalid token (the server rejected it)',
    ),
    'ui.eebdd18b00': (
      '用配对码重新配对，或从电脑端启动日志里复制最新 token',
      'Pair again with the pairing code, or copy the latest token from the server log',
    ),
    'ui.75c322d9f5': (
      '服务端可能版本不匹配，看看要不要更新',
      'Possible version mismatch — consider updating',
    ),
    'ui.d30d228229': ('发送到 {target} 失败：{e}', 'Failed to send to {target}: {e}'),
    'ui.06e2174d32': ('服务端没给出 token', 'The server returned no token'),
    'ui.942ce60e9f': ('配对成功', 'Paired'),
    'ui.d5c5d56576': ('配对被拒绝（HTTP {code}）', 'Pairing rejected (HTTP {code})'),
    'ui.50fec36c81': (
      '配对超时：电脑没响应',
      'Pairing timed out: no response from the computer',
    ),
    'ui.53eb8845bf': (
      '连不上 {host}:{port}（{e}）',
      'Cannot reach {host}:{port} ({e})',
    ),
    'ui.07d8607b07': ('接口不存在：{body}', 'Endpoint not found: {body}'),
    'ui.ee85679cef': ('(空响应)', '(empty response)'),
    'ui.27c192ed70': (
      '服务端未返回会话 id：{json}',
      'Server returned no session id: {json}',
    ),
    'ui.87bb8d621e': ('(空会话)', '(empty session)'),
    'ui.648679c656': ('(未命名会话)', '(untitled session)'),
    'ui.0b436778d8': ('Cloudflare 隧道', 'Cloudflare tunnel'),
    'ui.2c028e4a7b': ('SSH 反向隧道', 'SSH reverse tunnel'),
    'ui.61a53db098': ('pi agent 会话片段', 'pi agent session excerpt'),
    // 错误与状态提示（审计第三轮点名）
    'ui.d2a6633d48': ('读用量失败：{e}', 'Failed to read usage: {e}'),
    'ui.c3f797f056': ('读累计用量失败：{e}', 'Failed to read total usage: {e}'),
    'ui.8210d7f767': ('读默认模型失败：{e}', 'Failed to read the default model: {e}'),
    'ui.859d589642': (
      '没连上服务端，改不了默认模型',
      'Not connected — cannot change the default model',
    ),
    'ui.435b4754a0': (
      '载入超时。服务端可能在忙，或会话过大。',
      'Load timed out. The server may be busy, or the session is too large.',
    ),
    'ui.1a5741451f': ('尚未连接服务端', 'Not connected to the server yet'),
    'ui.37c4dd9994': ('未指定工作目录', 'No working directory specified'),
    'ui.74c6f09b91': ('事件流出错', 'Event stream error'),
    'ui.44a5b4dcf1': ('回应失败：{e}', 'Reply failed: {e}'),
    'ui.fcaecec77a': ('连接已断开，请手动重连', 'Connection lost — reconnect manually'),
    // 通知文案（审计第三轮点名）
    'ui.8f4c857389': ('通知总开关关着', 'Notification master switch is off'),
    'ui.18d7b3c71a': ('免打扰时段 {a}:00–{b}:00', 'Do-not-disturb {a}:00–{b}:00'),
    'ui.7c54beebb8': ('看护模式：跑完不吵', 'Watch mode: no alert when finished'),
    'ui.094736ccd5': ('没开「跑完提醒」', '"Notify when finished" is off'),
    'ui.5492807fab': ('没开「出错提醒」', '"Notify on error" is off'),
    'ui.1b5996f581': (
      '没开「需要确认提醒」',
      '"Notify when confirmation is needed" is off',
    ),
    'ui.ade9834361': ('{label} · 需要你确认', '{label} · needs your confirmation'),
    'ui.1e91c9aeb8': ('pi 在等你选一个选项', 'pi is waiting for you to pick an option'),
    'ui.94cbe1dd74': ('{label} · 出错了', '{label} · error'),
    'ui.d99d6fe16a': ('运行失败', 'run failed'),
    'ui.c36902b0dc': ('{label} · 跑完了', '{label} · finished'),
    'ui.5a9e6a6a16': ('（没有正文输出）', '(no text output)'),
    'ui.a75650db91': ('{label} · 好像卡住了', '{label} · looks stuck'),
    'ui.53e037d7cc': (
      '已经 {idle}（阈值 {n} 秒，可在设置里改）',
      'No new output for {idle} (threshold {n}s, configurable in settings)',
    ),
    'ui.43d3089cba': ('{title}（{reason}）', '{title} ({reason})'),
    'ui.47aeb4ecf8': ('{n} 分钟', '{n} min'),
    'ui.2607898580': ('{n} 分 {m} 秒', '{n}m {m}s'),
    'ui.05be0025af': ('pi agent · 测试通知', 'pi agent · test notification'),
    'ui.062e18cf92': (
      '能看到这条，说明通知这条路是通的（点它会打开 App）',
      'If you can see this, notifications work (tapping opens the app)',
    ),
    // lib/server 运行时文案（审计第三轮点名）
    'ui.df1fd91011': ('你', 'You'),
    'ui.1edff073d4': ('回复', 'Reply'),
    'ui.cd8057fce0': ('已切换到 {p}/{m}', 'Switched to {p}/{m}'),
    'ui.4cc14a6c13': ('正在重试…', 'Retrying…'),
    'ui.c296785412': ('正在压缩上下文…', 'Compacting context…'),
    'ui.7cec835f67': ('压缩失败：{e}', 'Compaction failed: {e}'),
    'ui.cdad85d6a7': ('自动重试 {a}/{b}…', 'Auto-retry {a}/{b}…'),
    'ui.41b5785945': ('重试失败', 'Retry failed'),
    'ui.0fbd2577cd': ('会话已关闭', 'Session closed'),
    // 第五轮补：审计点名仍在的 7 处（task-23）
    'ui.836349be8d': ('· 已连接', '· connected'),
    'ui.20f9b96cf2': ('本轮 {n} 次工具调用{files}', 'Tool calls: {n}{files}'),
    'ui.30f2b16887': (' · {n} 个文件', ' · Files: {n}'),
    'ui.124ba57d80': (
      '会新建一条会话，从「{preview}」往后继续。\n',
      'Creates a new session continuing after “{preview}”.',
    ),
    'ui.558ac73c08': (
      '后续对话将接在「{preview}」之后。\n',
      'Follow-up messages continue after “{preview}”.',
    ),
    'ui.dbfff2a1f7': (
      '⚠ 这是**按本机落盘用量**做的估算，不是服务商官方额度。\n',
      '⚠ Estimated from on-disk usage on this machine, not the provider\'s official quota.\n',
    ),
    'ui.2cdecccb2e': (
      '阈值：今天 \$5 变黄、\$10 变红。真正要紧的是「别在半夜卡住」：'
          '额度用尽时 pi 会停在原地，需要到电脑上换个模型（或给服务商充值）再继续。',
      'Threshold: \$5 today turns yellow, \$10 red. What matters is not stalling overnight: '
          'when quota runs out pi stops where it is — switch model on the desktop (or top up) and carry on.',
    ),
    'ui.b7612b71c0': ('空', '(empty)'),
    // 补回误删的人工命名 key（task-23）
    'theme.system': ('跟随系统', 'System'),
    'theme.light': ('浅色', 'Light'),
    'theme.dark': ('深色', 'Dark'),
    // 补齐误删（task-23）
    'ui.038edd57e7': (' · 编辑 {n} 处', ' · Edits: {n}'),
    'ui.03dd98a903': (
      '默认模型 {provider}/{name}',
      'Default model {provider}/{name}',
    ),
    'ui.18cd90baad': ('{cwd} · 已载入 {n}', '{cwd} · {n} loaded'),
    'ui.1c4dd927c8': (
      '今日已用 {today}，接近额度',
      'Used {today} today, nearing the limit',
    ),
    'ui.2e2b64d0b1': ('（图片不入缓存）', '(images are not cached)'),
    'ui.31bbcc36d8': ('未知原因', 'unknown'),
    'ui.33716d0005': ('pi {v} · {n} 个会话', 'pi {v} · Sessions: {n}'),
    'ui.3550a72e44': ('连接失败：{e}', 'Connection failed: {e}'),
    'ui.3b07ed0da7': ('· 未开配对窗口', '· pairing window closed'),
    'ui.5283a21d5b': (
      '今日已用 {today}，额度已用完',
      'Used {today} today, quota exhausted',
    ),
    'ui.5bbb1a9d41': ('  ⇢ {n} 条分支', '  ⇢ {n} branch(es)'),
    'ui.6b1e5ff3a1': ('正文合计', 'text total'),
    'ui.86b3ddbe40': (
      '文件会从电脑上删掉，无法恢复。\n删掉后能腾出 {size}（工作区：{ws}）。',
      'The file is deleted from your computer and cannot be recovered.\nThis frees {size} (workspace: {ws}).',
    ),
    'ui.96738eb2aa': (' · {n} 条 · {size}', ' · Messages: {n} · {size}'),
    'ui.9aa63cf775': ('{key} 路径', '{key} path'),
    'ui.9d3c5fe8d6': ('pi 插件{count}', 'pi plugins{count}'),
    'ui.ae4cdde650': (
      '会执行 pi 的 removeAndPersist：{s}\n',
      'Runs pi\'s removeAndPersist: {s}',
    ),
    'ui.b083df935e': ('pi {v}', 'pi {v}'),
    'ui.b7077d029c': (
      '{provider} · 上下文 {window}',
      '{provider} · context {window}',
    ),
    'ui.bc346bf8af': ('\n检查更新失败：{e}', 'Update check failed: {e}'),
    'ui.c6729a8150': ('登录失败：{e}', 'Login failed: {e}'),
    'ui.cd0d2003f0': (
      '「{title}」\n{size} · {n} 条消息\n\n',
      '“{title}”\n{size} · Messages: {n}\n\n',
    ),
    'ui.d92cca389d0': (
      '会清掉：未发送的草稿、常用语、本地缓存。\n',
      'Clears: unsent drafts, snippets, local cache.',
    ),
    'ui.dd5666e6e0': (
      '这是系统的要求，我们也不做偷偷保活。\n',
      'This is a system requirement; we do not keep-alive secretly.',
    ),
    'ui.ded70fe6ab': ('提醒已开启{dnd}', 'Notifications on{dnd}'),
    'ui.eddf38f2db': (' · 整文件写入 {n}', ' · {n} whole-file writes'),
    'ui.ef2e6f8ec0': ('完整路径：\n{path}', 'Full path:\n{path}'),
    // 恢复：删闲置词条时误删的在用 key（task-23）
    'tab.chat': ('会话', 'Chat'),
    'tab.settings': ('设置', 'Settings'),
    'tab.start': ('开始', 'Home'),
    'ui.70a59fefaa': ('· 已截断', '· truncated'),
    'ui.af181ac8b2': ('· 支持思考', '· supports thinking'),
    'ui.b4912bca07': ('· 可配对', '· pairable'),
    'ui.d99dc368ab': (
      '手机端不内嵌预览 {ext}',
      'No inline preview for {ext} on mobile',
    ),
    'ui.e96f1cf9ba': ('远程 · {host}', 'Remote · {host}'),
    // ============ 高频通用词（task-23 铺开的第一批）============
    // 选的是全仓出现次数最多的 20 个 UI 词（取消 21 次、删除 7 次…）。
    // 上一轮试过一次性把 463 条全塞进来，结果破坏了字面量结构、编译炸 3287 处，
    // 回滚后改成小批 + 每步 analyze，稳一点。
    'common.delete': ('删除', 'Delete'),
    'common.save': ('保存', 'Save'),
    'common.done': ('完成', 'Done'),
    'common.ok': ('确定', 'OK'),
    'common.clear': ('清空', 'Clear'),
    'common.copied': ('已复制', 'Copied'),
    'common.loading': ('读取中…', 'Loading…'),
    'common.connected': ('已连接', 'Connected'),
    'common.connecting': ('连接中…', 'Connecting…'),
    'common.disconnected': ('未连接', 'Not connected'),
    'common.connFailed': ('连接失败', 'Connection failed'),
    'common.failed': ('失败', 'Failed'),
    'common.running': ('运行中', 'Running'),
    'common.model': ('模型', 'Model'),
    'common.command': ('命令', 'Command'),
    'common.input': ('输入', 'Input'),

    // ============ 界面高频文案（task-23 铺开）============
    // 全仓出现次数最多的 UI 标题/按钮/状态，英文是人工写的。key 用 md5 前缀
    // 保证不与人工命名冲突；带变量的文案（如「已切换到 $x」）需要参数化
    // i18n，留到下一批；长尾说明性长句见 tool/i18n_coverage.py 的报告。
    'ui.5258ce61e8': ('AI 配置', 'AI settings'),
    'ui.e21425f183': ('一键断开', 'Disconnect'),
    'ui.8539b2ecd4': ('上下文占用', 'Context usage'),
    'ui.1facbf7790': ('上翻', 'Page up'),
    'ui.3c81db078c': ('下翻', 'Page down'),
    'ui.6224248126': ('不启用', 'Off'),
    'ui.d8d7ca77e9': ('中断', 'Abort'),
    'ui.aeb5271ede': ('主机地址', 'Host'),
    'ui.800dfdd902': ('今天', 'Today'),
    'ui.a2e9a7991a': ('保存图片到相册', 'Save image'),
    'ui.e383057c96': ('保存失败：系统相册没接住', 'Save failed'),
    'ui.e8ba811b3f': ('保存并使用', 'Save & use'),
    'ui.be63fac285': ('免打扰时段', 'Do not disturb'),
    'ui.a8b0c20416': ('全部', 'All'),
    'ui.3ee093d39a': ('关掉通知', 'Turn off'),
    'ui.ad8e01fe71': ('出错', 'Error'),
    'ui.56ed8b49c3': ('分享不可用（系统没接住）', 'Sharing unavailable'),
    'ui.96c2ee76cd': ('分享这段', 'Share this'),
    'ui.2d5fbafe5d': ('切换失败', 'Switch failed'),
    'ui.78fb22f373': ('删除会话', 'Delete session'),
    'ui.5e51feb8f3': ('刷新会话', 'Refresh sessions'),
    'ui.6c237fca7f': ('卡住阈值自定义…', 'Custom stall threshold…'),
    'ui.9ea3f6a5de': ('历史会话 · 按工作区', 'History · by workspace'),
    'ui.8454029f34': ('发一条测试通知', 'Send test notification'),
    'ui.1535fcfa4c': ('发送', 'Send'),
    'ui.9ca6a3440e': ('发送失败', 'Send failed'),
    'ui.bc83e0c0c2': ('取消归档', 'Unarchive'),
    'ui.066ae8d7d6': ('后台', 'Background'),
    'ui.db2728b716': ('图片数据坏了，存不了', 'Image data is broken'),
    'ui.79d3abe929': ('复制', 'Copy'),
    'ui.5f6e171c5b': ('复制为分支', 'Clone as branch'),
    'ui.ab18e30c0d': ('大', 'Large'),
    'ui.b9d0f24c4c': ('存储占用', 'Storage'),
    'ui.f3460980a4': ('实时活动', 'Live activity'),
    'ui.43e534acf9': ('宽松', 'Wide'),
    'ui.cb9bf0e70e': ('导出会话', 'Export session'),
    'ui.391b8fa9c7': ('小', 'Small'),
    'ui.20dce2c6fa': ('工具', 'Tool'),
    'ui.f8dfedcd8a': ('已保存', 'Saved'),
    'ui.69b0f68457': ('已停用', 'Disabled'),
    'ui.3586246ba6': ('已存到相册（Pictures/pi-yz）', 'Saved to Photos'),
    'ui.9db7a84fcd': ('已开启', 'Enabled'),
    'ui.06a3c99161': ('已打开分享面板', 'Share sheet opened'),
    'ui.b244d633d4': ('已新建会话', 'Session created'),
    'ui.64dfcf277f': ('常用语', 'Snippets'),
    'ui.d89ca63cd0': ('开启远程访问', 'Enable remote access'),
    'ui.bd3d0854a0': ('开始对话', 'Start chatting'),
    'ui.a1395a5eec': ('当前连接参数', 'Current parameters'),
    'ui.3b5b97cab5': ('待回话', 'Needs reply'),
    'ui.f7d2996639': ('快捷键', 'Shortcuts'),
    'ui.21d68b2de0': ('思考', 'Thinking'),
    'ui.11eead2c33': ('思考等级', 'Thinking level'),
    'ui.7e237e9459': ('成本', 'Cost'),
    'ui.3a8e52efff': ('扫描局域网', 'Scan LAN'),
    'ui.3c56ed3536': ('按工作区', 'By workspace'),
    'ui.c7abd045d8': ('按工作区看会话占了多少、清掉旧的', 'See and clean storage'),
    'ui.8d8324a89f': ('捞回来', 'Restore'),
    'ui.2629bdbfad': ('换行', 'New line'),
    'ui.c9651ff139': (
      '搜索会话（名称 / 首条消息 / 路径）',
      'Search sessions (name / first message / path)',
    ),
    'ui.def9e98b60': ('收起', 'Collapse'),
    'ui.9b55c5c9f8': ('断开', 'Disconnect'),
    'ui.42ddad2439': ('新会话', 'New session'),
    'ui.66ab5e9f24': ('新增', 'Add'),
    'ui.96a6a6ca0f': ('新建会话失败', 'Failed to create session'),
    'ui.ea4a363d8f': ('未开启', 'Off'),
    'ui.0ec94a3708': ('本月', 'This month'),
    'ui.4f1a748dda': ('本次会话', 'This session'),
    'ui.c91492851a': ('本轮已结束', 'Turn finished'),
    'ui.544fac400d': ('标准', 'Standard'),
    'ui.592ff57b9b': ('正在建立隧道…', 'Establishing tunnel…'),
    'ui.680ba4ce16': ('正在跑', 'Running'),
    'ui.c9e2c3a6fd': ('正在运行', 'Running'),
    'ui.69e74756bc': ('测试连接', 'Test connection'),
    'ui.8a31d0428f': ('添加 API Key', 'Add API Key'),
    'ui.3bd1c146b5': ('添加 MCP 服务器', 'Add MCP server'),
    'ui.3bc9ba2888': ('清空离线缓存', 'Clear offline cache'),
    'ui.56fddae514': ('点开管理', 'Manage'),
    'ui.3386da5f56': ('特大', 'Extra large'),
    'ui.7b79313922': ('用户级', 'User'),
    'ui.bd939b977d': ('用这个地址连', 'Use this address'),
    'ui.53750dd580': ('用量明细', 'Usage detail'),
    'ui.4be9b33847': ('登录 Provider', 'Sign in provider'),
    'ui.73e82552c8': ('目标', 'Target'),
    'ui.63000cee55': ('直接发送', 'Send'),
    'ui.b66f0c9549': ('看工作区目录、读文件、查 git 改动', 'Browse files and git diff'),
    'ui.87bb5bbcc3': ('空闲', 'Idle'),
    'ui.c76cfefe72': ('端口', 'Port'),
    'ui.493b7bc5ff': ('等你确认', 'Awaiting you'),
    'ui.03e59bb33c': ('紧凑', 'Compact'),
    'ui.27ca568be2': ('继续', 'Continue'),
    'ui.8e784e8cd7': ('缓存写', 'Cache write'),
    'ui.0ae4a745b0': ('缓存读', 'Cache read'),
    'ui.7c79620b1a': ('编辑重发', 'Edit & resend'),
    'ui.4cb4f622a9': ('补全', 'Complete'),
    'ui.69ffdd9247': ('请填写主机地址', 'Enter host address'),
    'ui.97d29d8430': ('调用', 'Call'),
    'ui.8ba7c3a7be': ('输出', 'Output'),
    'ui.9a75eed25e': ('还没发过消息', 'No messages yet'),
    'ui.1d1a0f3be8': ('还没有活动', 'No activity yet'),
    'ui.fb852fc6cc': ('进行中', 'In progress'),
    'ui.0959028680': ('远程访问', 'Remote access'),
    'ui.de15ce00dd': ('连接诊断', 'Connection diagnosis'),
    'ui.6eedee5f84': ('逐轮明细', 'Per-turn detail'),
    'ui.5660bcd256': ('通知', 'Notifications'),
    'ui.e33ff6aad6': ('配对', 'Pair'),
    'ui.e2a075395d': ('配对码', 'Pairing code'),
    'ui.4fcad1c9ba': ('配置名称', 'Profile name'),
    'ui.c8ce4b36cb': ('重命名', 'Rename'),
    'ui.3e654d807c': ('重命名会话', 'Rename session'),
    'ui.cead89f9f1': ('链路与代价（威胁模型）', 'Threat model'),
    'ui.98a5faeeaf': ('项目级', 'Project'),
    'ui.b6d1510faf': ('额度预警', 'Quota warning'),
    'ui.96dba48253': ('默认工作区', 'Default workspace'),
    'ui.e963f6371c': ('默认工作区路径', 'Default workspace path'),
    // 备用地址（双地址回落）：主地址连不上时自动试它。
    // 典型用法 —— 主地址填家里局域网 IP，备用填 VPN（Tailscale 之类）的 IP，
    // 这样在家走局域网、出门走 VPN，不用手动切 profile。
    // 表单分组标题：把「基本」与「远程访问」分开。备用地址是可选的高级项，
    // 平铺在必填项中间会让人以为它也得填。
    'conn.groupBasic': ('基本', 'Basics'),
    // 连接页分区。原来扫描/诊断/已保存/手动表单全平铺，用户说「设置项太杂乱了」。
    'conn.groupQuick': ('快速连接', 'Quick connect'),
    'conn.groupManual': ('手动配置', 'Manual setup'),
    // 「手动添加连接」：配置连接页底部的入口按钮。
    // 原先这里是「测试连接 / 保存并使用」一对按钮，但它们读的是页面内联
    // 表单的 controller —— 表单已经搬去 conn_edit_page 了，两个按钮永远
    // 拿到空 host，点下去只会弹「请填写主机地址」。改成直接开子页。
    'conn.manualAdd': ('手动添加连接', 'Add connection manually'),
    // 一条连接都没有时，「已保存」分组里显示的占位说明。
    'conn.noSavedYet': ('还没有保存的连接', 'No saved connections yet'),
    // 没连过就去点「连接诊断」时的提示：诊断要拿一条已知配置去查。
    'conn.diagnoseNeedsTarget': ('先添加一条连接，再诊断', 'Add a connection first'),
    // 新建会话时手动指定工作区（候选只来自历史 + 默认，没用过的目录进不来）
    // ---- 「目标」配置子页面（conn_edit_page.dart）----
    'ui.4a3d8c1f0b': ('配对成功', 'Paired'),
    'connEdit.newTitle': ('新增连接', 'New connection'),
    'connEdit.editTitle': ('编辑连接', 'Edit connection'),
    'connEdit.test': ('测试连接', 'Test'),
    'connEdit.testing': ('正在测试…', 'Testing…'),
    'connEdit.save': ('保存', 'Save'),
    'connEdit.testOk': ('连上了 · pi {pi}', 'Connected · pi {pi}'),
    'connEdit.hostRequired': ('主机地址不能为空', 'Host is required'),
    'connEdit.portInvalid': ('端口要填 1-65535 之间的数', 'Port must be 1-65535'),
    'connEdit.tokenRequired': ('token 不能为空', 'Token is required'),
    'connEdit.tokenHelpTitle': ('不知道 token 填什么？', 'Where do I get the token?'),
    'connEdit.tokenHelp1': (
      '在电脑上启动服务端时，终端里会打印一行 token（完整值）',
      'The server prints the full token in the terminal when it starts',
    ),
    'connEdit.tokenHelp2': (
      '服务端刚启动的 5 分钟内有配对码：扫描局域网后点「选中」直接填它',
      'For 5 minutes after startup there is a pairing code — use that instead',
    ),
    'connEdit.tokenHelp3': (
      '服务端启动时会打印地址与 token',
      'The server prints the address and token when it starts',
    ),
    'conn.manualWorkspace': ('手动输入路径…', 'Enter a path…'),
    'conn.manualWorkspaceHint': (
      '如 C:/Users/you/projects',
      'e.g. C:/Users/you/projects',
    ),
    'conn.groupRemote': ('远程访问（可选）', 'Remote access (optional)'),
    'conn.remoteIntro': (
      '在家走局域网、出门走 VPN —— 程序自动选能连上的那条，你不用手动切。',
      'LAN at home, VPN when away — it picks whichever answers, so you never switch manually.',
    ),
    // HTTPS 显式开关。原来只能靠在地址栏粘 https:// 或把端口填 443 隐式触发，
    // 用户根本不知道有这回事。
    'conn.useHttps': ('用 HTTPS 连接', 'Connect over HTTPS'),
    'conn.useHttpsHint': (
      '远程隧道 / 反向代理需要；局域网直连不用开',
      'Needed for a remote tunnel or reverse proxy; not for a direct LAN connection',
    ),
    // 标签从「备用地址（可选）」改成场景化表述：原来主地址说「是什么」（IP 或域名）、
    // 备用地址说「什么时候用」，两个标签不在一个抽象层级上。
    'conn.fallbackHost': (
      '出门用的地址（如 Tailscale IP）',
      'Address for when you are away (e.g. a Tailscale IP)',
    ),
    // hint 不再重复「出门用」（那是 label 的职责），改为说明**留空的后果** ——
    // 原来 label 与 hint 都在说「什么时候用」，两句话打架，还会被输入框截断。
    'conn.fallbackHint': (
      '留空则只用上面的地址，不启用自动切换',
      'Leave blank to use only the address above, with no auto-fallback',
    ),
    // ---- 远程访问面板的两段结构 ----
    //
    // 用户的要求（2026-10-05）：**并列多种方式、自己选** —— 不要写死只走
    // Cloudflare。「也可用其他的比如焦月连这样的工具」，所以第二段是开放的
    // 「你自己的工具」：App 不代管它们（Tailscale 这类是系统级 VPN，必须用户
    // 自己在电脑和手机上装），只负责引导 + 把地址收下来。
    'remote.managedTitle': ('① 让 App 开一条隧道', '① Let the app open a tunnel'),
    'remote.managedHint': ('服务端自己起，选一条：', 'Started by the server — pick one:'),
    'remote.optCloudflare': ('Cloudflare', 'Cloudflare'),
    'remote.optCloudflareHint': (
      '实测国内可达；临时地址每次重开都变',
      'Reachable from CN; the URL changes every time you restart it',
    ),
    'remote.optSsh': ('SSH 反向', 'SSH reverse'),
    'remote.optSshHint': (
      '零安装，但要求能连到外网中转',
      'Nothing to install, but it needs outbound access',
    ),
    'remote.ownTitle': ('② 用你自己的工具', '② Use your own tool'),
    'remote.ownHint': (
      'Tailscale / 皎月连 / frp 等：在电脑上装好并拿到外网地址后，填在下面。',
      'Tailscale, frp and the like — set it up on the computer, then paste the address it gives you.',
    ),
    'remote.ownPlaceholder': (
      '100.64.1.2:30142 或 https://…',
      '100.64.1.2:30142 or https://…',
    ),
    'remote.ownSave': ('存成一条连接', 'Save as a connection'),
    'remote.ownSaved': (
      '已存成连接，到「已保存」里就能切过去',
      'Saved — switch to it from the saved list',
    ),
    // 回落生效时的标记。必须说清「为什么显示的地址和填的不一样」，
    // 否则用户会以为填错了。
    'conn.viaFallback': (
      '走的是备用地址（主地址连不上）',
      'via fallback address (primary unreachable)',
    ),
    // 连接页的安全提示。三条都是**实际存在**的机制，不是泛泛的「注意安全」——
    // 泛泛的提醒用户会直接跳过，具体的信息才会真的影响他的选择。
    'conn.securityTitle': ('安全提示', 'Security notes'),
    'conn.securityBody': (
      '· token 由服务端首次启动时自动生成，保存在 server/.token（已在 .gitignore 里）；\n'
          '· 不要把这个端口直接暴露到公网。出门请用 VPN（如 Tailscale）而不是公共隧道；\n'
          '· 配对码只在你于电脑端打开的 5 分钟窗口内有效，连续填错会被限速。',
      '· The token is generated on first launch and kept in server/.token (git-ignored);\n'
          '· Do not expose this port to the public internet. Prefer a VPN (e.g. Tailscale) over a public tunnel;\n'
          '· The pairing code only works inside the 5-minute window you open on the computer, and repeated wrong entries are rate-limited.',
    ),

    // ============ 第二批：短句 UI 元素（task-23）============
    'ui.af767b7e4a': ('上', 'Up'),
    'ui.3850a186c3': ('下', 'Down'),
    'ui.7bbc73646a': ('主', 'You'),
    'ui.d58a55bcee': ('关', 'Off'),
    'ui.4d9c32c23d': ('右', 'Right'),
    'ui.d2aff14178': ('左', 'Left'),
    'ui.8493205602': ('开', 'On'),
    'ui.d81bb206a8': ('无', 'None'),
    'ui.6c7b1c13e5': ('上页', 'Page up'),
    'ui.821d4333ad': ('下页', 'Page down'),
    'ui.5c56a88945': ('停用', 'Disable'),
    'ui.bfc04cfda7': ('分支', 'Branch'),
    'ui.bec7e4d621': ('切换', 'Switch'),
    'ui.4181f7fe2a': ('刚刚', 'Just now'),
    'ui.d9ac9228e8': ('创建', 'Create'),
    'ui.81824cff24': ('卸载', 'Uninstall'),
    'ui.123adf145e': ('反向', 'Reverse'),
    'ui.7854b52a88': ('启用', 'Enable'),
    'ui.7650487a87': ('地址', 'Address'),
    'ui.e655a410ff': ('安装', 'Install'),
    'ui.f422e88af6': ('开头', 'Beginning'),
    'ui.48ac479789': ('当前', 'Current'),
    'ui.699143b15a': ('技能', 'Skills'),
    'ui.939d5345ad': ('提交', 'Submit'),
    'ui.2305051ed0': ('撤回', 'Undo send'),
    'ui.bd9fcf46b4': ('撤销', 'Undo'),
    'ui.0d83078816': ('数据', 'Data'),
    'ui.2a0c4740f1': ('文件', 'Files'),
    'ui.456d29ef8b': ('日志', 'Logs'),
    'ui.e8567f144b': ('末尾', 'End'),
    'ui.8fd578b58a': ('条目', 'Items'),
    'ui.ff692f04ac': ('消息', 'Messages'),
    'ui.e47bb1cd74': ('清理', 'Clean up'),
    'ui.4403fca0c0': ('清除', 'Clear'),
    'ui.743735721a': ('用量', 'Usage'),
    'ui.767fa455bb': ('目录', 'Directory'),
    'ui.e83a256e4f': ('确认', 'Confirm'),
    'ui.226b091218': ('类型', 'Type'),
    'ui.54d363afee': ('素材', 'Assets'),
    'ui.12f1d7ef38': ('结束', 'Ended'),
    'ui.95b351c862': ('编辑', 'Edit'),
    'ui.39f1374d36': ('耗时', 'Duration'),
    'ui.f970d0272c': ('花费', 'Cost'),
    'ui.df011658c3': ('范围', 'Range'),
    'ui.e09fea40f7': ('覆盖', 'Overwrite'),
    'ui.12bec730c7': ('轮数', 'Turns'),
    'ui.c3992269b4': ('退出', 'Exit'),
    'ui.03f38597a6': ('速度', 'Speed'),
    'ui.bfe68d5844': ('链接', 'Link'),
    'ui.18c63459a2': ('默认', 'Default'),
    'ui.756aadc26d': ('(空)', '(empty)'),
    'ui.c73936bbd7': ('0 秒', '0s'),
    'ui.50f198f07f': ('上下文', 'Context'),
    'ui.20c94429e5': ('会话名', 'Session name'),
    'ui.4705b88497': ('作用域', 'Scope'),
    'ui.19b5e0a26e': ('分支树', 'Branch tree'),
    'ui.b48cca48ed': ('可更新', 'Updatable'),
    'ui.6787355b9b': ('命中率', 'Hit rate'),
    'ui.5cc232620c': ('已删除', 'Deleted'),
    'ui.93d159228b': ('已发送', 'Sent'),
    'ui.2111ccbb19': ('已取消', 'Cancelled'),
    'ui.fad5222ca0': ('已完成', 'Completed'),
    'ui.da208e9c74': ('已配置', 'Configured'),
    'ui.c33f0e7bb9': ('开会话', 'Open session'),
    'ui.7f0425a8a6': ('未命名', 'Untitled'),
    'ui.fe2d26a257': ('未设置', 'Not set'),
    'ui.a21f6ab17d': ('空目录', 'Empty directory'),
    'ui.42861ce8c8': ('设备码', 'Device code'),
    'ui.708c9d6d2a': ('请选择', 'Select'),
    'ui.aa50cded3a': ('选模型', 'Select model'),
    'ui.b21364a469': ('(未知)', '(unknown)'),
    'ui.f4ae4ba20c': ('1 分钟', '1 min'),
    'ui.265b0f8cf7': ('2 分钟', '2 min'),
    'ui.ec13baff37': ('5 分钟', '5 min'),
    'ui.36e8fd3177': ('主工作树', 'Main worktree'),
    'ui.155e26ceeb': ('会话信息', 'Session info'),
    'ui.f98077685a': ('会话总数', 'Total sessions'),
    'ui.7914a459b5': ('会话片段', 'Session excerpt'),
    'ui.f96de32b76': ('内置命令', 'Built-in commands'),
    'ui.7f7c7dcf89': ('再来一次', 'Try again'),
    'ui.dd24107d75': ('出错提醒', 'Notify on error'),
    'ui.f8dc3f9a56': ('分支摘要', 'Branch summary'),
    'ui.4956c9f6d6': ('切换分支', 'Switch branch'),
    'ui.db5f3f8829': ('删除凭据', 'Delete credential'),
    'ui.fb4ca1cf1b': ('加载中…', 'Loading…'),
    'ui.75f7c9f130': ('卸载插件', 'Uninstall plugin'),
    'ui.cf978c0252': ('处理中…', 'Working…'),
    'ui.290b624aca': ('复制全文', 'Copy all'),
    'ui.cde0ad3061': ('复制结果', 'Copy result'),
    'ui.f4130cae7d': ('复制路径', 'Copy path'),
    'ui.879058ce06': ('复制链接', 'Copy link'),
    'ui.03fcdf562e': ('存到手机', 'Save to phone'),
    'ui.49c24aafc0': ('安装插件', 'Install plugin'),
    'ui.560e8629e3': ('已重命名', 'Renamed'),
    'ui.aecb607774': ('扩展命令', 'Extension commands'),
    'ui.fc9ce61bab': ('授权链接', 'Auth link'),
    'ui.5ba881d3c3': ('文件浏览', 'Files'),
    'ui.9418d7cb5e': ('未知时间', 'Unknown time'),
    'ui.904333d474': ('本地进程', 'Local process'),
    'ui.94d80e751a': ('本轮改动', 'This turn\'s changes'),
    'ui.87afad55b5': ('没有差异', 'No changes'),
    'ui.b08caf56ca': ('活跃会话', 'Active sessions'),
    'ui.eb0d6764ea': ('统计范围', 'Range'),
    'ui.dc0f2e515f': ('自动压缩', 'Auto-compaction'),
    'ui.cc2177391a': ('自动生成', 'Auto-generated'),
    'ui.6d2374cab5': ('诊断中…', 'Diagnosing…'),
    'ui.0a2ef2dec1': ('跑完提醒', 'Notify on done'),
    'ui.b1a9635c77': ('配置连接', 'Configure connection'),
    'ui.eb7b58bbb4': ('重新诊断', 'Re-diagnose'),

    // ============ 第三批：剩余全部中文（task-23 收尾）============
    // 带变量的文案用 {name} 占位，配合 I18n.tp(key, {...})；占位名按中文里
    // 变量出现的顺序一一对应（不依赖源代码里的变量名）。
    'ui.eb2ee57cb4': ('{label} 已复制', '{label} copied'),
    'ui.caccdc5cc0': ('新建 worktree', 'New worktree'),
    'ui.021016e15c': ('{m} 分', '{m} min'),
    'ui.c2d9323e9e': ('{n} 秒', '{n}s'),
    'ui.dfe094795b': ('{scope} · 未安装到本地', '{scope} · not installed locally'),
    'ui.f405d8974a': ('{h} 时 {m} 分', '{h}h {m}m'),
    'ui.ce4502a521': ('{n} 条', 'Messages: {n}'),
    'ui.a236b08a33': ('{name} 登录成功', 'Signed in to {name}'),
    'ui.a3645c3f66': ('(未知分支)', '(unknown branch)'),
    'ui.cb8fd1da6d': ('(未设置)', '(not set)'),
    'ui.0e19f86e8d': ('10 分钟', '10 min'),
    'ui.d2bf098e02': (
      'App 只做「显示器 + 键盘」，pi 始终跑在电脑上，',
      'The app is just a screen + keyboard; pi always runs on your computer,',
    ),
    'ui.5ed98f5447': (
      'Esc 收起面板/中断 · Tab 补全 · ↑↓ 历史',
      'Esc close/abort · Tab complete · ↑↓ history',
    ),
    'ui.358bf4b90b': ('IP 或域名', 'IP or domain'),
    'ui.d7911f414c': ('MCP 服务器', 'MCP servers'),
    'ui.c4d89641a1': ('Provider 凭据', 'Provider credentials'),
    'ui.0f7aa5c1a7': (
      'pi 记的价，不是我们按价目表算的',
      'Prices recorded by pi itself, not estimated from a list',
    ),
    'ui.65b148d3ae': ('pi-yz 连接诊断', 'pi-yz connection diagnosis'),
    'ui.f78ec7c874': (
      'provider 与 Key 都要填',
      'Both provider and key are required',
    ),
    'ui.61d5eeff77': ('url 不能空', 'URL cannot be empty'),
    'ui.b900e1a8a8': ('上下文压缩摘要', 'Compaction summary'),
    'ui.2e8c13741c': (
      '下次会话启动时不再连接它。',
      'It will not be connected on next launch.',
    ),
    'ui.020b61cdae': (
      '今天 / 本月（本机全部会话）',
      'Today / this month (all sessions on this machine)',
    ),
    'ui.d32325742b': (
      '今天已用 {today}（估算）：还早',
      'Used today: {today} (estimated) — plenty left',
    ),
    'ui.a1c0a7962b': ('从这条消息分支', 'Branch from this message'),
    'ui.7fdeeb20cd': (
      '会执行 git worktree remove {path}。目录里有未提交的改动时 git 会拒绝。',
      'Runs git worktree remove {path}. git refuses if there are uncommitted changes.',
    ),
    'ui.1483581ee7': ('例如 406794', 'e.g. 406794'),
    'ui.ef78e4268a': ('例如 90', 'e.g. 90'),
    'ui.487a7ad4fa': (
      '例如 C:/Users/you/projects（新建会话用）',
      'e.g. C:/Users/you/projects (for new sessions)',
    ),
    'ui.ae50303667': ('例如 家里的电脑', 'e.g. home-pc'),
    'ui.d7c8e237a5': ('保存失败：{error}', 'Save failed: {error}'),
    'ui.b35af26ccf': ('先打开一条会话才能切模型', 'Open a session first to switch models'),
    'ui.ce27b6f56c': (
      '先打开一条会话才能改思考等级',
      'Open a session first to change thinking level',
    ),
    'ui.3df36a0007': (
      '关掉的代价是：从锁屏切回来之前，跑完/卡住/需要确认这些提醒都收不到。',
      'Cost of turning it off: until you switch back, no finished / stuck / needs-input alerts.',
    ),
    'ui.b645389837': (
      '出门在外（4G / 别的 WiFi）也能连上这台电脑。局域网连接不受影响。',
      'Reach this computer from anywhere (4G / another Wi-Fi). LAN connections are unaffected.',
    ),
    'ui.0f584a2971': (
      '分享不可用，已复制到剪贴板',
      'Sharing unavailable, copied to clipboard',
    ),
    'ui.d156b373ad': ('创建中…', 'Creating…'),
    'ui.269830c1e6': ('删除 MCP 服务器', 'Delete MCP server'),
    'ui.d6b068b05f': ('删除 worktree', 'Delete worktree'),
    'ui.643e2ff2b9': ('删除这条会话？', 'Delete this session?'),
    'ui.7bf84c8cd4': ('剪贴板里没有文本', 'Clipboard is empty'),
    'ui.dc50378aea': ('包名不能空', 'Package name cannot be empty'),
    'ui.b33eaa597b': (
      '卡住提醒（多久没新输出就提醒）',
      'Stall alert (notify after this long without output)',
    ),
    'ui.af3e668e71': ('卡住阈值（秒）', 'Stall threshold (seconds)'),
    'ui.4f23e4de2b': (
      '压缩后还没跑过模型，暂无法估算',
      'No model run since compaction, cannot estimate yet',
    ),
    'ui.f8d73b6d3b': ('参数（空格分隔，可留空）', 'Arguments (space separated, optional)'),
    'ui.5e0e5bf05d': (
      '发送失败：通知被系统拦了',
      'Send failed: the system blocked the notification',
    ),
    'ui.dd55c97800': ('取不到分支树', 'Cannot fetch the branch tree'),
    'ui.2a624cf5e8': ('口径：{basis}', 'Basis: {basis}'),
    'ui.17c8715557': (
      '口径：缓存读 ÷ (输入 + 缓存读)',
      'Basis: cache read ÷ (input + cache read)',
    ),
    'ui.e20009713c': ('名字不能空', 'Name cannot be empty'),
    'ui.5a47c238fb': ('名字（如 github）', 'Name (e.g. github)'),
    'ui.97f76f1a29': ('后台保持连接（退到后台不断线）', 'Keep connection in background'),
    'ui.e2c2055ec7': (
      '启动后本页点「扫描局域网」就能直接找到这台电脑；',
      'After starting, tap “Scan LAN” to find this computer;',
    ),
    'ui.8109beab3c': (
      '命令清单还在拉取…（未连接或服务端没返回时，这里会一直是空的）',
      'Loading command list… (stays empty when not connected)',
    ),
    'ui.6b8e604809': (
      '图片会跟这条消息一起发给 pi；其他文件先传到工作区，再把路径写进输入框。',
      'Images go with the message; other files are uploaded first, then their paths are inserted.',
    ),
    'ui.e2cf8c9f6c': ('图片无法显示', 'Cannot display image'),
    'ui.0403f8b312': (
      '在浏览器打开上面的地址，输入设备码：{code}',
      'Open the URL above in a browser and enter device code: {code}',
    ),
    'ui.fb75dd5ecd': ('在电脑上启动服务端', 'Start the server on your computer'),
    'ui.1d11df355d': (
      '在电脑上启动服务端的终端里能看到「配对码: 6 位数字」，填进来即可。',
      'The server terminal shows “pairing code: 6 digits” — enter it here.',
    ),
    'ui.d988ff0fb5': ('地址已复制', 'Address copied'),
    'ui.f7959bcdd0': ('复制设备码', 'Copy device code'),
    'ui.74d486f798': (
      '它在后台的作用：SSE 长连接不被冻结、「卡住」提醒的定时器照跳。',
      'What it buys: the SSE connection is not frozen and the stall timer keeps ticking.',
    ),
    'ui.00c35d4155': ('安装 pi 插件', 'Install pi plugin'),
    'ui.50242e8bb9': ('导出到服务端', 'Export to server'),
    'ui.bfa525d4c6': ('导出诊断日志（系统分享）', 'Export diagnostic log (system share)'),
    'ui.e772a04b44': (
      '将删除 {provider} 在 pi 里保存的凭据。删掉后该 provider 的模型会不可用。',
      'Deletes the credential stored for {provider} in pi. Its models become unavailable.',
    ),
    'ui.16ae3ae443': ('尚未连接', 'Not connected yet'),
    'ui.d597968aea': ('工作区全部改动', 'All workspace changes'),
    'ui.af825e2845': ('工作区是干净的', 'Workspace is clean'),
    'ui.cd7349bbde': ('已从该消息分出分支', 'Branched from that message'),
    'ui.9c58505de3': ('已关闭', 'Off'),
    'ui.cbfd37e24c': (
      '已关闭后台保活（更省电，但切回 App 前收不到提醒）',
      'Background keep-alive off (saves battery, no alerts until you switch back)',
    ),
    'ui.7fd5122d71': ('已切换分支', 'Switched branch'),
    'ui.53c4ba1558': ('已切换分支（含摘要）', 'Switched branch (with summary)'),
    'ui.a3549f9b28': ('已发送（下拉通知栏看看）', 'Sent (check the notification shade)'),
    'ui.e8b121d05d': ('已取消归档', 'Unarchived'),
    'ui.be925b16ea': (
      '已在该 worktree 里打开会话',
      'Opened a session in that worktree',
    ),
    'ui.d228d6f331': ('已复制为新会话', 'Copied as a new session'),
    'ui.17ab7240c1': ('已存为常用语', 'Saved as a snippet'),
    'ui.8af708690a': ('已存到手机：{path}', 'Saved to phone: {path}'),
    'ui.9a2a7b9e12': ('已存在同名文件', 'A file with that name already exists'),
    'ui.2a5478aa2c': ('已导出到服务端', 'Exported to server'),
    'ui.bb06dd8151': ('已开启 · {provider}', 'Enabled · {provider}'),
    'ui.79e99333c9': (
      '已开启：退到后台也保持连接',
      'Enabled: the connection stays alive in background',
    ),
    'ui.c881be90ec': ('已引用到输入框', 'Quoted into the input box'),
    'ui.0708eadaa1': (
      '已归档 · 默认列表里不显示，文件还在电脑上',
      'Archived · hidden from the default list, file still on your computer',
    ),
    'ui.0ed6fd21dd': (
      '已拉回输入框，改完再发',
      'Pulled back to the input box — edit and send',
    ),
    'ui.b13542f798': (
      '已拉回输入框，改完点发送',
      'Pulled back to the input box — edit then send',
    ),
    'ui.e2410daedf': ('已提交，等下一步…', 'Submitted, waiting…'),
    'ui.59afc7c239': (
      '已撤回：已中断本轮，文字已放回输入框（那条仍在历史里）',
      'Undone: turn aborted, text restored (the message stays in history)',
    ),
    'ui.13261adf5f': (
      '已显示全部消息（含工具调用）',
      'Showing all messages (including tool calls)',
    ),
    'ui.6d0d37ee23': ('已清掉这条缓存', 'Cache entry removed'),
    'ui.c1a9075e7b': (
      '已清理：草稿 {drafts} 条、本地缓存 {others} 项',
      'Cleared drafts: {drafts}, cache items: {others}',
    ),
    'ui.add6e7b352': ('已清空默认工作区', 'Default workspace cleared'),
    'ui.87ad4d4da6': (
      '已申请通知权限，授权后再点一次',
      'Notification permission requested — tap again after granting',
    ),
    'ui.2afd083385': ('平均生成速度', 'Average generation speed'),
    'ui.27109fea19': (
      '开启后通知栏会常驻一条「正在保持连接」—— 保活必须让用户看得见，',
      'A persistent “keeping connection” notification appears — keep-alive must stay visible,',
    ),
    'ui.e9e41b7e7f': ('开启通知', 'Enable notifications'),
    'ui.370bc4a6b1': ('开场白没发出去', 'The opening message was not sent'),
    'ui.0f875dd0dc': ('引用（回输入框）', 'Quote (into input box)'),
    'ui.67a8909b85': (
      '归档只影响这台手机的默认列表，会话文件还在电脑上。',
      'Archiving only affects this phone\'s default list; the file stays on your computer.',
    ),
    'ui.dac78a7368': ('归档（默认列表里收起）', 'Archive (hide from list)'),
    'ui.1263de37a0': ('当前会话保持不动。', 'The current session is untouched.'),
    'ui.68af09ffe6': (
      '当前分支不会丢失，随时可以切回来。',
      'The current branch is not lost — you can switch back anytime.',
    ),
    'ui.eb6e66be0f': (
      '当前工作区不是 git 仓库',
      'The current workspace is not a git repository',
    ),
    'ui.6e6f9563b7': ('当前：未知（可能没打开会话）', 'Current: unknown (no session open?)'),
    'ui.e139dcc6af': (
      '必须在允许的根目录下（家目录 / 会话工作区）',
      'Must be under an allowed root (home dir / session workspace)',
    ),
    'ui.944e771000': ('思考等级：{level}', 'Thinking level: {level}'),
    'ui.a9cec18e05': ('技能与命令', 'Skills & commands'),
    'ui.8551ea0b22': ('把当前输入存为常用语', 'Save input as a snippet'),
    'ui.67bda6669e': (
      '拉取会话内容失败（会话没打开或服务端不可用）',
      'Failed to load the session (not open, or server unreachable)',
    ),
    'ui.2af86cefa9': (
      '拿不到占用数据（服务端连不上？）',
      'Cannot get storage data (server unreachable?)',
    ),
    'ui.d75cd7604d': ('按天趋势（最近 10 天）', 'Daily trend (last 10 days)'),
    'ui.fa76940a48': ('改默认模型失败', 'Failed to change the default model'),
    'ui.1aeddef693': (
      '数字来自落盘会话记录，不是估算',
      'Numbers come from on-disk session records, not estimates',
    ),
    'ui.1b857f46f0': ('整份会话已复制', 'Whole session copied'),
    'ui.435ccbf9b2': (
      '新会话将在该目录下运行',
      'The new session will run in that directory',
    ),
    'ui.fd70d64c54': (
      '新会话将默认用 {model}（当前会话不受影响）',
      'New sessions will default to {model} (current session unaffected)',
    ),
    'ui.930618f742': ('新会话默认模型', 'Default model for new sessions'),
    'ui.6ae804fad2': (
      '新分支名（留空则 detached HEAD）',
      'New branch name (empty = detached HEAD)',
    ),
    'ui.da96bf7843': (
      '方式一：注册过 pi-yz 命令的话 —— 一条命令就够，服务会打印手机要填的信息，',
      'Option 1: if you have registered the pi-yz command — one line is enough; it prints,',
    ),
    'ui.282652e49f': (
      '方式二：在 pi-yz 目录里直接跑（前台运行，Ctrl+C 停止）',
      'Option 2: run it directly inside the pi-yz directory (foreground, Ctrl+C to stop)',
    ),
    'ui.0b30277c77': ('有一步需要你拍板', 'One step needs your call'),
    'ui.22f5ca6614': (
      '服务端上的会话与配置不受影响。',
      'Sessions and settings on the server are unaffected.',
    ),
    'ui.fb58f723f1': ('服务端返回异常', 'Server returned an error'),
    'ui.261ec4f0de': ('未打开会话', 'No session open'),
    'ui.95af3b54e0': ('未配置服务端', 'Server not configured'),
    'ui.91977f0940': (
      '本地命令型 MCP（在电脑上起子进程，能读写本机文件）',
      'Local command MCP (spawns a process on your computer, can read/write files)',
    ),
    'ui.e2bbbd3cee': ('本轮没有工具调用', 'No tool calls this turn'),
    'ui.7f28d733a5': ('检查/全部更新', 'Check / update all'),
    'ui.0874b95e15': (
      '模型、思考等级、技能命令、MCP 服务器',
      'Model, thinking level, skills, MCP servers',
    ),
    'ui.29f830c6dd': ('模型与思考等级', 'Model & thinking level'),
    'ui.41f1f2fb0e': ('模型（点一下就切）', 'Model (tap to switch)'),
    'ui.18a16fa829': ('正在建立…', 'Establishing…'),
    'ui.eb0bc967a8': ('正在扫局域网…', 'Scanning LAN…'),
    'ui.5f31a99e96': ('正在整理会话…', 'Preparing session…'),
    'ui.74596dca8e': ('正在生成分支摘要…', 'Generating branch summary…'),
    'ui.d8999cf874': ('正在载入会话…', 'Loading session…'),
    'ui.04b4da54a3': (
      '没扫到。确认手机与电脑在同一个 Wi-Fi、且电脑端服务端已启动（见下方启动向导）',
      'Nothing found. Make sure both are on the same Wi-Fi and the server is running (see the guide below)',
    ),
    'ui.3ac69ac199': ('没有 worktree 信息', 'No worktree info'),
    'ui.a425983efe': ('没有匹配「{query}」的会话', 'No sessions matching “{query}”'),
    'ui.039e58de36': ('没有可用模型', 'No models available'),
    'ui.35eb0b8e30': ('没有在跑的会话', 'No running sessions'),
    'ui.f28ba9e525': (
      '没能读到配置（可能未连接或服务端异常）',
      'Could not read settings (not connected, or server error)',
    ),
    'ui.54e7e0babb': ('没起来：{error}', 'Failed to start: {error}'),
    'ui.480b698883': ('浏览工作区文件', 'Browse workspace files'),
    'ui.1d3a567c5e': ('清理本地数据？', 'Clear local data?'),
    'ui.f447ebec03': (
      '清空（用连接配置里的默认值）',
      'Clear (use the default from the connection profile)',
    ),
    'ui.5a54a90ba5': (
      '点「开启远程访问」后，这里会列出链路走向与代价。',
      'After enabling remote access, the route and its trade-offs appear here.',
    ),
    'ui.56420c43ac': (
      '点「选择」读取当前默认',
      'Tap “Select” to read the current default',
    ),
    'ui.14768ed565': ('点一下填进输入框', 'Tap to insert into the input box'),
    'ui.ca760bfec8': (
      '点修饰键锁定，再点按键即组合',
      'Tap a modifier to lock, then tap a key to combine',
    ),
    'ui.9822a4f972': ('点开看内容', 'Tap to view content'),
    'ui.08d9b34843': ('用哪句开场？', 'Which opening line?'),
    'ui.c0fdf79953': ('登录 {name}', 'Sign in to {name}'),
    'ui.ba23cee4eb': ('登录失败：{error}', 'Sign-in failed: {error}'),
    'ui.52ff644bf2': ('目录（绝对路径）', 'Directory (absolute path)'),
    'ui.824949be5b': ('相册 / 图片', 'Photos / images'),
    'ui.30570a7afa': ('看 diff', 'View diff'),
    'ui.ea2e75976e': ('磁盘上没有会话文件', 'No session files on disk'),
    'ui.b2b3bb2703': ('离线缓存已清空', 'Offline cache cleared'),
    'ui.6e33906ae2': (
      '离线缓存（断网时还能读的最近会话）',
      'Offline cache (recent sessions readable offline)',
    ),
    'ui.7870802a43': ('空会话（自己打第一句）', 'Empty session (send the first message)'),
    'ui.9b5fb84bb2': ('等待你的输入', 'Waiting for your input'),
    'ui.a87c5ece96': (
      '等待开始 · 发一句话，这里会按时间线记下每一步',
      'Waiting to start · send a message and every step shows up here',
    ),
    'ui.32249be96d': ('粘贴剪贴板', 'Paste from clipboard'),
    'ui.21587f0de2': ('粘贴密钥', 'Paste key'),
    'ui.c6f2208df0': (
      '系统没接住（常驻服务起不来，看看有没有禁用后台）',
      'The system refused (keep-alive service could not start — check background restrictions)',
    ),
    'ui.4dc7b743df': (
      '统计口径：只算 edit / write 工具',
      'Counted from edit / write tools only',
    ),
    'ui.759391f11c': ('缓存命中率', 'Cache hit rate'),
    'ui.f7cf767827': (
      '自动压缩已关闭：到 100% 会失败，建议手动 /compact',
      'Auto-compaction is off: it fails at 100%; run /compact manually',
    ),
    'ui.8d63f5a87f': (
      '装的东西会从磁盘删掉，设置里的登记也会撤销。',
      'Installed files are deleted from disk and the settings entry is removed.',
    ),
    'ui.a1dfc88cea': ('设备码登录', 'Device-code sign-in'),
    'ui.c92c4d1779': ('诊断结果已复制', 'Diagnosis copied'),
    'ui.a9f32d22fd': ('说明（可留空）', 'Description (optional)'),
    'ui.3a27243926': (
      '请先在「连接」里配置服务端地址',
      'Configure the server address under “Connection” first',
    ),
    'ui.0ef428fefc': (
      '请先在连接配置里填写默认工作区',
      'Set a default workspace in the connection profile first',
    ),
    'ui.2b039aa291': (
      '读不到 {target}（可能超出允许范围）',
      'Cannot read {target} (outside the allowed roots?)',
    ),
    'ui.e849a32234': ('读不到图片数据', 'Cannot read image data'),
    'ui.b16350e431': ('读不到文件数据', 'Cannot read file data'),
    'ui.7bb952c3c4': (
      '读不到目录（可能不在允许范围内）',
      'Cannot read the directory (outside the allowed roots?)',
    ),
    'ui.054235bdc7': ('读取 provider…', 'Reading providers…'),
    'ui.a6664f495a': (
      '读取会话信息失败：{error}',
      'Failed to read session info: {error}',
    ),
    'ui.beec95ef4a': (
      '超过约 70% 变黄、85% 变红：自动压缩开启时，到阈值会自己压一次',
      'Turns yellow past ~70%, red past 85%; with auto-compaction on it compacts at the threshold',
    ),
    'ui.42c4e29d47': ('路径已复制', 'Path copied'),
    'ui.578b86ba8e': (
      '输入 + 输出 + 缓存读 + 缓存写',
      'Input + output + cache read + cache write',
    ),
    'ui.fd081a3eac': ('输入会话名', 'Session name'),
    'ui.37dba61d9d': (
      '输入框是空的，先打点字再存',
      'The input box is empty — type something first',
    ),
    'ui.8f4e9d8dbf': ('输入消息，或打 / 调出命令', 'Type a message, or / for commands'),
    'ui.c32f83502e': (
      '还没打开会话： 「当前模型」与扩展命令要等会话打开；模型、思考等级、技能、内置命令已能直接读',
      'No session open: “current model” and extension commands need one; model, thinking level, skills and built-ins can be read already',
    ),
    'ui.20b7049647': ('还没有今天的用量数据', 'No usage data for today yet'),
    'ui.814d5316b2': ('还没有可分享的回复', 'No reply to share yet'),
    'ui.ec884726be': (
      '还没有可统计的轮次（跑过一次模型调用后这里会逐轮列出来）',
      'No turns to count yet (they appear after a model call)',
    ),
    'ui.0f4c3ea1dd': (
      '还没有工作区，先在连接设置里填默认工作区',
      'No workspace yet — set a default in the connection profile',
    ),
    'ui.45afe85695': (
      '还没有工作区，先打开一条会话',
      'No workspace yet — open a session first',
    ),
    'ui.0a50893ad0': (
      '还没有工作区，请先在连接配置里填写默认工作区',
      'No workspace yet — fill in the default workspace in the connection profile',
    ),
    'ui.b47293f027': (
      '还没有常用语。在会话页输入区的 ＋ 菜单里可以收藏（存本地，重启保留）。',
      'No snippets yet. Save them from the ＋ menu in the chat input area (stored locally).',
    ),
    'ui.d0f489e127': (
      '还没有常用语。把想重复用的句子先打进输入框，再点下面的按钮存起来。',
      'No snippets yet. Type the sentence you reuse into the input box, then tap the button below.',
    ),
    'ui.7af44bc1f0': ('还没有按工作区的记录', 'No per-workspace records yet'),
    'ui.761a77f1f9': (
      '还没有日志。连一次服务端就会开始记录。',
      'No logs yet. They start once you connect to the server.',
    ),
    'ui.577d49c54f': (
      '还没有缓存（打开过的会话会自动留一份）',
      'No cache yet (opened sessions are cached automatically)',
    ),
    'ui.3a61229d9e': ('还没有配置凭据', 'No credentials configured yet'),
    'ui.606276afd3': ('还没装 pi 插件', 'No pi plugin installed yet'),
    'ui.58fea6ab1a': (
      '这个技能没给出文件路径（可能来自扩展）',
      'This skill exposes no file path (it may come from an extension)',
    ),
    'ui.dad890d59d': ('这个文件是空的', 'This file is empty'),
    'ui.4fa10ed005': (
      '这台电脑没开配对窗口：重启服务端会自动开 5 分钟',
      'No pairing window open: restarting the server opens one for 5 minutes',
    ),
    'ui.2d951376b5': (
      '这条会话正在运行，先停下再删',
      'This session is running — stop it before deleting',
    ),
    'ui.de8eecad10': (
      '这段范围内还没有带 usage 的落盘记录',
      'No on-disk usage records in this range yet',
    ),
    'ui.065d1a7742': (
      '这里空了，都捞回来了',
      'Nothing left here — everything is restored',
    ),
    'ui.435a51e1a2': (
      '进行中…（在电脑浏览器里完成授权也行）',
      'In progress… (you can also authorize in a browser on your computer)',
    ),
    'ui.1aef0e1818': (
      '远程 MCP（走网络，数据出本机）',
      'Remote MCP (over the network, data leaves this machine)',
    ),
    'ui.f40bb45c68': ('远程 URL', 'Remote URL'),
    'ui.1b730b15b4': (
      '远程入口已关闭 · 公网再也连不上，局域网照常',
      'Remote entry closed · no public access anymore, LAN still works',
    ),
    'ui.3fc0cf9dc3': ('远程入口已就绪，地址见上方', 'Remote entry is ready — address above'),
    'ui.1de0cfbc46': ('远端 pi', 'Remote pi'),
    'ui.d0bacac615': (
      '连接诊断（端口 / 延迟 / 鉴权逐项查）',
      'Connection diagnosis (port / latency / auth, item by item)',
    ),
    'ui.fad7c8a21f': ('选中', 'Selected'),
    'ui.1afcd77a58': ('选图失败：{error}', 'Failed to pick an image: {error}'),
    'ui.7e0ab49ec4': ('选择工作区', 'Choose a workspace'),
    'ui.47840e3fb4': (
      '选择服务端地址，连接远端 pi',
      'Pick a server address to connect to remote pi',
    ),
    'ui.723126c430': ('选文件失败：{error}', 'Failed to pick a file: {error}'),
    'ui.ec238afeae': (
      '逐项检查地址解析、端口、鉴权 —— 失败的那一项会给出下一步怎么做',
      'Checks DNS, port and auth one by one — the failing item tells you what to do next',
    ),
    'ui.b0a2bb16fb': ('通知已关闭', 'Notifications off'),
    'ui.a8b60db178': ('通知栏快速回复', 'Quick reply from the notification'),
    'ui.fccbc56d80': ('通过 HTTP + SSE 连接。', 'Connects over HTTP + SSE.'),
    'ui.421b536739': ('重新载入', 'Reload'),
    'ui.d03d895f04': ('重点模式：只看对话主干', 'Focus mode: conversation backbone only'),
    'ui.4f1313e28c': (
      '长任务看护（只在需要人时提醒）',
      'Long-task watch (only alert when a human is needed)',
    ),
    'ui.6bf9e327f2': ('闲置 {time}', 'Idle {time}'),
    'ui.3bff752a5d': ('隧道地址不认识：{url}', 'Unrecognized tunnel address: {url}'),
    'ui.4d4a4242b1': ('需打开会话', 'Needs an open session'),
    'ui.a7b4addcc2': ('需要确认时提醒', 'Notify when confirmation is needed'),
    'ui.e949f0cedd': (
      '顺手生成摘要（把丢掉的那条分支压缩成一段话，切换后不丢上下文）',
      'Also generate a summary (compresses the dropped branch so context is not lost)',
    ),
    'ui.9b86661544': ('默认工作区：{picked}', 'Default workspace: {picked}'),
    'ui.2abac8cdd2': (
      '（可理解为「窗口里现在装了多少」）',
      '(how much is currently loaded in the window)',
    ),
    'ui.13b31d4b3e': ('（当前在免打扰时段）', '(currently in do-not-disturb hours)'),
    'ui.acb19e42a6': ('，更早的 {n} 条未缓存', ', {n} older messages not cached'),

    // 收尾补漏（task-23）
    'ui.f0d15d56eb': (
      '用量明细（逐轮 tokens / 速度 / 成本）',
      'Usage detail (per-turn tokens / speed / cost)',
    ),

    'ui.d7320b9231': (
      '共 {n} 个节点；点任意节点可切过去（当前叶子高亮）',
      'Nodes: {n}; tap any node to jump (current leaf highlighted)',
    ),
    // 第四批：模板字符串与收尾补漏（task-23）
    'ui.409a5d5fb9': ('agent 空闲中', 'agent idle'),
    'ui.a67d3f95b7': ('等你确认 {n} 项', 'Items awaiting you: {n}'),
    'ui.2286308de1': ('{n} 次工具调用', 'Tool calls: {n}'),
    'ui.f547f2d5e4': ('{n} 个文件', 'Files: {n}'),
    'ui.1395da23fa': ('输出 {n} tok', 'output {n} tok'),
    'ui.19c1bd1b68': ('用时 {time}', 'took {time}'),
    'ui.998a18b488': (
      '发一句话，这里会按时间线列出 agent 每一步在干什么',
      'Send a message and every step shows up here',
    ),
    'ui.ae9a52e8c8': (
      '排队中：插话 {a} 条 · 后续 {b} 条',
      'Queued: {a} steer · {b} follow-up',
    ),
    'ui.9fa88d5d6f': ('当前：{name} · {provider}', 'Current: {name} · {provider}'),
    'ui.97523d250a': (
      '已切到 {name}（{provider}）',
      'Switched to {name} ({provider})',
    ),
    'ui.8dc0a54c3c': ('已移除「{name}」', 'Removed “{name}”'),
    'ui.42ccfeb789': ('已附上 {name}', 'Attached {name}'),
    'ui.54507a5944': (
      '加载更早的消息（已显示 {shown}/{total}）',
      'Load earlier messages ({shown}/{total})',
    ),
    'ui.cb3f40c93e': (
      '离线 · 显示 {time} 的缓存（{n} 条{dropped}）',
      'Offline · cached at {time} (messages: {n}{dropped})',
    ),
    'ui.7622b8adf0': ('已载入 {n} / {n}', 'Loaded {n} / {n}'),
    'ui.37e8f35792': (
      '合计 {total}（输入 {input} · 输出 {output} · 缓存读 {cr} · 缓存写 {cw}）',
      'Total {total} (input {input} · output {output} · cache read {cr} · cache write {cw})',
    ),
    'ui.d8deeeee4c': (
      'user {u} · assistant {a} · 工具调用 {tc} · 工具结果 {tr}',
      'user {u} · assistant {a} · tool calls {tc} · tool results {tr}',
    ),
    'ui.a977d99ebd': ('共 {n} 个 · 上下滑动看全部', '{n} total · scroll to see all'),
    'ui.6e9ce7a03e': (
      '匹配 {a} / 共 {b} 个 · 上下滑动看全部',
      '{a} / {b} matched · scroll to see all',
    ),
    'ui.9069e11411': (
      '本轮改动 {files} 个文件 +{added}/-{removed}',
      'This turn: files {files} +{added}/-{removed}',
    ),
    'ui.064981f079': (
      '{files} 个文件 +{added}/-{removed}',
      'files {files} +{added}/-{removed}',
    ),
    'ui.91e8ba4966': ('provider（如 openai）', 'provider (e.g. openai)'),
    'ui.c2cad6ac24': ('command（如 npx）', 'command (e.g. npx)'),
    'ui.079283b6b1': ('command 不能空', 'command cannot be empty'),
    'ui.edb9ab9fc0': (
      '共 {n} 个模型，已列出前 40 个',
      'Models: {n}, showing the first 40',
    ),
    'ui.ebd66f8a1f': ('电脑端已汉化 {n} 处文案', 'Strings localized: {n}'),
    'ui.800e3b5963': ('更新 {n} 个', 'update {n}'),
    'ui.5ab2668c03': (
      '还没有 MCP 服务器（可在这里添加，写进 ~/.pi/agent/mcp.json）',
      'No MCP servers yet (add one here; written to ~/.pi/agent/mcp.json)',
    ),
    'ui.8480b01bc7': ('已切到 {name}', 'Switched to {name}'),
    'ui.9030449893': ('…还有 {n} 条', '…{n} more'),
    'ui.ae38520cd9': (
      'npm 包名 / git 地址 / 本地目录',
      'npm package / git URL / local directory',
    ),
    'ui.62b8ab7e30': (
      '安装会真的联网下载（npm / git），可能需要几十秒。',
      'Installing really downloads over the network (npm / git); it can take a while.',
    ),
    'ui.57e6d24d08': ('连接成功 · pi {version}', 'Connected · pi {version}'),
    'ui.754e7e0a0b': ('已连接 {endpoint}', 'Connected to {endpoint}'),
    'ui.7ae8535227': ('扫到 {n} 台，点一下就能配对', 'Found {n} — tap to pair'),
    'ui.3210a50038': ('配对成功（pi {version}）', 'Paired (pi {version})'),
    'ui.506c0b7cbf': (
      '目标：{name}（{endpoint} · pi {version}）',
      'Target: {name} ({endpoint} · pi {version})',
    ),
    'ui.445cf3f727': (
      '填写 pi-yz-server 的地址与 token',
      'Enter the pi-yz-server address and token',
    ),
    'ui.7ab030fd16': (
      '服务端启动时打印的 token',
      'The token printed when the server starts',
    ),
    'ui.e28ad37f63': (
      '并在终端打印手机该填的地址与 token。',
      'and prints the address and token for your phone.',
    ),
    'ui.44d23ca46b': (
      '终端里那行「配对码」填进去即可，不用手动复制 token。',
      'Just enter the “pairing code” from the terminal — no need to copy the token.',
    ),
    'ui.8e72a51181': (
      '还没有 token，先连一次局域网或手填',
      'No token yet — connect over LAN once, or type it in',
    ),
    'ui.e02ef1e216': (
      '已通过公网连上（{endpoint}）',
      'Connected over the public tunnel ({endpoint})',
    ),
    'ui.cca1ded1d1': (
      '导出的内容里 token 是掩码的，可以直接发给别人',
      'The exported content masks the token, so it is safe to share',
    ),
    'ui.8e735016cc': ('这个文件不是图片（{type}）', 'This file is not an image ({type})'),
    'ui.6e4f2b46a6': (
      '{name} 已经在当前目录里，要覆盖吗？',
      '{name} already exists here — overwrite?',
    ),
    'ui.b7efc0c5ef': ('还有 {n} 个未显示', '{n} more not shown'),
    'ui.29889d892e': ('{n} 条（最多留 500 条）', '{n} entry(ies) (keep up to 500)'),
    'ui.a2e6d79651': ('已复制 {n} 条日志', 'Copied {n} log entries'),
    'ui.e3e9b48350': ('正在运行 {n} 个', '{n} running'),
    'ui.f39b24369b': ('共 {n} 个会话活着', 'Sessions alive: {n}'),
    'ui.a33efe1f34': ('已跑 {time}', 'running {time}'),
    'ui.5fa4f9c0f7': ('已删除 · 腾出 {size}', 'Deleted · freed {size}'),
    'ui.95409b9ef3': ('{n} 条会话 · {g} 个工作区', 'Sessions: {n} · workspaces: {g}'),
    'ui.dda1a3b608': ('{n} 条 · {size}', '{n} · {size}'),
    'ui.bdd04225f4': (
      'API Key 向导与 OAuth（订阅账号 / 设备码）都在这里；凭据写进 pi 的 auth.json',
      'API key wizard and OAuth (subscription / device code) live here; credentials go into pi\'s auth.json',
    ),
    'ui.72a5d6bddc': ('{label}（需环境变量）', '{label} (env var required)'),
    'ui.eeab2a93eb': (
      '登录完成，凭据已写入 pi 的 auth.json。可以返回凭据列表看看。',
      'Signed in — credentials written to pi\'s auth.json. Go back to the credential list to check.',
    ),
    'ui.af6b674a02': (
      '离线缓存（{n} 条 · 断网也能读正文）',
      'Offline cache ({n} · readable without network)',
    ),
    'ui.4751d5948e': (
      '「{title}」及其 {n} 条消息将被删除，无法恢复。',
      '“{title}” and its messages ({n}) will be deleted permanently.',
    ),
    'ui.5a04ac36ad': ('已归档 {n} 条', 'Archived {n}'),
    'ui.c748caed3a': ('已归档（{n}）', 'Archived ({n})'),
    'ui.8d6dd7475a': ('{ws} · {n} 条', '{ws} · messages: {n}'),
    'ui.40f8db2889': ('{n} 条 · {cwd}', 'Messages: {n} · {cwd}'),
    'ui.604c021ba2': (
      '正在跑 · {n} 条 · {time}',
      'Running · messages: {n} · {time}',
    ),
    'ui.d05a6b72d1': ('{n} 条 · {time}', 'Messages: {n} · {time}'),
    'ui.1f75ab9c48': ('{count} 分钟前', '{count} min ago'),
    'ui.16362ceb20': ('{n} 小时前', '{n} h ago'),
    'ui.0dd2ae3aa0': ('{n} 天前', '{n} d ago'),
    'ui.ac2a29973b': ('最近被压掉的提醒（{n} 条）', 'Recently suppressed ({n})'),
    'ui.226628b2da': ('自检：{check}', 'Self-check: {check}'),
    'ui.745a442139': (
      '已缓存 {n} 条会话 · 共 {size}',
      'Cached sessions: {n} · {size}',
    ),
    'ui.c97d59e36c': ('上限：最多 {n} 条会话、', 'Limit: at most {n} sessions,'),
    'ui.3c7de3c73a': ('每条 {n} 条消息、', '{n} messages each,'),
    'ui.84dc1d5db5': ('合计 tokens', 'Total tokens'),
    'ui.3bc67904e3': (
      '口径：输出 tokens ÷ 各轮耗时之和（耗时为相邻落盘条目时间戳之差）',
      'Basis: output tokens ÷ sum of per-turn durations (duration = gap between adjacent on-disk entries)',
    ),
    'ui.6bc638f6a6': (
      '最近 45 天内改动过的 {n} 条会话',
      'Sessions changed in the last 45 days: {n}',
    ),
    'ui.aa1d2675e2': ('{n} 轮', 'Turns: {n}'),
    'ui.fcbd3cc5d4': (
      '口径：按每条 assistant 落盘条目的 usage 累加，日期取该条目的时间戳；',
      'Basis: summed from the usage of each on-disk assistant entry, dated by its timestamp;',
    ),
    'ui.5a6fa04a24': (
      'tokens = 输入 + 输出 + 缓存读 + 缓存写。下面按工作区同理。',
      'tokens = input + output + cache read + cache write. Same basis for the workspace breakdown below.',
    ),
    'ui.e505495394': (
      '{n} 条会话 · {t} 轮 · {cwd}',
      'Sessions: {n} · turns: {t} · {cwd}',
    ),

    // 接线补漏：这些中文早就有译文，只是调用点没接上（task-23 第四轮）
    'ui.af094ee50d': (
      '将从 {scope} mcp.json 删掉「{name}」。',
      'Removes “{name}” from {scope} mcp.json.',
    ),

    'start.noSession': ('还没有会话', 'No sessions yet'),
    'start.connectFirst': ('连接后显示历史会话', 'Connect to see history'),

    'chat.inputHint': ('输入消息', 'Message'),
    'chat.inputHintRunning': ('运行中…可输入以插话', 'Running… type to steer'),

    'settings.conn': ('连接', 'Connection'),
    'settings.workspace': ('工作区', 'Workspace'),
    'settings.appearance': ('外观', 'Appearance'),
    'settings.app': ('App 设置', 'App settings'),
    'settings.about': ('关于', 'About'),
    'settings.language': ('界面语言', 'Language'),
    'settings.fontSize': ('字体大小（整机生效）', 'Font size (whole app)'),
    'settings.lineHeight': ('行距（消息正文）', 'Line height (message body)'),
    'settings.enter': ('回车键', 'Enter key'),
    'settings.defaultWorkspace': (
      '默认工作区（没打开会话时发消息用）',
      'Default workspace (when no session is open)',
    ),
    'settings.defaultModel': (
      '新会话默认模型（改的是电脑端 pi 的设置）',
      'Default model for new sessions (writes pi settings)',
    ),
    'settings.localData': ('本地数据与日志', 'Local data & logs'),
    'settings.clear': ('清理本地数据', 'Clear local data'),
    'settings.logs': ('打开日志', 'Open logs'),

    'common.retry': ('重试', 'Retry'),
    'common.cancel': ('取消', 'Cancel'),
    'common.select': ('选择', 'Select'),
  };

  /// 当前是否中文（跟随系统时看平台 Locale）。
  ///
  /// **为什么忽略 `context`**（2026-10-09 MuMu 实测后改）：
  /// 这个参数原先走 `Localizations.localeOf(context)`，但 `MaterialApp`
  /// （lib/main.dart）没配 `supportedLocales` —— Flutter 的默认支持集只有
  /// `[en_US]`，解析结果恒为 en_US。于是 25 处带 `context:` 的调用在中文界面上
  /// 一律取英文，而 880 多处不带的重走平台 Locale 取中文，同一个设置页里中英混排
  /// （截图里「Font size (whole app)」和「默认工作区路径」并排）。
  ///
  /// 现在只认一个真源：`AppPrefs.lang`（用户显式选的界面语言）→ 平台 Locale。
  /// 保留参数是为了不动那 25 个调用点的签名。
  static bool isZh(BuildContext? context) {
    final lang = AppPrefs.instance.lang;
    if (lang == 'zh') return true;
    if (lang == 'en') return false;
    try {
      // context 刻意不参与判定：它承载的 Localizations 结果不可信，见上面的说明。
      return WidgetsBinding.instance.platformDispatcher.locale.languageCode
          .startsWith('zh');
    } catch (_) {
      // 纯 Dart 单测里 binding 未初始化，按默认中文处理
      return true;
    }
  }

  /// 取文案；找不到就返回 key（让漏翻一眼可见，而不是静默显示中文）
  /// 词表里登记的全部 key。
  ///
  /// 只给测试用（`test/i18n_integrity_test.dart`），核对「代码里引用的 key」与
  /// 「词表里登记的 key」是否对得上。这个方向对不上时，运行时会**直接显示 key
  /// 原文**（`t()` 找不到就返回 key，这是刻意设计，为了让漏翻一眼可见）——
  /// 也就是说界面上会出现 `ui.8cd4d69138` 这种字符串。它用户看得到，但代码里
  /// grep 不出来（是运行时行为），必须靠测试挡。
  ///
  /// 注意这与「生产代码里的测试开关」不同：这里只**暴露数据**，不改变任何行为。
  @visibleForTesting
  static Iterable<String> get debugKeys => _strings.keys;

  /// 整张词表（测试用：校验占位符一致性、空翻译）。
  @visibleForTesting
  static Map<String, (String zh, String en)> get debugStrings => _strings;

  static String t(String key, {BuildContext? context}) {
    final entry = _strings[key];
    if (entry == null) return key;
    return isZh(context) ? entry.$1 : entry.$2;
  }

  /// 带参数的文案：词表里用 `{name}` 占位，这里做替换。
  ///
  /// 为什么需要它：像「已切换到 {name}」这种句子，中文和英文的语序不同
  /// （`Switched to X` vs `已切换到 X`），把变量拼在字符串外面是翻不好的。
  static String tp(
    String key,
    Map<String, Object?> args, {
    BuildContext? context,
  }) {
    var text = t(key, context: context);
    args.forEach((k, v) {
      text = text.replaceAll('{$k}', '${v ?? ''}');
    });
    return text;
  }

  /// 命令说明：中文模式优先中文，没有就原文 + 标注；英文模式一律原文
  static String describe(
    String? original,
    String? chinese, {
    BuildContext? context,
  }) {
    final zh = (chinese ?? '').trim();
    final en = (original ?? '').trim();
    if (isZh(context)) {
      if (zh.isNotEmpty) return zh;
      if (en.isNotEmpty) {
        return '$en（${t('common.untranslated', context: context)}）';
      }
      return '';
    }
    return en.isNotEmpty ? en : zh;
  }

  /// 供文档/自检：当前语言包有多少条
  static int get keyCount => _strings.length;
}
