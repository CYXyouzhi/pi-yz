// 本轮改动速览：数一数「这一轮改了哪些文件、各增删多少行」。
//
// 数据来源：会话 JSONL 里的工具调用（原始记录，不猜）。
//
// 口径（返回值里也带着 basis 字段，App 直接显示这句话）：
//   · 只算 edit / write 两个工具
//   · edit：删行 = oldText 的行数，增行 = newText 的行数（一次调用可能有多个 edits）
//   · write：增行 = content 的行数，删行记 0（要算删除得先有原文件内容，这里不猜）
//   · bash 里用 sed / python 改的文件**算不出来**，明确不计入 —— 宁可少算，不编数据

import { readFileSync } from 'node:fs';

import { resolveSessionPath } from './sessions.mjs';

const BASIS = '统计口径：只算 edit / write 工具；bash 里的文件改写不计入';

function countLines(text) {
  const value = String(text ?? '');
  if (value === '') return 0;
  // 末尾换行不算多一行（编辑器的常识）
  const lines = value.split('\n');
  return value.endsWith('\n') ? lines.length - 1 : lines.length;
}

/** 末尾那段「最后一条用户消息之后」的所有消息算作一轮 */
function lastTurnStart(messages) {
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index];
    if (message?.message?.role === 'user') return index;
  }
  return 0;
}

export function turnSummaryFromLines(lines) {
  const messages = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed === '') continue;
    try {
      messages.push(JSON.parse(trimmed));
    } catch {
      // 半截行（正在写）跳过
    }
  }

  const start = lastTurnStart(messages);
  const turn = messages.slice(start);
  const files = new Map();
  let toolCalls = 0;

  for (const entry of turn) {
    const message = entry?.message;
    if (!message) continue;
    const blocks = Array.isArray(message.content) ? message.content : [];
    for (const block of blocks) {
      if (block?.type !== 'toolCall') continue;
      const name = block.name;
      if (name !== 'edit' && name !== 'write') continue;
      toolCalls += 1;
      const args = block.arguments ?? {};
      const path = String(args.path ?? '（未给路径）');
      const item = files.get(path) ?? { path, added: 0, removed: 0, edits: 0, writes: 0 };
      if (name === 'write') {
        item.added += countLines(args.content);
        item.writes += 1;
      } else {
        const edits = Array.isArray(args.edits) ? args.edits : [];
        item.edits += edits.length;
        for (const edit of edits) {
          item.removed += countLines(edit?.oldText);
          item.added += countLines(edit?.newText);
        }
      }
      files.set(path, item);
    }
  }

  const list = [...files.values()].sort(
    (a, b) => b.added + b.removed - (a.added + a.removed),
  );

  return {
    files: list,
    totals: {
      files: list.length,
      added: list.reduce((sum, item) => sum + item.added, 0),
      removed: list.reduce((sum, item) => sum + item.removed, 0),
      toolCalls,
    },
    startedAt: turn[0]?.timestamp ?? null,
    endedAt: turn[turn.length - 1]?.timestamp ?? null,
    messageCount: turn.length,
    basis: BASIS,
  };
}

/** 会话 id 版：内部自己把 id 解析成 JSONL 路径 */
export async function turnSummaryForSession(sessionId) {
  const path = await resolveSessionPath(sessionId);
  return turnSummary(path);
}

export function turnSummary(sessionPath) {
  let lines;
  try {
    lines = readFileSync(sessionPath, 'utf8').split('\n');
  } catch (error) {
    if (error?.code === 'ENOENT') return null;
    throw error;
  }
  return turnSummaryFromLines(lines);
}
