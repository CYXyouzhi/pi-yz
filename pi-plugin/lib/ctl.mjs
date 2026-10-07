// pi-mobile-server 的进程控制（纯 Node，不依赖 pi 的 API）。
//
// 为什么抽出来：这样它可以被 pi 扩展调用，也能被命令行/测试直接调用 ——
// 不需要启动一个模型就能验证「起得来、停得掉、状态读得到」。

import { spawn } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, openSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { homedir, networkInterfaces } from 'node:os';

// 路径可以被环境变量覆盖 —— 测试时指到临时目录，就不会碰到真实的状态文件。
// 生产用法不设这些变量，走默认的 ~/.pi/agent/。
export const CONFIG_PATH = process.env.PI_MOBILE_CONFIG_PATH
  ?? join(homedir(), '.pi', 'agent', 'pi-mobile-server.json');
export const STATE_PATH = process.env.PI_MOBILE_STATE_PATH
  ?? join(homedir(), '.pi', 'agent', 'pi-mobile-server.pid');
export const LOG_PATH = process.env.PI_MOBILE_LOG_PATH
  ?? join(homedir(), '.pi', 'agent', 'pi-mobile-server.log');

/** 本机局域网 IP（手机要连的那个）；找不到就退回回环地址 */
export function lanAddress() {
  const interfaces = networkInterfaces();
  for (const list of Object.values(interfaces)) {
    for (const item of list ?? []) {
      if (item.family === 'IPv4' && !item.internal) return item.address;
    }
  }
  return '127.0.0.1';
}

export function readConfig() {
  try {
    return JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
  } catch {
    return {};
  }
}

