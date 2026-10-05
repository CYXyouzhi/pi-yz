// 会话列表：读 ~/.pi/agent/sessions 下的全部会话。
//
// 与命令行 pi 共用同一批文件，所以手机端看到的会话和 CLI 完全一致。

import { SessionManager } from '@earendil-works/pi-coding-agent';
import { unlink } from 'node:fs/promises';
import { existsSync, statSync } from 'node:fs';

// 缓存时长：listAll 首次要扫 200+ 个文件（实测约 900ms），
// 之后命中缓存是微秒级。手机端列表页刷新频率低，30 秒足够。
const CACHE_TTL_MS = 30_000;

// 首条消息在列表里只做预览，截断避免列表响应过大
const PREVIEW_CHARS = 120;
// 会话名可能被用户设成整段文本（实测见过 300+ 字符），列表里必须截断
const NAME_CHARS = 60;

let cache = null; // { at, sessions, pathById }

/** 从会话文件路径里取出会话 id（形如 .../2026-10-02T12-28-04-860Z_<uuid>.jsonl） */
function idFromPath(path) {
  const base = String(path).replace(/\\/g, '/').split('/').pop() ?? '';
  const matched = base.match(/_([0-9a-fA-F-]{36})\.jsonl$/);
  return matched ? matched[1] : null;
}

function clip(text, max) {
  return text.length > max ? text.slice(0, max) + '…' : text;
}

/** 把 SessionInfo 裁剪成客户端需要的字段 */
function toClientSession(info) {
  return {
    id: info.id,
    cwd: info.cwd,
    name: info.name ? clip(info.name, NAME_CHARS) : null,
    created: info.created ?? null,
    modified: info.modified ?? null,
    messageCount: info.messageCount ?? 0,
    preview: clip(info.firstMessage ?? '', PREVIEW_CHARS),
    // 只给父会话 id，不给本地路径：客户端不需要知道服务端的目录结构
    parentId: info.parentSessionPath ? idFromPath(info.parentSessionPath) : null,
  };
}

/**
 * 列出全部会话。
 *
 * 刻意不返回 path：客户端只认 id，服务端内部维护 id → path 映射。
 * 这样客户端无法构造任意路径让服务端去读，避免路径穿越。
 */
export async function listSessions({ refresh = false } = {}) {
  const now = Date.now();
  if (!refresh && cache && now - cache.at < CACHE_TTL_MS) {
    return { ...buildResponse(cache), cached: true };
  }

  const infos = await SessionManager.listAll();

  // 按修改时间倒序：最近用过的排前面
  infos.sort((a, b) => String(b.modified ?? '').localeCompare(String(a.modified ?? '')));

  const pathById = new Map();
  const cwdById = new Map();
  for (const info of infos) {
    pathById.set(info.id, info.path);
    cwdById.set(info.id, info.cwd);
  }

  cache = {
    at: now,
    sessions: infos.map(toClientSession),
    pathById,
    cwdById,
  };
  return { ...buildResponse(cache), cached: false };
}

function buildResponse(entry) {
  const cwds = new Set(entry.sessions.map((s) => s.cwd));
  return {
    sessions: entry.sessions,
    count: entry.sessions.length,
    cwdCount: cwds.size,
    scannedAt: entry.at,
  };
}

/** 由会话 id 取服务端本地文件路径（后续打开会话时用） */
export async function resolveSessionPath(id) {
  if (!cache) await listSessions();
  const path = cache.pathById.get(id);
  if (!path) throw new Error(`未找到会话: ${id}`);
  return path;
}

/** 由会话 id 取本地路径与工作目录（打开会话时两个都要） */
export async function resolveSessionMeta(id) {
  if (!cache) await listSessions();
  let path = cache.pathById.get(id);
  // 刚建出来的会话还没进缓存（30 秒 TTL），强制重扫一次再找
  if (!path) {
    await listSessions({ refresh: true });
    path = cache.pathById.get(id);
  }
  if (!path) throw new Error(`未找到会话: ${id}`);
  return { path, cwd: cache.cwdById.get(id) ?? process.cwd() };
}

/**
 * 删除一条会话。
 *
 * 只删会话文件本身。路径来自 listAll 的结果（服务端自己枚举出来的），
 * 不是客户端传入的，所以不存在任意路径删除的问题。
 *
 * 注意：新建但还没说过话的会话盘上没有文件（pi 是 append-only，
 * 没内容就不落盘），这种只把池里的释放掉，不算错误。
 */
export async function deleteSession(id) {
  let path;
  try {
    ({ path } = await resolveSessionMeta(id));
  } catch {
    return { id, path: null, notPersisted: true };
  }
  await unlink(path);
  // 缓存里还留着这条，置空强制下次重新扫描
  cache = null;
  return { id, path, notPersisted: false };
}

/**
 * 按工作区统计磁盘占用（task-15 的合同④：手机端要知道「谁占了地方、能清哪条」）。
 *
 * 口径：只算会话 JSONL 文件本身的字节数。附件/图片存在会话文件里（base64），
 * 所以这个数就是「删了这条能腾多少」的真实值 —— 不另算一套估算值。
 */
export async function diskUsage() {
  if (!cache) await listSessions();

  const groups = new Map();
  let totalBytes = 0;

  for (const s of cache.sessions) {
    const path = cache.pathById.get(s.id);
    let bytes = 0;
    try {
      if (path && existsSync(path)) bytes = statSync(path).size;
    } catch {
      bytes = 0;
    }
    totalBytes += bytes;

    const cwd = s.cwd ?? '';
    let group = groups.get(cwd);
    if (!group) {
      group = { cwd, bytes: 0, count: 0, sessions: [] };
      groups.set(cwd, group);
    }
    group.bytes += bytes;
    group.count += 1;
    group.sessions.push({
      id: s.id,
      title: s.name || s.preview || '(空会话)',
      bytes,
      messages: s.messageCount ?? 0,
      modified: s.modified ?? null,
    });
  }

  const list = [...groups.values()].sort((a, b) => b.bytes - a.bytes);
  for (const g of list) g.sessions.sort((a, b) => b.bytes - a.bytes);

  return {
    groups: list,
    totalBytes,
    totalSessions: cache.sessions.length,
    scannedAt: cache.at,
    // 口径写给客户端直接显示，免得用户以为漏算了
    basis: '只算会话 JSONL 文件本身（含图片等附件），单位字节',
  };
}
