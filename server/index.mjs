// pi-mobile-server 入口
//
// 职责：把 pi 的 SDK 包成 HTTP + SSE，供手机端访问。
// 设计原则：零依赖（只用 Node 内置模块 + 本机已装的 pi SDK）。
//
// 用法：
//   node index.mjs                      # 监听 127.0.0.1，仅本机可访问
//   node index.mjs --host 0.0.0.0       # 监听局域网（Windows 会弹防火墙授权）
//   node index.mjs --port 30142 --token mysecret
//
// 接口：
//   GET  /api/health                    健康检查（无需认证）
//   GET  /api/sessions                  会话列表（跨 cwd）
//   POST /api/sessions                  新建会话 {cwd}
//   GET  /api/sessions/:id/events       SSE 事件流
//   POST /api/sessions/:id/command      命令入口 {id,type,...}
//   GET  /api/pool                      当前活跃会话（调试）

import { createServer } from 'node:http';
import { resolveToken, describeSource } from './lib/token-store.mjs';
import { parseArgs } from './lib/args.mjs';
import { startDiscovery, lanAddresses } from './lib/discovery.mjs';
import {
  closePairingWindow,
  isPairingOpen,
  openPairingWindow,
  pairingState,
  verifyPairingCode,
} from './lib/pairing.mjs';
import { listSessions, deleteSession, diskUsage } from './lib/sessions.mjs';
import { maskSecret } from './lib/secrets.mjs';
import { startTunnel, stopTunnel, tunnelState } from './lib/tunnel.mjs';
import { sessionUsage, usageSummary } from './lib/usage.mjs';
import { turnSummaryForSession } from './lib/turn-summary.mjs';
import {
  allowedRoots,
  FsAccessError,
  addWorktree,
  gitDiff,
  gitStatus,
  listDirectory,
  listMcpServers,
  listWorkspaceFiles,
  listWorktrees,
  readTextFile,
  removeWorktree,
  resolveRawFile,
  uploadFile,
} from './lib/fs.mjs';
import { SessionPool } from './lib/session-pool.mjs';
import {
  listCredentials,
  removeApiKey,
  setApiKey,
} from './lib/credentials.mjs';
import {
  configCommands,
  configModels,
  configThinkingLevels,
} from './lib/config-info.mjs';
import { readDefaultModel, writeDefaultModel } from './lib/default-model.mjs';
import { openEventStream } from './lib/sse.mjs';
import { listPackages, runPackageAction } from './lib/packages.mjs';
import {
  McpConfigError,
  removeMcpServer,
  setMcpEnabled,
  upsertMcpServer,
} from './lib/mcp-store.mjs';
import {
  answerLogin,
  cancelLogin,
  listProviders,
  loginStatus,
  logoutProvider,
  startLogin,
} from './lib/login-flow.mjs';
import { exportHtmlText, exportServerFiles, sessionToMarkdown } from './lib/export.mjs';
import { VERSION } from '@earendil-works/pi-coding-agent';

const args = parseArgs(process.argv.slice(2));

// token 的来源与持久化见 lib/token-store.mjs：
//   优先级 --token 参数 > .token 文件 > 首次生成并写入。
// 于是「够强」和「重启不变」可以同时成立 —— 手机端填一次就行。
const tokenInfo = resolveToken(args.token);
const TOKEN = tokenInfo.token;

const pool = new SessionPool();
pool.startIdleReaper();

/** 局域网发现应答器（UDP）。启动后才有值，退出时要关。 */
let discovery = null;

/** 统一 JSON 响应 */
function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
  });
  res.end(payload);
}