export function writeConfig(next) {
  mkdirSync(dirname(CONFIG_PATH), { recursive: true });
  writeFileSync(CONFIG_PATH, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
  return next;
}

/** 服务端入口：默认用包旁边的 server/index.mjs，可用配置或环境变量覆盖 */
export function serverEntry() {
  const config = readConfig();
  if (config.serverEntry) return config.serverEntry;
  if (process.env.PI_MOBILE_SERVER_ENTRY) return process.env.PI_MOBILE_SERVER_ENTRY;
  // pi-plugin/lib/ → ../../server/index.mjs
  return resolve(dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..', '..', 'server', 'index.mjs');
}

function readState() {
  try {
    return JSON.parse(readFileSync(STATE_PATH, 'utf8'));
  } catch {
    return null;
  }
}

function alive(pid) {
  if (!pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

// alive() 只回答「这个号有没有进程」，回答不了「那是不是我们的服务端」。
//
// 为什么不能拿它当「在不在跑」的依据（真实踩坑）：
//   1. PID 会被系统复用 —— 号被别的进程捡走后，alive() 仍返回 true；
//   2. 跨重启必然失效 —— Windows 重启后 PID 从低位重新分配，老 pid 文件全是废的；
//   3. 它检测不到「手动起的服务」—— 那时端口上有服务、pid 文件里却没有。
// 所以权威信号只能是端口探活，PID 仅用于 stop 时「杀谁」。

/**
 * 权威状态：pid 存活 + 端口探活 双重验证，分四种情况。
 *
 *   self    我们自己起的，而且真的在服务          → 复用，不用重起
 *   foreign 端口有人应，但不是我们的 pid（手动起） → 不重起、也不停（不是我们能管的）
 *   zombie  进程还在，但端口上没服务（僵死/启动失败）→ 需要清掉重起
 *   down    进程没了、端口也没人应                 → 顺手删掉陈旧的 pid 文件
 */
export async function resolveStatus({ port, token } = {}) {
  const config = readConfig();
  const state = readState();
  const finalPort = port ?? state?.port ?? config.port ?? 30142;
  const finalToken = token ?? config.token ?? null;

  const pidAlive = Boolean(state && alive(state.pid));
  const serving = await probeHealth(finalPort, finalToken);

  let kind;
  if (serving && pidAlive) kind = 'self';
  else if (serving) kind = 'foreign';
  else if (pidAlive) kind = 'zombie';
  else kind = 'down';

  // 进程没了、端口也没人应 —— pid 文件就是垃圾，顺手清掉。
  // 不清的后果：/mobile stop 会对着一个不存在的号发信号，用户看到「已停止」但什么也没发生。
  if (kind === 'down' && existsSync(STATE_PATH)) {
    rmSync(STATE_PATH, { force: true });
  }

  return {
    ...status({ port: finalPort }),
    kind,
    serving,
    pidAlive,
    port: finalPort,
    token: finalToken,
  };
}

/** 读日志最后若干行（用来辨认 EADDRINUSE 这类启动失败）*/
function tailLog(lines = 40) {
  try {
    return readFileSync(LOG_PATH, 'utf8').split('\n').slice(-lines).join('\n');
  } catch {
    return '';
  }
}

/**
 * 同步状态（展示用）。
 * 注意 running 字段只表示「pid 文件里的号还有进程」，**不代表服务真的通** ——
 * 要判断能不能连上，用 resolveStatus()。
 */
export function status({ port } = {}) {
  const config = readConfig();
  const state = readState();
  const running = state && alive(state.pid);
  return {
    running: Boolean(running),
    pid: running ? state.pid : null,
    port: port ?? state?.port ?? config.port ?? 30142,
    token: config.token ?? null,
    host: state?.host ?? config.host ?? '0.0.0.0',
    hostAddress: lanAddress(),
    startedAt: state?.startedAt ?? null,
    logPath: LOG_PATH,
    configPath: CONFIG_PATH,
    entry: serverEntry(),
  };
}

/**
 * 起服务：detached + 日志重定向到 LOG_PATH。
 *
 * 先问权威状态再决定做什么 —— 绝不仅凭 pid 就认定「已经在跑」：
 *   self    → 复用，直接返回
 *   foreign → 端口上有别的服务占着，不重起也不报成功（否则手机连上的是别人）
 *   zombie  → 清掉僵死进程再重起
 *   down    → 正常启动
 */
export async function start({ port, host = '0.0.0.0', token } = {}) {
  const current = await resolveStatus({ port, token });
  const finalPort = current.port;

  if (current.kind === 'self') {
    return { ...current, healthy: true, alreadyRunning: true };
  }

  if (current.kind === 'foreign') {
    return {
      ...current,
      healthy: true,
      alreadyRunning: true,
      foreign: true,
      hint: `端口 ${finalPort} 上已有服务在跑，但不是本插件拉起的（可能是手动启动或别的程序）。`
        + '没有重复拉起 —— 手机上直接连它就行；要用插件接管，先手动停掉那个进程。',
    };
  }

  // 僵死：进程还在但端口没服务。留着它会占住端口导致新进程 EADDRINUSE。
  if (current.kind === 'zombie') {
    await stop({ force: true });
  }

  const config = readConfig();
  const finalToken = token ?? config.token ?? null;
  writeConfig({ ...config, port: finalPort, host, token: finalToken });

  const entry = serverEntry();
  if (!existsSync(entry)) {
    throw new Error(`找不到服务端入口：${entry}（可用 PI_MOBILE_SERVER_ENTRY 指定）`);
  }

  mkdirSync(dirname(LOG_PATH), { recursive: true });
  const log = openSync(LOG_PATH, 'a');
  const args = [entry, '--host', host, '--port', String(finalPort)];
  if (finalToken) args.push('--token', finalToken);

  // 记下启动前的日志长度：启动失败原因只看这之后写进去的部分，
  // 否则会把上一次的 EADDRINUSE 误判成这次的。
  const logMark = tailLog(1_000_000).length;

  const child = spawn(process.execPath, args, {
    detached: true,
    stdio: ['ignore', log, log],
    windowsHide: true,
  });
  child.unref();

  const state = {
    pid: child.pid,
    port: finalPort,
    host,
    startedAt: new Date().toISOString(),
  };
  writeFileSync(STATE_PATH, `${JSON.stringify(state, null, 2)}\n`, 'utf8');

  // 等它真的起来（最多 8 秒），并把 /api/health 探通
  const ok = await waitHealthy(finalPort, 8000, child);
  if (!ok) {
    // 探活失败：从日志增量里找出人话原因，别把 Node 原始堆栈丢给用户
    const fresh = tailLog(1_000_000).slice(logMark);
    let reason = '进程已拉起但健康检查没通过，看日志确认原因';
    if (/EADDRINUSE/.test(fresh)) {
      reason = `端口 ${finalPort} 已被占用（EADDRINUSE）—— 可能上个进程没停干净，或用 /mobile doctor 看是谁占的`;
    } else if (/EACCES/.test(fresh)) {
      reason = `端口 ${finalPort} 没权限监听（EACCES）—— 换个大于 1024 的端口试试`;
    } else if (!alive(child.pid)) {
      reason = '进程刚起来就退出了，看日志末尾';
    }
    // 进程既然没服务成功，pid 文件就别留着骗人
    if (!alive(child.pid)) rmSync(STATE_PATH, { force: true });
    return { ...status({ port: finalPort }), kind: 'down', serving: false, healthy: false, alreadyRunning: false, reason, logTail: fresh.slice(-800) };
  }

  return { ...(await resolveStatus({ port: finalPort })), healthy: true, alreadyRunning: false };
}

/** 探一次健康接口，拿不到就当没有（doctor 用来区分「谁起的」） */
async function probeHealth(port, token) {
  try {
    const headers = token ? { Authorization: `Bearer ${token}` } : {};
    // 必须带超时：端口上可能有个「会 accept 但不应答 HTTP」的程序（别的 TCP 服务），
    // 没超时的话这个 fetch 会永久挂着，/mobile start 就永远不返回。
    const response = await fetch(`http://127.0.0.1:${port}/api/health`, {
      headers,
      signal: AbortSignal.timeout(2000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

async function waitHealthy(port, timeoutMs, child) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/api/health`, {
        signal: AbortSignal.timeout(1500),
      });
      if (response.ok) return true;
    } catch {
      // 还没起，继续等
    }
    // 进程已经退出了（比如端口冲突），再等也是白等
    if (child && !alive(child.pid)) return false;
    await new Promise((r) => setTimeout(r, 400));
  }
  return false;
}

/**
 * 停服务。
 *
 * 默认只杀 pid 文件里记的那个（也就是「插件拉的」）；
 * force 用于清理僵死进程（进程在、但端口没服务）—— 它占着端口，不清就起不来新的。
 */
export async function stop({ force = false } = {}) {
  const state = readState();

  if (!state?.pid || !alive(state.pid)) {
    if (existsSync(STATE_PATH)) rmSync(STATE_PATH);
    // 号死了，但端口上可能还有别人起的服务 —— 说清楚，别让人以为停干净了
    const config = readConfig();
    const serving = await probeHealth(state?.port ?? config.port ?? 30142, config.token ?? null);
    return {
      stopped: false,
      reason: serving ? '没有本插件拉起的服务；端口上的服务是别的进程启的，不归 /mobile 管' : '没有在跑的服务端',
    };
  }

  try {
    process.kill(state.pid);
  } catch (error) {
    return { stopped: false, reason: String(error.message ?? error) };
  }
  rmSync(STATE_PATH, { force: true });

  // 给进程一点退出时间；force 场景下要确保端口真的松开，否则新进程必遭 EADDRINUSE
  if (force) {
    const config = readConfig();
    const port = state.port ?? config.port ?? 30142;
    for (let i = 0; i < 10; i += 1) {
      if (!(await probeHealth(port, config.token ?? null))) return { stopped: true, pid: state.pid };
      await new Promise((r) => setTimeout(r, 300));
    }
    return { stopped: true, pid: state.pid, portStillBusy: true };
  }

  return { stopped: true, pid: state.pid };
}

/** 自检：状态 + 健康接口 + 会话数 + 版本 */
export async function doctor() {
  const info = await resolveStatus();

  // 进程表里没有，但端口上有服务在跑 —— 那多半是 start.cmd / 手动 nohup 起的。
  // 这个区分很重要：不能把别人起的服务说成「没在跑」，也不能让 /mobile stop 去乱杀。
  if (info.kind === 'foreign') {
    return {
      ...info,
      running: true,
      healthy: true,
      foreign: true,
      hint: `端口 ${info.port} 上有服务在跑，但不是本插件拉起的（可能是 start.cmd 或手动启动的）。`
        + '/mobile start 不会重复拉起，/mobile stop 也不会去杀它。',
    };
  }

  if (info.kind === 'zombie') {
    return {
      ...info,
      healthy: false,
      hint: `进程 ${info.pid} 还在，但端口 ${info.port} 上没有服务应答（僵死）。`
        + '用 /mobile start 会自动清掉它再重新拉起。',
    };
  }

  if (info.kind === 'down') {
    return { ...info, running: false, healthy: false, foreign: false, hint: '服务端没在跑：用 /mobile start 启动' };
  }

  let health = null;
  let sessions = null;
  try {
    const headers = info.token ? { Authorization: `Bearer ${info.token}` } : {};
    // 每个请求都要自己的一份 signal —— AbortSignal.timeout() 是一次性的：
    // 复用一个的话，第一个请求用完（或超时）后第二个会直接被 abort 掉。
    health = await (await fetch(`http://127.0.0.1:${info.port}/api/health`, {
      headers,
      signal: AbortSignal.timeout(3000),
    })).json();
    const list = await (await fetch(`http://127.0.0.1:${info.port}/api/sessions`, {
      headers,
      signal: AbortSignal.timeout(3000),
    })).json();
    sessions = list.count ?? null;
  } catch (error) {
    return { ...info, healthy: false, hint: `探活失败：${String(error.message ?? error)}` };
  }
  return { ...info, healthy: true, health, sessions };
}

/** 手机端要填的三样东西，拼成一句可以直接抄的话 */
export function connectInfo(info = status()) {
  return [
    `地址  ${info.hostAddress}`,
    `端口  ${info.port}`,
    `token ${info.token ?? '(未设置，服务端会每次随机生成)'}`,
  ].join('\n');
}
