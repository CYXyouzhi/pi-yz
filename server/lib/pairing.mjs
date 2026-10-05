// 配对窗口：手机拿 token 的正规入口。
//
// 设计取舍（这是安全边界，写清楚）：
//   · token 绝不放进广播 —— 广播是给整个局域网看的，等于公开；
//   · 配对码只在**用户显式打开窗口**后才存在，默认只开 5 分钟；
//   · 窗口一关，码立刻失效；配对成功后窗口立刻关闭（一次性）。
//
// 也就是说：攻击者要拿 token，必须在你按下「开启配对」的那几分钟里
// 同时待在同一个局域网里、并且知道那 6 位码（码只打印在你自己的终端上）。
//
// ## 为什么还要加限速
//
// 上面那段在「窗口 + 局域网 + 一次性」三条件下成立，但 **6 位数字只有 100 万种**，
// 而原先**没有任何失败计数**：局域网里发几百到几千 req/s，5 分钟足够覆盖
// 相当比例。补三层：
//
//   1. 单 IP 连续失败 MAX_FAILS_PER_IP 次 -> 该 IP 冷却 IP_COOLDOWN_MS（挡单机爆破）；
//   2. 全局失败 GLOBAL_FAIL_LIMIT 次 -> **立即关窗**。这条挡的是换 IP 的分布式爆破：
//      窗口都没了，再多 IP 也没用，只能等你重新开；
//   3. 冷却期内**不比较配对码、直接拒绝** —— 免得把「比较耗时」本身变成旁路信道。
//
// 阈值全部是导出常量，且所有时间相关函数都接受注入的 `now`，
// 于是测试可以做时间旅行，不用真的 sleep 60 秒。

import { randomInt } from 'node:crypto';

const DEFAULT_WINDOW_MS = 5 * 60 * 1000;

/** 单 IP 连续失败上限，达到就进冷却 */
export const MAX_FAILS_PER_IP = 5;
/** 单 IP 冷却时长 */
export const IP_COOLDOWN_MS = 60 * 1000;
/** 全局失败上限：达到立即关窗（换 IP 也没用） */
export const GLOBAL_FAIL_LIMIT = 20;

let current = null; // { code, expiresAt, windowMs }

/** ip -> { count, cooldownUntil } */
const failsByIp = new Map();
/** 当前窗口内累计失败次数（跨 IP） */
let globalFails = 0;

function makeCode() {
  // 6 位数字：够短好念。配合「窗口 + 局域网 + 一次性 + 限速」四个条件够用。
  return String(randomInt(0, 1_000_000)).padStart(6, '0');
}

function resetFailures() {
  failsByIp.clear();
  globalFails = 0;
}

/** 开一个配对窗口（已经开着就续期，码不变——避免用户刚看到码就被换掉） */
export function openPairingWindow(windowMs = DEFAULT_WINDOW_MS, now = Date.now()) {
  if (current && current.expiresAt > now) {
    current.expiresAt = now + windowMs;
    return current;
  }
  current = { code: makeCode(), expiresAt: now + windowMs, windowMs };
  // 新窗口 = 新计数：上一个窗口的失败不该罚到这一个
  resetFailures();
  return current;
}

/** 关掉窗口（配对成功、超限、或用户主动关闭） */
export function closePairingWindow() {
  current = null;
  resetFailures();
}

/** 当前窗口状态（给广播与设置页看） */
export function pairingState(now = Date.now()) {
  if (!current || current.expiresAt <= now) {
    current = null;
    return { open: false };
  }
  return {
    open: true,
    code: current.code,
    expiresAt: current.expiresAt,
    secondsLeft: Math.max(0, Math.round((current.expiresAt - now) / 1000)),
  };
}

export function isPairingOpen(now = Date.now()) {
  return pairingState(now).open;
}

/**
 * 清掉冷却已结束的记录。
 *
 * 不会无限增长：能撑到 Map 变大的是「很多不同 IP」，而那种情况下
 * globalFails 会先撞到 GLOBAL_FAIL_LIMIT 并关窗 + 清空。
 * 所以这里只是把「零散试过一两次、已经过了冷却」的条目扫掉。
 */
function pruneFails(now) {
  for (const [ip, rec] of failsByIp) {
    if (rec.cooldownUntil > 0 && rec.cooldownUntil <= now) failsByIp.delete(ip);
  }
}

/**
 * 记一次失败。
 * @returns {boolean} 是否因为全局超限而**关闭了窗口**
 */
function recordFail(ip, now) {
  const rec = failsByIp.get(ip) ?? { count: 0, cooldownUntil: 0 };
  rec.count += 1;
  if (rec.count >= MAX_FAILS_PER_IP) {
    rec.cooldownUntil = now + IP_COOLDOWN_MS;
  }
  failsByIp.set(ip, rec);

  globalFails += 1;
  if (globalFails >= GLOBAL_FAIL_LIMIT) {
    // 注意顺序：先把「窗口已关闭」这个事实定下来，再重置计数
    current = null;
    resetFailures();
    return true;
  }
  return false;
}

/**
 * 校验配对码。成功即关闭窗口（一次性）。
 *
 * @param {string} code     用户填的 6 位码
 * @param {string} clientIp 请求来源 IP（限速用）
 * @param {number} now      时间戳（测试注入；生产用 Date.now()）
 * @returns {{ok: true} | {ok: false, reason: string, retryAfterMs?: number}}
 */
export function verifyPairingCode(code, clientIp = 'unknown', now = Date.now()) {
  pruneFails(now);

  // ---- 1) 该 IP 在冷却中：不比较码，直接拒 ----
  const rec = failsByIp.get(clientIp);
  if (rec && rec.cooldownUntil > now) {
    const waitMs = rec.cooldownUntil - now;
    return {
      ok: false,
      reason: `尝试过于频繁，请 ${Math.ceil(waitMs / 1000)} 秒后再试`,
      retryAfterMs: waitMs,
    };
  }

  // ---- 2) 窗口开着吗 ----
  const state = pairingState(now);
  if (!state.open) {
    // 窗口没开不算「失败」：那是用户操作顺序问题，不该罚他、也不该计入限速
    return {
      ok: false,
      reason: '配对窗口没开（在电脑端执行 pi-mobile server pair，或重启服务端会自动开 5 分钟）',
    };
  }

  // ---- 3) 常量时间比较 ----
  const given = String(code ?? '').trim();
  const mismatch = () => {
    const closed = recordFail(clientIp, now);
    return {
      ok: false,
      reason: closed
        ? '配对尝试次数过多，窗口已关闭。请在电脑端重新开启配对'
        : '配对码不对',
    };
  };
  if (!given) return mismatch();
  if (given.length !== state.code.length) return mismatch();
  let diff = 0;
  for (let i = 0; i < state.code.length; i += 1) {
    diff |= given.charCodeAt(i) ^ state.code.charCodeAt(i);
  }
  if (diff !== 0) return mismatch();

  closePairingWindow();
  return { ok: true };
}