/** 读取并解析 JSON 请求体。图片附件可能较大，上限 8MB。 */
async function readJson(req, limitBytes = 8 * 1024 * 1024) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > limitBytes) throw new Error('请求体过大');
    chunks.push(chunk);
  }
  if (size === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

/**
 * 取请求来源 IP（配对限速用）。
 *
 * 两个必须处理的坑：
 *   1. Node 在 IPv6 监听时给的是 `::ffff:192.168.1.5` 这种映射地址 —— 不归一化
 *      的话，同一个客户端会被算成两个不同 IP，限速直接失效；
 *   2. **不看 X-Forwarded-For**：这个服务端按设计不放在反向代理后面，
 *      而那个头是客户端可以随便写的 —— 信它等于给爆破者一把
 *      「每个请求换一个 IP」的钥匙，限速就白做了。
 */
function clientIpOf(req) {
  const raw = req.socket?.remoteAddress ?? 'unknown';
  return raw.startsWith('::ffff:') ? raw.slice(7) : raw;
}

/** Bearer token 校验（常量时间比较） */function authorized(req) {
  const header = req.headers.authorization ?? '';
  const prefix = 'Bearer ';
  if (!header.startsWith(prefix)) return false;
  const given = header.slice(prefix.length);
  if (given.length !== TOKEN.length) return false;
  let diff = 0;
  for (let i = 0; i < TOKEN.length; i += 1) diff |= given.charCodeAt(i) ^ TOKEN.charCodeAt(i);
  return diff === 0;
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`);
  const path = url.pathname;

  // 健康检查不需要认证，方便客户端探测服务是否在跑
  if (path === '/api/health') {
    return json(res, 200, {
      ok: true,
      server: 'pi-mobile-server',
      version: '0.1.0',
      piVersion: VERSION,
      activeSessions: pool.list().length,
    });
  }

  // ---- 配对：用配对码换 token ----
  // 这一条也必须免认证，否则「拿 token」要先有 token（鸡生蛋）。
  // 安全性靠配对码本身：窗口由用户在电脑端显式开，默认只活 5 分钟，用过即废。
  // 另外在 pairing.mjs 里按来源 IP 做了失败限速（6 位码只有 100 万种，
  // 没有限速时局域网内几分钟就能覆盖相当比例）。
  if (path === '/api/pair' && req.method === 'POST') {
    let body;
    try {
      body = await readJson(req, 64 * 1024);
    } catch (error) {
      return json(res, 400, { error: String(error?.message ?? error) });
    }
    const check = verifyPairingCode(body?.code, clientIpOf(req));
    if (!check.ok) {
      // 冷却中回 429 + Retry-After，让客户端知道「等一会儿再试」而不是「码错了」
      if (check.retryAfterMs) {
        res.setHeader('Retry-After', String(Math.ceil(check.retryAfterMs / 1000)));
        return json(res, 429, { error: check.reason, retryAfterMs: check.retryAfterMs });
      }
      return json(res, 403, { error: check.reason });
    }
    console.log('[server] 配对成功，已下发 token');
    return json(res, 200, {
      token: TOKEN,
      port: args.port,
      piVersion: VERSION,
      addresses: lanAddresses().map((item) => item.address),
    });
  }

  if (!authorized(req)) {
    return json(res, 401, { error: 'unauthorized' });
  }
  try {
    // ---- 会话列表 ----
    if (path === '/api/sessions' && req.method === 'GET') {
      const data = await listSessions({ refresh: url.searchParams.get('refresh') === '1' });
      return json(res, 200, data);
    }

    // ---- 新建会话 ----
    if (path === '/api/sessions' && req.method === 'POST') {
      const body = await readJson(req);
      // 不指定 cwd 时必须能从上到下找到一个，否则会在服务端进程自己的
      // 目录下建会话 —— 那几乎总是错的
      const cwd = body.cwd ?? args.defaultCwd;
      if (!cwd || String(cwd).trim() === '') {
        return json(res, 400, { error: '必须指定 cwd（或在服务端用 --default-cwd 配置默认工作区）' });
      }
      const live = await pool.create(cwd);
      return json(res, 200, { sessionId: live.id, cwd: live.cwd });
    }

    // ---- 远程访问（SSH 反向隧道） ----
    if (path === '/api/remote' && req.method === 'GET') {
      return json(res, 200, tunnelState());
    }
    if (path === '/api/remote/start' && req.method === 'POST') {
      return json(res, 200, startTunnel({ localPort: args.port }));
    }
    // 一键断开（合同④）：关掉隧道就再也不通公网，服务本身照常跑
    if (path === '/api/remote/stop' && req.method === 'POST') {
      return json(res, 200, stopTunnel());
    }

    // ---- 活跃会话（多会话总览：哪个在跑、跑到哪、花了多少） ----
    if (path === '/api/pool' && req.method === 'GET') {
      return json(res, 200, { sessions: pool.listDetailed() });
    }

    // ---- 会话磁盘占用（按工作区分组） ----
    // 必须放在下面 /api/sessions/:id 的正则之前：
    // 那个正则会先匹配到 "disk" 这个"会话 id"。
    if (path === '/api/sessions/disk' && req.method === 'GET') {
      return json(res, 200, await diskUsage());
    }

    // ---- 文件浏览 / Git（只读） ----
    // 允许的根目录 = 用户主目录 + 所有会话用过的工作区
    if (path.startsWith('/api/files') || path.startsWith('/api/file')
        || path.startsWith('/api/git/') || path.startsWith('/api/file-index')
        || (path === '/api/mcp' && req.method === 'GET')) {
      const roots = allowedRoots((await listSessions()).sessions.map((s) => s.cwd));
      const q = url.searchParams;

      if (path === '/api/files' && req.method === 'GET') {
        const target = q.get('path') ?? (roots.length > 1 ? roots[1] : roots[0]);
        return json(res, 200, await listDirectory(target, roots));
      }

      if (path === '/api/file' && req.method === 'GET') {
        const target = q.get('path');
        if (!target) return json(res, 400, { error: '缺少 path' });
        return json(res, 200, await readTextFile(target, roots));
      }

      if (path === '/api/git/status' && req.method === 'GET') {
        const cwd = q.get('cwd') ?? (roots.length > 1 ? roots[1] : roots[0]);
        return json(res, 200, await gitStatus(cwd, roots));
      }

      if (path === '/api/git/diff' && req.method === 'GET') {
        const cwd = q.get('cwd') ?? (roots.length > 1 ? roots[1] : roots[0]);
        return json(res, 200, await gitDiff(cwd, q.get('path') ?? undefined, roots));
      }

      if (path === '/api/mcp' && req.method === 'GET') {
        const cwd = q.get('cwd') ?? (roots.length > 1 ? roots[1] : roots[0]);
        return json(res, 200, await listMcpServers(cwd));
      }

      if (path === '/api/file-index' && req.method === 'GET') {
        const cwd = q.get('cwd') ?? (roots.length > 1 ? roots[1] : roots[0]);
        return json(res, 200, await listWorkspaceFiles(cwd, q.get('q') ?? '', roots));
      }

      if (path === '/api/file/raw' && req.method === 'GET') {
        const target = q.get('path');
        if (!target) return json(res, 400, { error: '缺少 path' });
        const info = await resolveRawFile(target, roots);
        const { readFile: readBytes } = await import('node:fs/promises');
        const buffer = await readBytes(info.path);
        res.writeHead(200, {
          'Content-Type': info.mime,
          'Content-Length': buffer.length,
          'Cache-Control': 'no-store',
          'X-Pi-File-Kind': info.kind,
          'X-Pi-File-Name': encodeURIComponent(info.name),
        });
        res.end(buffer);
        return undefined;
      }

      if (path === '/api/git/worktrees' && req.method === 'GET') {
        const cwd = q.get('cwd') ?? (roots.length > 1 ? roots[1] : roots[0]);
        return json(res, 200, await listWorktrees(cwd, roots));
      }

      if (path === '/api/git/worktrees' && req.method === 'POST') {
        const body = await readJson(req);
        const cwd = body.cwd ?? (roots.length > 1 ? roots[1] : roots[0]);
        const result = await addWorktree({
          cwd,
          dir: body.dir,
          branch: body.branch,
          base: body.base,
        }, roots);
        console.log(`[server] 已新建 worktree ${body.dir}`);
        return json(res, 200, result);
      }

      if (path === '/api/git/worktrees' && req.method === 'DELETE') {
        const cwd = q.get('cwd') ?? (roots.length > 1 ? roots[1] : roots[0]);
        const dir = q.get('path');
        if (!dir) return json(res, 400, { error: '缺少 path' });
        const result = await removeWorktree(
          { cwd, dir, force: q.get('force') === '1' },
          roots,
        );
        console.log(`[server] 已删除 worktree ${dir}`);
        return json(res, 200, result);
      }

      return json(res, 404, { error: 'not found', path });
    }

    // ---- 文件上传（手机 → 工作区） ----
    if (path === '/api/upload' && req.method === 'POST') {
      const body = await readJson(req);
      const roots = allowedRoots((await listSessions()).sessions.map((s) => s.cwd));
      const result = await uploadFile(
        {
          dir: body.dir,
          name: body.name,
          base64: body.base64 ?? body.content,
          overwrite: body.overwrite === true,
        },
        roots,
      );
      console.log(`[server] 已上传 ${result.path}（${result.size} 字节）`);
      return json(res, 200, result);
    }

    // ---- Provider 凭据（读/增/删；不返回密钥本体） ----
    if (path === '/api/credentials' && req.method === 'GET') {
      return json(res, 200, await listCredentials());
    }

    if (path === '/api/credentials' && req.method === 'POST') {
      const body = await readJson(req);
      const result = await setApiKey(body.provider, body.apiKey);
      console.log(`[server] 已写入 provider 凭据: ${result.provider}`);
      return json(res, 200, result);
    }

    // ---- 会话无关的配置信息（模型 / 思考等级 / 命令） ----
    // 没有打开的会话时 App 也读得到，AI 配置页因此不再空白。
    if (path === '/api/config/models' && req.method === 'GET') {
      return json(res, 200, await configModels(url.searchParams.get('cwd')));
    }

    if (path === '/api/config/thinking-levels' && req.method === 'GET') {
      return json(
        res,
        200,
        await configThinkingLevels(
          url.searchParams.get('cwd'),
          url.searchParams.get('provider'),
          url.searchParams.get('model'),
        ),
      );
    }

    if (path === '/api/config/commands' && req.method === 'GET') {
      return json(res, 200, await configCommands(url.searchParams.get('cwd')));
    }

    // ---- 用量统计（全部从落盘 JSONL 算） ----
    // days 可调：45 天是默认窗口（够看趋势），要核对历史就把窗口放大。
    if (path === '/api/usage' && req.method === 'GET') {
      const days = Number(url.searchParams.get('days')) || 45;
      return json(res, 200, await usageSummary({ days: Math.min(Math.max(days, 1), 3650) }));
    }

    const usageMatch = path.match(/^\/api\/sessions\/([^/]+)\/usage$/);
    if (usageMatch && req.method === 'GET') {
      try {
        return json(res, 200, await sessionUsage(usageMatch[1]));
      } catch (error) {
        return json(res, 404, { error: String(error.message ?? error) });
      }
    }

    // ---- 本轮改动速览（改了哪些文件、增删多少行；从 JSONL 里数） ----
    const turnMatch = path.match(/^\/api\/sessions\/([^/]+)\/turn-summary$/);
    if (turnMatch && req.method === 'GET') {
      try {
        const summary = await turnSummaryForSession(turnMatch[1]);
        if (!summary) return json(res, 404, { error: 'session not found' });
        return json(res, 200, summary);
      } catch (error) {
        // 会话没找到就是 404，其余当 500（别把「找不到」说成服务器坏了）
        const message = String(error.message ?? error);
        return json(res, message.startsWith('未找到会话') ? 404 : 500, { error: message });
      }
    }

    // pi 的默认模型（新会话用什么）—— 读 / 写 ~/.pi/agent/settings.json
    if (path === '/api/config/default-model' && req.method === 'GET') {
      return json(res, 200, await readDefaultModel());
    }

    if (path === '/api/config/default-model' && req.method === 'POST') {
      const body = await readJson(req);
      try {
        return json(res, 200, await writeDefaultModel(body.provider, body.modelId));
      } catch (error) {
        return json(res, 400, { error: String(error.message ?? error) });
      }
    }

    const credMatch = path.match(/^\/api\/credentials\/([^/]+)$/);
    if (credMatch && req.method === 'DELETE') {
      const provider = decodeURIComponent(credMatch[1]);
      const result = await removeApiKey(provider);
      console.log(`[server] 已删除 provider 凭据: ${result.provider}`);
      return json(res, 200, result);
    }

    // ---- 删除会话 ----
    const sessionMatch = path.match(/^\/api\/sessions\/([^/]+)$/);
    if (sessionMatch && req.method === 'DELETE') {
      const id = decodeURIComponent(sessionMatch[1]);
      // 正在跑的会话不允许直接删：合同④要求「不能误删在跑的」。
      // 手机端上误点一次就把跑了一半的活干掉，代价太大 —— 要删先停下来。
      const running = pool.get(id);
      if (running?.isStreaming && url.searchParams.get('force') !== '1') {
        return json(res, 409, {
          error: '这条会话正在运行，先停下再删',
          running: true,
        });
      }
      // 没在跑但有活着的实例：先释放（会触发扩展的 session_shutdown），再删文件
      await pool.dispose(id);
      const result = await deleteSession(id);
      console.log(`[server] 已删除会话 ${id}`);
      return json(res, 200, { deleted: true, id: result.id });
    }

    // ---- 会话导出 ----
    // 手机端的「导出」不能只是得到一个服务端路径：
    //   GET  ?format=markdown → 直接把 Markdown 文本回给 App（可预览/复制/存手机）
    //   GET  ?format=html     → 导出 HTML 并把内容回给 App（也可以旁路浏览器下载）
    //   POST                  → 只写到服务端磁盘（HTML + JSONL），返回路径
    const exportMatch = path.match(/^\/api\/sessions\/([^/]+)\/export$/);
    if (exportMatch) {
      const id = decodeURIComponent(exportMatch[1]);
      const live = await pool.open(id);
      const format = url.searchParams.get('format') ?? 'markdown';

      if (req.method === 'GET' && format === 'markdown') {
        const result = sessionToMarkdown(live);
        return json(res, 200, result);
      }

      if (req.method === 'GET' && format === 'html') {
        const result = await exportHtmlText(live);
        return json(res, 200, result);
      }

      if (req.method === 'POST') {
        const result = await exportServerFiles(live);
        console.log(`[server] 已导出会话 ${id}: ${result.html ?? '(html 失败)'}`);
        return json(res, 200, result);
      }

      return json(res, 400, { error: '不支持的导出方式', format });
    }

    // ---- SSE 事件流 ----
    const eventsMatch = path.match(/^\/api\/sessions\/([^/]+)\/events$/);
    if (eventsMatch && req.method === 'GET') {
      const id = decodeURIComponent(eventsMatch[1]);
      // 惰性打开：客户端连上才创建 AgentSession（实测约 1 秒）
      return openEventStream(req, res, () => pool.open(id));
    }

    // ---- 扩展对话框回应 ----
    const uiMatch = path.match(/^\/api\/sessions\/([^/]+)\/ui-response$/);
    if (uiMatch && req.method === 'POST') {
      const id = decodeURIComponent(uiMatch[1]);
      const body = await readJson(req);
      const live = pool.get(id);
      if (!live) return json(res, 404, { error: '会话未在运行' });
      const accepted = live.resolveUiRequest(body.id, body);
      return json(res, 200, { accepted });
    }

    // ---- 命令入口 ----
    const commandMatch = path.match(/^\/api\/sessions\/([^/]+)\/command$/);
    if (commandMatch && req.method === 'POST') {
      const id = decodeURIComponent(commandMatch[1]);
      const body = await readJson(req);

      // 已有会话不在池里就打开；池里没有且磁盘上也没有则报错
      const live = await pool.open(id);
      const response = await live.send(body, pool);
      return json(res, 200, response);
    }

    // ---- MCP 服务器：增 / 改 / 删 / 启用停用（写 mcp.json） ----
    if (path === '/api/mcp' && req.method === 'POST') {
      const body = await readJson(req);
      const cwd = body.cwd ?? url.searchParams.get('cwd') ?? undefined;
      const result = await upsertMcpServer({ ...body, cwd });
      console.log(`[server] 已写入 MCP 配置 ${result.name}（${result.scope}）`);
      return json(res, 200, result);
    }

    const mcpNameMatch = path.match(/^\/api\/mcp\/([^/]+)$/);
    if (mcpNameMatch && (req.method === 'DELETE' || req.method === 'PATCH')) {
      const name = decodeURIComponent(mcpNameMatch[1]);
      const scope = url.searchParams.get('scope') ?? 'user';
      const cwd = url.searchParams.get('cwd') ?? undefined;
      if (req.method === 'DELETE') {
        const result = await removeMcpServer({ name, scope, cwd });
        console.log(`[server] 已删除 MCP 配置 ${result.name}（${result.scope}）`);
        return json(res, 200, result);
      }
      const body = await readJson(req);
      const result = await setMcpEnabled({ name, scope, cwd, enabled: body.enabled });
      return json(res, 200, result);
    }

    // ---- Provider 登录（API Key 向导 / OAuth） ----
    if (path === '/api/providers' && req.method === 'GET') {
      return json(res, 200, await listProviders());
    }

    if (path === '/api/login' && req.method === 'POST') {
      const body = await readJson(req);
      const started = await startLogin(body.provider, body.type ?? 'api_key');
      return json(res, 200, started);
    }

    if (path === '/api/logout' && req.method === 'POST') {
      const body = await readJson(req);
      const result = await logoutProvider(body.provider);
      console.log(`[server] 已退出登录 ${result.provider}`);
      return json(res, 200, result);
    }

    const loginMatch = path.match(/^\/api\/login\/([^/]+)$/);
    // ---- pi 包（插件）管理 ----
    if (path === '/api/packages') {
      const q = url.searchParams;
      if (req.method === 'GET') {
        return json(res, 200, await listPackages(q.get('cwd')));
      }
      if (req.method === 'POST') {
        const body = await readJson(req);
        const result = await runPackageAction({
          cwd: body.cwd ?? q.get('cwd'),
          action: body.action,
          source: body.source,
          local: body.local === true,
        });
        console.log(`[server] 插件 ${body.action}: ${body.source ?? '(全部)'}`);
        return json(res, 200, result);
      }
    }

    if (loginMatch) {
      const taskId = decodeURIComponent(loginMatch[1]);
      if (req.method === 'GET') {
        const status = loginStatus(taskId);
        if (!status) return json(res, 404, { error: '登录任务不存在或已结束' });
        return json(res, 200, status);
      }
      if (req.method === 'POST') {
        const body = await readJson(req);
        if (body.cancel === true) return json(res, 200, { cancelled: cancelLogin(taskId) });
        return json(res, 200, { accepted: answerLogin(taskId, body.answer) });
      }
    }

    return json(res, 404, { error: 'not found', path });
  } catch (error) {
    if (error instanceof McpConfigError) {
      return json(res, 400, { error: error.message });
    }
    if (error instanceof FsAccessError) {
      return json(res, 403, { error: error.message });
    }
    console.error('[server] 处理失败:', error);
    return json(res, 500, { error: String(error?.message ?? error) });
  }
});

server.listen(args.port, args.host, () => {
  const shown = args.host === '0.0.0.0' ? '<本机局域网IP>' : args.host;
  console.log('pi-mobile-server 已启动');
  console.log(`  pi 版本   : ${VERSION}`);
  console.log(`  监听      : http://${args.host}:${args.port}`);
  console.log(`  手机访问  : http://${shown}:${args.port}`);
  // 合同③：token 不进日志。启动日志经常被截图/贴到聊天里，
  // 明文打出来等于把钥匙一起贴出去。
  console.log(`  token     : ${maskSecret(TOKEN)}（手机端填完整值，这里只显示脱敏版）`);
  console.log(`  token 来源: ${describeSource(tokenInfo.source)}`);
  if (tokenInfo.source === 'generated') {
    // 只在这时候提示文件位置：以后每次启动都一样，没必要每次刷屏
    console.log(`              完整值在 ${tokenInfo.path}（已加入 .gitignore）`);
  }

  // 局域网里能被手机看到的地址（有线/无线可能不止一个，全列出来）
  const addresses = lanAddresses();
  if (addresses.length > 0) {
    console.log(`  局域网地址: ${addresses.map((item) => `${item.address}（${item.name}）`).join('、')}`);
  }

  // 远程访问：--tunnel 启动时就开好，手机不用等
  if (args.tunnel) {
    const state = startTunnel({ localPort: args.port });
    console.log(`  远程入口  : ${state.url || '正在建立隧道（约 3-10 秒，之后用 /api/remote 或 App 查看）'}`);
  }

  // 配对窗口默认开 5 分钟：手机扫到就能直接配对，不必再回电脑敲命令。
  // 要关掉就重启时用 --no-pair（或等它自己过期）。
  if (!args.noPair) {
    const pairing = openPairingWindow();
    const minutes = Math.round(pairing.windowMs / 60000);
    console.log(`  配对码    : ${pairing.code}（${minutes} 分钟内有效，手机扫局域网后填它）`);
    console.log('              不想开就用 --no-pair 启动，或随时 Ctrl+C 重启');
  } else {
    console.log('  配对码    : 已关闭（--no-pair）');
  }

  // 局域网发现：应答手机端的 UDP 广播（默认 30143）
  discovery = startDiscovery({
    httpPort: args.port,
    piVersion: VERSION,
    pairingOpen: isPairingOpen,
    onQuery: (info) => console.log(`[discovery] ${info.from} 正在查找服务端`),
  });
  console.log(`  发现端口  : udp/${discovery.port}`);
  console.log('  Ctrl+C 停止');
});

// 优雅退出：先释放会话（扩展要处理 session_shutdown），再关监听
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    console.log(`\n收到 ${signal}，正在停止…`);
    void (async () => {
      discovery?.close();
      closePairingWindow();
      stopTunnel();
      await pool.disposeAll();
      server.close(() => process.exit(0));
      // 兜底：5 秒内没关完就强退
      setTimeout(() => process.exit(0), 5000).unref();
    })();
  });
}
