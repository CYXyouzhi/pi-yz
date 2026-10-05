// pi-mobile-server 的进程控制（纯 Node，不依赖 pi 的 API）。
//
// 为什么抽出来：这样它可以被 pi 扩展调用，也能被命令行/测试直接调用 ——
// 不需要启动一个模型就能验证「起得来、停得掉、状态读得到」。

import { spawn } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, openSync, rmSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { homedir, networkInterfaces } from 'node:os';

export const CONFIG_PATH = join(homedir(), '.pi', 'agent', 'pi-mobile-server.json');
export const STATE_PATH = join(homedir(), '.pi', 'agent', 'pi-mobile-server.pid');
export const LOG_PATH = join(homedir(), '.pi', 'agent', 'pi-mobile-server.log');

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

export function status() {
  const config = readConfig();
  const state = readState();
  const running = state && alive(state.pid);
  return {
    running: Boolean(running),
    pid: running ? state.pid : null,
    port: state?.port ?? config.port ?? 30142,
    token: config.token ?? null,
    host: state?.host ?? config.host ?? '0.0.0.0',
    hostAddress: lanAddress(),
    startedAt: state?.startedAt ?? null,
    logPath: LOG_PATH,
    configPath: CONFIG_PATH,
    entry: serverEntry(),
  };
}

/** 起服务：detached + 日志重定向到 LOG_PATH；已有活着的进程就直接复用 */
export async function start({ port, host = '0.0.0.0', token } = {}) {
  const current = status();
  if (current.running) return { ...current, alreadyRunning: true };

  const config = readConfig();
  const finalPort = port ?? config.port ?? 30142;
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

  // 等它真的起来（最多 6 秒），并把 /api/health 探通
  const ok = await waitHealthy(finalPort, 6000);
  return { ...status(), healthy: ok, alreadyRunning: false };
}

/** 探一次健康接口，拿不到就当没有（doctor 用来区分「谁起的」） */
async function probeHealth(port, token) {
  try {
    const headers = token ? { Authorization: `Bearer ${token}` } : {};
    const response = await fetch(`http://127.0.0.1:${port}/api/health`, { headers });
    return response.ok;
  } catch {
    return false;
  }
}

async function waitHealthy(port, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/api/health`);
      if (response.ok) return true;
    } catch {
      // 还没起，继续等
    }
    await new Promise((r) => setTimeout(r, 400));
  }
  return false;
}

export function stop() {
  const state = readState();
  if (!state?.pid || !alive(state.pid)) {
    if (existsSync(STATE_PATH)) rmSync(STATE_PATH);
    return { stopped: false, reason: '没有在跑的服务端' };
  }
  try {
    process.kill(state.pid);
  } catch (error) {
    return { stopped: false, reason: String(error.message ?? error) };
  }
  rmSync(STATE_PATH, { force: true });
  return { stopped: true, pid: state.pid };
}

/** 自检：状态 + 健康接口 + 会话数 + 版本 */
export async function doctor() {
  const info = status();

  // 进程表里没有，但端口上有服务在跑 —— 那多半是 start.cmd / 手动 nohup 起的。
  // 这个区分很重要：不能把别人起的服务说成「没在跑」，也不能让 /mobile stop 去乱杀。
  if (!info.running) {
    const foreign = await probeHealth(info.port, info.token);
    if (foreign) {
      return {
        ...info,
        healthy: true,
        foreign: true,
        hint: `端口 ${info.port} 上有服务在跑，但不是本插件拉起的（可能是 start.cmd 或手动启动的）。`
          + '/mobile start 不会重复拉起，/mobile stop 也不会去杀它。',
      };
    }
    return { ...info, healthy: false, foreign: false, hint: '服务端没在跑：用 /mobile start 启动' };
  }
  let health = null;
  let sessions = null;
  try {
    const headers = info.token ? { Authorization: `Bearer ${info.token}` } : {};
    health = await (await fetch(`http://127.0.0.1:${info.port}/api/health`, { headers })).json();
    const list = await (await fetch(`http://127.0.0.1:${info.port}/api/sessions`, { headers })).json();
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
