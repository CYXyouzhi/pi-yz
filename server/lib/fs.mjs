// 文件浏览与 Git 只读查询。
//
// 安全约束：只允许访问「允许的根目录」下的路径 —— 用户主目录 + 所有会话用过的工作区。
// 手机端只能给出路径，没有这层白名单就等于把整台机器的文件系统开出去。

import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import { readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';

/**
 * 读 MCP 服务器配置（只读列举）。
 * pi 的约定：用户级 ~/.pi/agent/mcp.json，项目级 <cwd>/.pi/mcp.json。
 */
export async function listMcpServers(cwd) {
  const read = async (file, scope) => {
    try {
      const text = await readFile(file, 'utf8');
      const parsed = JSON.parse(text);
      const servers = parsed?.mcpServers ?? {};
      return Object.entries(servers).map(([name, config]) => ({
        name,
        scope,
        kind: config?.url ? 'remote' : 'local',
        target: config?.url ?? config?.command ?? '',
        args: Array.isArray(config?.args) ? config.args.join(' ') : '',
        // enabled:false 表示条目保留但不连接（pi 的语义）
        enabled: config?.enabled !== false,
        description: typeof config?.description === 'string' ? config.description : '',
      }));
    } catch {
      return [];
    }
  };

  const user = await read(path.join(homedir(), '.pi', 'agent', 'mcp.json'), 'user');
  const project = cwd ? await read(path.join(cwd, '.pi', 'mcp.json'), 'project') : [];

  // 项目级同名会覆盖用户级
  const byName = new Map();
  for (const item of [...user, ...project]) byName.set(item.name, item);

  return {
    servers: [...byName.values()],
    userCount: user.length,
    projectCount: project.length,
  };
}
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

const TEXT_LIMIT_BYTES = 512 * 1024;
const LIST_LIMIT = 400;

/** 允许访问的根目录集合 */
export function allowedRoots(extraCwds = []) {
  const roots = new Set([homedir()]);
  for (const cwd of extraCwds) {
    if (typeof cwd === 'string' && cwd.trim().length > 1) {
      roots.add(path.resolve(cwd));
    }
  }
  return [...roots];
}

export class FsAccessError extends Error {}

/** 校验路径落在允许的根目录内 */
function assertAllowed(target, roots) {
  const resolved = path.resolve(target);
  const ok = roots.some((root) => {
    const normalizedRoot = path.resolve(root);
    return resolved === normalizedRoot || resolved.startsWith(normalizedRoot + path.sep);
  });
  if (!ok) {
    throw new FsAccessError(`路径不在允许范围内: ${resolved}`);
  }
  return resolved;
}

/** 列目录 */
export async function listDirectory(dir, roots) {
  const resolved = assertAllowed(dir, roots);
  const info = await stat(resolved);
  if (!info.isDirectory()) throw new FsAccessError('不是目录');

  const dirents = await readdir(resolved, { withFileTypes: true });
  const entries = [];
  for (const dirent of dirents.slice(0, LIST_LIMIT)) {
    // 隐藏目录太多，但 .pi / .git 之类有用，所以只跳过大块无关目录
    if (dirent.name === 'node_modules' || dirent.name === '.git') continue;
    const full = path.join(resolved, dirent.name);
    let size = 0;
    let mtime = null;
    try {
      const itemStat = await stat(full);
      size = itemStat.size;
      mtime = itemStat.mtime.toISOString();
    } catch {
      // 权限不足等，忽略大小
    }
    entries.push({
      name: dirent.name,
      path: full,
      type: dirent.isDirectory() ? 'dir' : 'file',
      size,
      mtime,
    });
  }

  entries.sort((a, b) => {
    if (a.type !== b.type) return a.type === 'dir' ? -1 : 1;
    return a.name.localeCompare(b.name);
  });

  // 上一层只在它仍然落在允许范围内时才给。
  // 否则 App 会显示一个「上一级」按钮，点下去必然失败（而且以前会把界面停到半死状态）——
  // 这就是用户报的「文件浏览返回上一级却没回之前一级」。
  const up = path.dirname(resolved);
  let parent = null;
  if (up !== resolved) {
    try {
      parent = assertAllowed(up, roots);
    } catch {
      parent = null; // 超出允许范围：当作到顶了，不提供上一级
    }
  }

  return {
    path: resolved,
    parent,
    entries,
    truncated: dirents.length > LIST_LIMIT,
  };
}

/** 读文本文件（超出上限截断） */
export async function readTextFile(file, roots) {
  const resolved = assertAllowed(file, roots);
  const info = await stat(resolved);
  if (info.isDirectory()) throw new FsAccessError('这是一个目录');

  const buffer = await readFile(resolved);
  const truncated = buffer.length > TEXT_LIMIT_BYTES;
  const slice = truncated ? buffer.subarray(0, TEXT_LIMIT_BYTES) : buffer;
  return {
    path: resolved,
    size: buffer.length,
    truncated,
    text: slice.toString('utf8'),
  };
}

async function git(cwd, args) {
  const { stdout } = await execFileAsync('git', args, {
    cwd,
    maxBuffer: 8 * 1024 * 1024,
    windowsHide: true,
  });
  return stdout;
}

/** git status（porcelain） */
export async function gitStatus(cwd, roots) {
  const resolved = assertAllowed(cwd, roots);
  try {
    const branch = (await git(resolved, ['rev-parse', '--abbrev-ref', 'HEAD'])).trim();
    const raw = await git(resolved, ['status', '--porcelain', '--untracked-files=all']);
    const files = raw
      .split('\n')
      .filter((line) => line.trim().length > 0)
      .slice(0, 300)
      .map((line) => ({
        status: line.slice(0, 2).trim(),
        path: line.slice(3).trim(),
      }));
    return { cwd: resolved, branch, files, isRepo: true };
  } catch (error) {
    // 不是 git 仓库、或没装 git
    return { cwd: resolved, branch: null, files: [], isRepo: false, error: String(error.message ?? error) };
  }
}

/** 单个文件或全仓的 diff */
export async function gitDiff(cwd, filePath, roots) {
  const resolved = assertAllowed(cwd, roots);
  const args = ['diff', '--no-color'];
  if (filePath) {
    const target = path.isAbsolute(filePath) ? path.relative(resolved, filePath) : filePath;
    args.push('--', target);
  }
  try {
    const diff = await git(resolved, args);
    return { cwd: resolved, path: filePath ?? null, diff, empty: diff.trim().length === 0 };
  } catch (error) {
    return { cwd: resolved, path: filePath ?? null, diff: '', empty: true, error: String(error.message ?? error) };
  }
}

/** 供 @ 引用用：列出工作区里的文件（浅层递归，限制数量） */
export async function listWorkspaceFiles(cwd, query, roots) {
  const resolved = assertAllowed(cwd, roots);
  const skip = new Set(['node_modules', '.git', 'build', '.dart_tool', 'dist', '.next', 'windows']);
  const found = [];
  const needle = (query ?? '').toLowerCase();

  async function walk(dir, depth) {
    if (found.length >= 200 || depth > 4) return;
    let dirents;
    try {
      dirents = await readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const dirent of dirents) {
      if (found.length >= 200) return;
      if (dirent.name.startsWith('.') && dirent.name !== '.pi') continue;
      if (skip.has(dirent.name)) continue;
      const full = path.join(dir, dirent.name);
      if (dirent.isDirectory()) {
        await walk(full, depth + 1);
      } else if (needle === '' || dirent.name.toLowerCase().includes(needle)) {
        found.push({
          name: dirent.name,
          path: full,
          relative: path.relative(resolved, full).replaceAll('\\', '/'),
        });
      }
    }
  }

  await walk(resolved, 0);
  return { cwd: resolved, files: found };
}

// ==================== 二进制预览（图片 / PDF / 音频） ====================
//
// 为什么要单开一条：`/api/file` 是「当文本读」，图片读出来是乱码。
// 预览要的是**原字节 + 正确的 Content-Type**，所以这里只做「解析与鉴权」，
// 真正的字节由 index.mjs 流式吐给客户端。

const MIME_BY_EXT = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.bmp': 'image/bmp',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.pdf': 'application/pdf',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.m4a': 'audio/mp4',
  '.ogg': 'audio/ogg',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
};

