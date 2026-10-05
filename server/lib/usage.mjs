// 用量统计：全部从**落盘的会话 JSONL** 里算，不猜、不估。
//
// 为什么放在服务端：
//   · 时间戳与 usage 都在会话文件里（App 只拿到快照的一部分）；
//   · 「今天 / 本月花了多少」需要跨 200+ 个会话文件聚合，手机端扫不动。
//
// 口径（写清楚，免得数字对不上）：
//   · tokens/s = 该轮 output ÷ 该轮耗时；耗时 = 本轮 assistant 条目时间戳 − 上一条目时间戳
//     （近似模型调用耗时，含首字节等待）
//   · 缓存命中率 = cacheRead ÷ (input + cacheRead)
//   · 花费直接用 pi 记在 usage.cost.total 的数（不是我们按价目表算的）

import { readFile } from 'node:fs/promises';
import { listSessions, resolveSessionPath } from './sessions.mjs';

const DAY = 24 * 60 * 60 * 1000;

function num(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function usageOf(message) {
  const usage = message?.usage;
  if (!usage || typeof usage !== 'object') return null;
  return {
    input: num(usage.input),
    output: num(usage.output),
    cacheRead: num(usage.cacheRead),
    cacheWrite: num(usage.cacheWrite),
    reasoning: num(usage.reasoning),
    totalTokens: num(usage.totalTokens),
    cost: num(usage.cost?.total),
  };
}

async function readEntries(sessionId) {
  const path = await resolveSessionPath(sessionId);
  const raw = await readFile(path, 'utf8');
  const entries = [];
  for (const line of raw.split('\n')) {
    if (!line.trim()) continue;
    try {
      entries.push(JSON.parse(line));
    } catch {
      // 坏行跳过：一个会话里有一条坏行不该让整个统计失败
    }
  }
  return entries;
}

/** 单条会话的逐轮明细 + 汇总 */
export async function sessionUsage(sessionId) {
  const entries = await readEntries(sessionId);
  const turns = [];
  let previousTimestamp = null;
  let lastUserTimestamp = null;
  const totals = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0, cost: 0, turns: 0 };

  for (const entry of entries) {
    const message = entry?.message;
    if (!message || typeof message !== 'object') continue;
    const timestamp = entry.timestamp ?? null;

    if (message.role === 'user') {
      lastUserTimestamp = timestamp;
      previousTimestamp = timestamp ?? previousTimestamp;
      continue;
    }

    if (message.role === 'assistant') {
      const usage = usageOf(message);
      const startedAt = previousTimestamp ?? lastUserTimestamp ?? timestamp;
      const durationMs =
        startedAt && timestamp ? Math.max(0, Date.parse(timestamp) - Date.parse(startedAt)) : null;
      const output = usage?.output ?? 0;
      const cacheRead = usage?.cacheRead ?? 0;
      const input = usage?.input ?? 0;
      turns.push({
        index: turns.length + 1,
        at: timestamp,
        provider: message.provider ?? null,
        model: message.model ?? null,
        stopReason: message.stopReason ?? null,
        input: usage?.input ?? null,
        output: usage?.output ?? null,
        cacheRead: usage?.cacheRead ?? null,
        cacheWrite: usage?.cacheWrite ?? null,
        reasoning: usage?.reasoning ?? null,
        totalTokens: usage?.totalTokens ?? null,
        cost: usage?.cost ?? null,
        durationMs,
        tokensPerSec: durationMs && durationMs > 0 ? Math.round((output / durationMs) * 1000 * 10) / 10 : null,
        cacheHitRate: input + cacheRead > 0 ? Math.round((cacheRead / (input + cacheRead)) * 1000) / 10 : null,
      });
      if (usage) {
        totals.input += usage.input ?? 0;
        totals.output += usage.output ?? 0;
        totals.cacheRead += usage.cacheRead ?? 0;
        totals.cacheWrite += usage.cacheWrite ?? 0;
        totals.reasoning += usage.reasoning ?? 0;
        totals.cost += usage.cost ?? 0;
        totals.turns += 1;
      }
      previousTimestamp = timestamp ?? previousTimestamp;
      continue;
    }

    previousTimestamp = timestamp ?? previousTimestamp;
  }

  const lastTurn = [...turns].reverse().find((turn) => turn.output !== null) ?? null;
  return {
    sessionId,
    turns,
    totals: {
      ...totals,
      cost: Math.round(totals.cost * 1e6) / 1e6,
      cacheHitRate:
        totals.input + totals.cacheRead > 0
          ? Math.round((totals.cacheRead / (totals.input + totals.cacheRead)) * 1000) / 10
          : null,
      tokensPerSec:
        turns.length > 0
          ? (() => {
              const withTime = turns.filter((t) => t.durationMs && t.output);
              const ms = withTime.reduce((sum, t) => sum + t.durationMs, 0);
              const out = withTime.reduce((sum, t) => sum + t.output, 0);
              return ms > 0 ? Math.round((out / ms) * 1000 * 10) / 10 : null;
            })()
          : null,
    },
    lastTurn,
  };
}

