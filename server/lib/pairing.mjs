// 配对窗口：手机拿 token 的正规入口。
//
// 设计取舍（这是安全边界，写清楚）：
//   · token 绝不放进广播 —— 广播是给整个局域网看的，等于公开；
//   · 配对码只在**用户显式打开窗口**后才存在，默认只开 5 分钟；
//   · 窗口一关，码立刻失效；配对成功后窗口立刻关闭（一次性）。
//
// 也就是说：攻击者要拿 token，必须在你按下「开启配对」的那几分钟里
// 同时待在同一个局域网里、并且知道那 6 位码（码只打印在你自己的终端上）。

import { randomInt } from 'node:crypto';

const DEFAULT_WINDOW_MS = 5 * 60 * 1000;

let current = null; // { code, expiresAt, windowMs }

function makeCode() {
  // 6 位数字：够短好念，配合「窗口 + 局域网 + 一次性」三条件够用。
  return String(randomInt(0, 1_000_000)).padStart(6, '0');
}

/** 开一个配对窗口（已经开着就续期，码不变——避免用户刚看到码就被换掉） */
export function openPairingWindow(windowMs = DEFAULT_WINDOW_MS) {
  if (current && current.expiresAt > Date.now()) {
    current.expiresAt = Date.now() + windowMs;
    return current;
  }
  current = { code: makeCode(), expiresAt: Date.now() + windowMs, windowMs };
  return current;
}

/** 关掉窗口（配对成功或用户主动关闭） */
export function closePairingWindow() {
  current = null;
}

/** 当前窗口状态（给广播与设置页看） */
export function pairingState() {
  if (!current || current.expiresAt <= Date.now()) {
    current = null;
    return { open: false };
  }
  return {
    open: true,
    code: current.code,
    expiresAt: current.expiresAt,
    secondsLeft: Math.max(0, Math.round((current.expiresAt - Date.now()) / 1000)),
  };
}

export function isPairingOpen() {
  return pairingState().open;
}

/**
 * 校验配对码。成功即关闭窗口（一次性）。
 * @returns {{ok: true} | {ok: false, reason: string}}
 */
export function verifyPairingCode(code) {
  const given = String(code ?? '').trim();
  if (!given) return { ok: false, reason: '请填写配对码' };
  const state = pairingState();
  if (!state.open) {
    return {
      ok: false,
      reason: '配对窗口没开（在电脑端执行 pi-mobile server pair，或重启服务端会自动开 5 分钟）',
    };
  }
  // 常量时间比较，避免按位试探
  if (given.length !== state.code.length) return { ok: false, reason: '配对码不对' };
  let diff = 0;
  for (let i = 0; i < state.code.length; i += 1) {
    diff |= given.charCodeAt(i) ^ state.code.charCodeAt(i);
  }
  if (diff !== 0) return { ok: false, reason: '配对码不对' };

  closePairingWindow();
  return { ok: true };
}