/** 单文件预览上限（手机端拉太大的没用，还费流量） */
export const RAW_LIMIT_BYTES = 16 * 1024 * 1024;

/** 预览类型：image | pdf | audio | video | text | binary */
export function previewKindFor(mime) {
  if (mime.startsWith('image/') && mime !== 'image/svg+xml') return 'image';
  if (mime === 'application/pdf') return 'pdf';
  if (mime.startsWith('audio/')) return 'audio';
  if (mime.startsWith('video/')) return 'video';
  if (mime.startsWith('text/') || mime === 'application/json') return 'text';
  return 'binary';
}

/**
 * 解析要预览的文件（鉴权 + 尺寸 + 类型）。
 * @returns {{path: string, size: number, mime: string, kind: string, name: string}}
 */
export async function resolveRawFile(file, roots) {
  const resolved = assertAllowed(file, roots);
  const info = await stat(resolved);
  if (info.isDirectory()) throw new FsAccessError('这是一个目录');
  if (info.size > RAW_LIMIT_BYTES) {
    throw new FsAccessError(
      `文件 ${(info.size / 1048576).toFixed(1)}MB，超过预览上限 ${RAW_LIMIT_BYTES / 1048576}MB`,
    );
  }
  const ext = path.extname(resolved).toLowerCase();
  let mime = MIME_BY_EXT[ext];
  if (!mime) {
    // 扑底：没有扩展名或少见扩展名时用「内容嗅探」——
    // 文本（含 UTF-8 中文）里不会有 NUL 字节，二进制几乎一定有。
    const probe = (await readFile(resolved)).subarray(0, 512);
    mime = probe.includes(0) ? 'application/octet-stream' : 'text/plain';
  }
  return {
    path: resolved,
    name: path.basename(resolved),
    size: info.size,
    mime,
    kind: previewKindFor(mime),
  };
}

