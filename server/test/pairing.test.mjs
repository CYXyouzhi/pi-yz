// 配对限速的单元测试。
//
// 为什么值得单独测：这是安全边界，而安全逻辑最容易「看起来对」——
// 比如「冷却期间连正确码也拒」这条，顺手写成「冷却期间先比较码再判冷却」
// 就退化成了一个可用的旁路信道，而肉眼看代码很难发现。
//
// 时间全部用注入的 `now`，所以毫秒内就能验证 60 秒冷却、5 分钟窗口这些事，
// 不需要真的 sleep。

import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  openPairingWindow,
  closePairingWindow,
  pairingState,
  verifyPairingCode,
  MAX_FAILS_PER_IP,
  IP_COOLDOWN_MS,
  GLOBAL_FAIL_LIMIT,
} from '../lib/pairing.mjs';

const T0 = 1_700_000_000_000;
const WRONG = '000000';

beforeEach(() => closePairingWindow());

/** 造一个与正确码不同的 6 位码 */
function wrongFor(code) {
  const alt = String((Number(code) + 1) % 1_000_000).padStart(6, '0');
  return alt === code ? WRONG : alt;
}

test('正确配对码：通过，且窗口立刻关闭（一次性）', () => {
  const { code } = openPairingWindow(undefined, T0);
  const r = verifyPairingCode(code, '10.0.0.1', T0);
  assert.equal(r.ok, true);
  assert.equal(pairingState(T0 + 1).open, false, '成功后窗口必须关闭');
});

test('错误配对码：拒绝，但窗口仍开着（真用户还要重试）', () => {
  const { code } = openPairingWindow(undefined, T0);
  const r = verifyPairingCode(wrongFor(code), '10.0.0.1', T0);
  assert.equal(r.ok, false);
  assert.match(r.reason, /配对码不对/);
  assert.equal(pairingState(T0 + 1).open, true, '错一次不该关窗');
});

test('同一个 IP 连错到上限后冷却：此后连正确码也拒', () => {
  const { code } = openPairingWindow(undefined, T0);
  for (let i = 0; i < MAX_FAILS_PER_IP; i += 1) {
    verifyPairingCode(WRONG, '10.0.0.9', T0 + i);
  }
  const r = verifyPairingCode(code, '10.0.0.9', T0 + 10);
  assert.equal(r.ok, false, '冷却中即使是正确码也必须拒（否则比较耗时成为旁路）');
  assert.ok(r.retryAfterMs > 0, '要告诉客户端还要等多久');
  assert.match(r.reason, /过于频繁/);
});

test('冷却结束后可以重新尝试', () => {
  const { code } = openPairingWindow(undefined, T0);
  for (let i = 0; i < MAX_FAILS_PER_IP; i += 1) {
    verifyPairingCode(WRONG, '10.0.0.9', T0 + i);
  }
  assert.equal(verifyPairingCode(code, '10.0.0.9', T0 + 10).ok, false);
  // 时间旅行：冷却 60 秒，窗口 5 分钟 —— 冷却是先到的那个
  const after = verifyPairingCode(code, '10.0.0.9', T0 + IP_COOLDOWN_MS + 100);
  assert.equal(after.ok, true, '冷却结束后正确码应当通过（窗口还在）');
});

test('一个 IP 被冷却不影响另一个 IP', () => {
  const { code } = openPairingWindow(undefined, T0);
  for (let i = 0; i < MAX_FAILS_PER_IP; i += 1) {
    verifyPairingCode(WRONG, '10.0.0.9', T0 + i);
  }
  const other = verifyPairingCode(code, '10.0.0.8', T0 + 10);
  assert.equal(other.ok, true, '限速按 IP 隔离，不能连坐');
});

test('全局失败达上限：立即关窗，换 IP 也没用', () => {
  openPairingWindow(undefined, T0);
  let last;
  // 用很多不同 IP 各错一次 —— 单 IP 都没到上限，靠全局计数兜住
  for (let i = 0; i < GLOBAL_FAIL_LIMIT; i += 1) {
    last = verifyPairingCode(WRONG, `10.0.1.${i}`, T0 + i);
  }
  assert.equal(last.ok, false);
  assert.match(last.reason, /窗口已关闭/, '第 N 次失败要明确告知窗口没了');
  assert.equal(pairingState(T0 + 1000).open, false, '窗口必须真的关掉');
});

test('窗口没开时的失败：不算数、不计入限速', () => {
  for (let i = 0; i < GLOBAL_FAIL_LIMIT + 10; i += 1) {
    const r = verifyPairingCode(WRONG, '10.0.0.5', T0 + i);
    assert.equal(r.ok, false);
  }
  // 现在开窗，用这个「已被试了几十次」的 IP 填正确码 —— 应当通过
  const { code } = openPairingWindow(undefined, T0 + 1000);
  const r = verifyPairingCode(code, '10.0.0.5', T0 + 1001);
  assert.equal(r.ok, true, '窗口外的操作不该罚到窗口内');
});

test('新窗口重置失败计数', () => {
  openPairingWindow(undefined, T0);
  for (let i = 0; i < MAX_FAILS_PER_IP; i += 1) {
    verifyPairingCode(WRONG, '10.0.0.7', T0 + i);
  }
  closePairingWindow();
  const second = openPairingWindow(undefined, T0 + 200);
  const r = verifyPairingCode(second.code, '10.0.0.7', T0 + 201);
  assert.equal(r.ok, true, '新窗口是干净的');
});

test('窗口过期后校验：提示「窗口没开」而不是「码不对」', () => {
  const { code } = openPairingWindow(1000, T0); // 只开 1 秒
  const r = verifyPairingCode(code, '10.0.0.1', T0 + 2000);
  assert.equal(r.ok, false);
  assert.match(r.reason, /配对窗口没开/);
});

test('空码不崩，按错误处理', () => {
  openPairingWindow(undefined, T0);
  for (const bad of ['', '   ', null, undefined]) {
    const r = verifyPairingCode(bad, '10.0.0.1', T0);
    assert.equal(r.ok, false);
  }
});