/**
 * 跨会话聚合：今天 / 本月 / 按天 / 按 provider。
 *
 * 只扫最近 45 天内改动过的会话文件 —— 「本月」够用，扫 200+ 个几十 MB 的文件太慢。
 */
export async function usageSummary({ days = 45 } = {}) {
  const { sessions } = await listSessions();
  const since = Date.now() - days * DAY;
  const byDay = new Map();
  const byProvider = new Map();
  const byWorkspace = new Map();
  const totals = { today: { tokens: 0, cost: 0 }, month: { tokens: 0, cost: 0 } };
  const now = new Date();
  const monthPrefix = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  const todayPrefix = new Date().toISOString().slice(0, 10);
  let scanned = 0;

  for (const info of sessions) {
    const modified = info.modified ? Date.parse(info.modified) : null;
    if (modified && modified < since) continue;
    let entries;
    try {
      entries = await readEntries(info.id);
    } catch {
      continue;
    }
    scanned += 1;
    // 每条会话只给它的工作区计一次数（turns 才按轮累加）
    const workspaceSeen = new Set();
    for (const entry of entries) {
      const message = entry?.message;
      if (!message || message.role !== 'assistant') continue;
      const usage = usageOf(message);
      if (!usage) continue;
      const at = entry.timestamp ?? null;
      if (!at) continue;
      const day = at.slice(0, 10);
      const tokens = (usage.input ?? 0) + (usage.output ?? 0) + (usage.cacheRead ?? 0) + (usage.cacheWrite ?? 0);
      const cost = usage.cost ?? 0;

      const dayRow = byDay.get(day) ?? { day, tokens: 0, cost: 0 };
      dayRow.tokens += tokens;
      dayRow.cost += cost;
      byDay.set(day, dayRow);

      // 按工作区：同一台电脑上不同项目的花费能分开看（task-16 合同①）
      const cwd = info.cwd ?? '';
      const wsRow = byWorkspace.get(cwd) ?? { cwd, tokens: 0, cost: 0, turns: 0, sessions: 0 };
      wsRow.tokens += tokens;
      wsRow.cost += cost;
      wsRow.turns += 1;
      byWorkspace.set(cwd, wsRow);
      if (!workspaceSeen.has(cwd)) {
        workspaceSeen.add(cwd);
        wsRow.sessions += 1;
      }

      const provider = message.provider ?? 'unknown';
      const providerRow = byProvider.get(provider) ?? { provider, tokens: 0, cost: 0, turns: 0 };
      providerRow.tokens += tokens;
      providerRow.cost += cost;
      providerRow.turns += 1;
      byProvider.set(provider, providerRow);

      if (day === todayPrefix) {
        totals.today.tokens += tokens;
        totals.today.cost += cost;
      }
      if (day.startsWith(monthPrefix)) {
        totals.month.tokens += tokens;
        totals.month.cost += cost;
      }
    }
  }

  return {
    scannedSessions: scanned,
    today: { tokens: totals.today.tokens, cost: Math.round(totals.today.cost * 1e6) / 1e6 },
    month: { tokens: totals.month.tokens, cost: Math.round(totals.month.cost * 1e6) / 1e6 },
    byDay: [...byDay.values()].sort((a, b) => (a.day < b.day ? 1 : -1)),
    byProvider: [...byProvider.values()].sort((a, b) => b.tokens - a.tokens),
    byWorkspace: [...byWorkspace.values()].sort((a, b) => b.tokens - a.tokens),
    generatedAt: new Date().toISOString(),
  };
}