// ==================== 文件上传（手机 → 电脑工作区） ====================

/** 上传上限：手机端传代码/文本/截图够用 */
export const UPLOAD_LIMIT_BYTES = 12 * 1024 * 1024;

/**
 * 往工作区写一个文件。
 * @param {{dir: string, name: string, base64: string, overwrite?: boolean}} input
 * @param {string[]} roots 允许的根
 */
export async function uploadFile({ dir, name, base64, overwrite = false }, roots) {
  const targetDir = assertAllowed(dir, roots);
  const dirInfo = await stat(targetDir);
  if (!dirInfo.isDirectory()) throw new FsAccessError('目标不是目录');

  const safeName = path.basename(String(name ?? '').trim());
  if (!safeName || safeName === '.' || safeName === '..') {
    throw new FsAccessError('文件名不合法');
  }
  if (typeof base64 !== 'string' || base64.length === 0) {
    throw new FsAccessError('没有文件内容');
  }
  const buffer = Buffer.from(base64, 'base64');
  if (buffer.length > UPLOAD_LIMIT_BYTES) {
    throw new FsAccessError(`文件超过上限 ${UPLOAD_LIMIT_BYTES / 1048576}MB`);
  }

  const target = path.join(targetDir, safeName);
  if (!overwrite && existsSync(target)) {
    throw new FsAccessError(`${safeName} 已存在（勾选覆盖才能替换）`);
  }
  await writeFile(target, buffer);
  return { path: target, name: safeName, size: buffer.length };
}

// ==================== git worktree ====================

/** 解析 `git worktree list --porcelain` */
function parseWorktrees(raw) {
  const items = [];
  let current = null;
  for (const line of raw.split('\n')) {
    if (line.startsWith('worktree ')) {
      if (current) items.push(current);
      current = { path: line.slice(9).trim(), branch: null, head: null, detached: false, bare: false };
    } else if (!current) {
      continue;
    } else if (line.startsWith('HEAD ')) {
      current.head = line.slice(5).trim();
    } else if (line.startsWith('branch ')) {
      current.branch = line.slice(7).trim().replace(/^refs\/heads\//, '');
    } else if (line.trim() === 'detached') {
      current.detached = true;
    } else if (line.trim() === 'bare') {
      current.bare = true;
    }
  }
  if (current) items.push(current);
  return items;
}

/** 列出仓库的所有 worktree（第一个是主工作树） */
export async function listWorktrees(cwd, roots) {
  const resolved = assertAllowed(cwd, roots);
  try {
    const raw = await git(resolved, ['worktree', 'list', '--porcelain']);
    const items = parseWorktrees(raw);
    const main = items[0]?.path ?? resolved;
    return {
      cwd: resolved,
      main,
      worktrees: items.map((item) => ({ ...item, isMain: item.path === main })),
      isRepo: true,
    };
  } catch (error) {
    return { cwd: resolved, main: resolved, worktrees: [], isRepo: false, error: String(error.message ?? error) };
  }
}

/**
 * 新建 worktree。
 * 默认「新建分支」：`git worktree add -b <branch> <path>`；
 * branch 为空则用 detached HEAD（看历史用）。
 */
export async function addWorktree({ cwd, dir, branch, base }, roots) {
  const resolved = assertAllowed(cwd, roots);
  const targetPath = assertAllowed(dir, roots);
  const trimmedBranch = String(branch ?? '').trim();
  const args = ['worktree', 'add'];
  if (trimmedBranch) args.push('-b', trimmedBranch);
  args.push(targetPath);
  if (base && String(base).trim()) args.push(String(base).trim());
  await git(resolved, args);
  return listWorktrees(resolved, roots);
}

/** 删除 worktree（默认不 force，有改动会拒绝 —— 让用户自己决定） */
export async function removeWorktree({ cwd, dir, force = false }, roots) {
  const resolved = assertAllowed(cwd, roots);
  const targetPath = assertAllowed(dir, roots);
  const args = ['worktree', 'remove'];
  if (force) args.push('--force');
  args.push(targetPath);
  await git(resolved, args);
  return listWorktrees(resolved, roots);
}
