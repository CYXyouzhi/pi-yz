// MCP 服务器的增删改（写 pi 的 mcp.json）。
//
// 为什么放服务端：mcp.json 在电脑上（~/.pi/agent/mcp.json 与 <cwd>/.pi/mcp.json），
// 手机上改不了；pi-web 也是这条路线（配置写服务端，界面只做编辑）。
//
// 只做「改配置」，不负责连服务器：连接由 pi 的 MCP 扩展在会话启动时做。

import { existsSync, mkdirSync } from 'node:fs';
import { readFile, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';

/** 服务器名：字母数字、下划线、连字符、点；空名或带空格会搞乱工具命名空间 */
const NAME_PATTERN = /^[A-Za-z0-9._-]{1,64}$/;

export class McpConfigError extends Error {}

function userFile() {
  return path.join(homedir(), '.pi', 'agent', 'mcp.json');
}

function projectFile(cwd) {
  return path.join(cwd, '.pi', 'mcp.json');
}

function fileFor(scope, cwd) {
  if (scope === 'project') {
    if (!cwd) throw new McpConfigError('项目级配置需要工作区路径');
    return projectFile(cwd);
  }
  return userFile();
}

async function readConfig(file) {
  try {
    const text = await readFile(file, 'utf8');
    const parsed = JSON.parse(text);
    const servers = parsed?.mcpServers;
    return {
      raw: parsed && typeof parsed === 'object' ? parsed : {},
      servers: servers && typeof servers === 'object' ? servers : {},
    };
  } catch (error) {
    if (error?.code === 'ENOENT') return { raw: {}, servers: {} };
    if (error instanceof SyntaxError) {
      throw new McpConfigError(`${path.basename(file)} 不是合法 JSON：${error.message}`);
    }
    throw error;
  }
}

/** 原子写：先写临时文件再改名，避免写一半被读到 */
async function writeConfig(file, raw) {
  const dir = path.dirname(file);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  const temp = `${file}.tmp-${process.pid}`;
  await writeFile(temp, `${JSON.stringify(raw, null, 2)}\n`, 'utf8');
  await rename(temp, file);
}

/**
 * 校验并规整一条配置。
 * 规则照 pi 的 mcp.json 语义：stdio 要 command，http 要 url；
 * 非 loopback 的 http 必须 https（会把凭据发过去）。
 */
export function normalizeConfig(input) {
  const config = input && typeof input === 'object' ? input : {};
  const url = typeof config.url === 'string' ? config.url.trim() : '';
  const command = typeof config.command === 'string' ? config.command.trim() : '';

  if (!url && !command) throw new McpConfigError('要么填 url（远程），要么填 command（本地）');
  if (url && command) throw new McpConfigError('url 与 command 只能填一个');

  const next = {};
  if (url) {
    let parsed;
    try {
      parsed = new URL(url);
    } catch {
      throw new McpConfigError(`url 不合法：${url}`);
    }
    const loopback = ['127.0.0.1', 'localhost', '::1', '[::1]'].includes(parsed.hostname);
    if (parsed.protocol !== 'https:' && !loopback) {
      throw new McpConfigError('远程 MCP 必须用 https（明文 http 会把凭据发出去）');
    }
    next.type = 'http';
    next.url = url;
    if (config.headers && typeof config.headers === 'object') next.headers = config.headers;
  } else {
    next.type = 'stdio';
    next.command = command;
    const args = Array.isArray(config.args)
      ? config.args.map((a) => String(a)).filter((a) => a.length > 0)
      : typeof config.args === 'string'
        ? config.args.split(/\s+/).filter(Boolean)
        : [];
    if (args.length) next.args = args;
    if (config.env && typeof config.env === 'object') next.env = config.env;
    if (typeof config.cwd === 'string' && config.cwd.trim()) next.cwd = config.cwd.trim();
  }

  if (typeof config.description === 'string' && config.description.trim()) {
    next.description = config.description.trim();
  }
  if (typeof config.enabled === 'boolean') next.enabled = config.enabled;
  if (typeof config.exposure === 'string') next.exposure = config.exposure;
  return next;
}

/** 新增或覆盖一条配置（同名直接覆盖） */
export async function upsertMcpServer({ name, scope = 'user', cwd, config }) {
  const trimmed = String(name ?? '').trim();
  if (!NAME_PATTERN.test(trimmed)) {
    throw new McpConfigError('名字只能用字母数字与 . _ -（1-64 位），因为它会进工具命名空间');
  }
  const file = fileFor(scope, cwd);
  const { raw, servers } = await readConfig(file);
  const next = normalizeConfig(config);
  servers[trimmed] = next;
  raw.mcpServers = servers;
  await writeConfig(file, raw);
  return { name: trimmed, scope, file, config: next };
}

/** 删除一条配置 */
export async function removeMcpServer({ name, scope = 'user', cwd }) {
  const trimmed = String(name ?? '').trim();
  const file = fileFor(scope, cwd);
  const { raw, servers } = await readConfig(file);
  if (!(trimmed in servers)) {
    throw new McpConfigError(`${trimmed} 不在 ${scope === 'project' ? '项目级' : '用户级'} 配置里`);
  }
  delete servers[trimmed];
  raw.mcpServers = servers;
  await writeConfig(file, raw);
  return { name: trimmed, scope, file };
}

/** 启用/停用（pi 侧 enabled:false 表示保留条目但不连接） */
export async function setMcpEnabled({ name, scope = 'user', cwd, enabled }) {
  const trimmed = String(name ?? '').trim();
  const file = fileFor(scope, cwd);
  const { raw, servers } = await readConfig(file);
  const current = servers[trimmed];
  if (!current) throw new McpConfigError(`找不到 ${trimmed}`);
  servers[trimmed] = { ...current, enabled: Boolean(enabled) === true };
  raw.mcpServers = servers;
  await writeConfig(file, raw);
  return { name: trimmed, scope, enabled: servers[trimmed].enabled };
}
