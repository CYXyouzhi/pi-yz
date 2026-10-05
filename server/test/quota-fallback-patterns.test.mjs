// 额度兜底插件的匹配表验证（task-20 合同②）。
//
// 为什么要单独测：插件自己有一份匹配表，pi 内部还有一份；两边错开就会出现
// 「明明额度用尽，插件却没反应」。这轮的写法是**从插件源码里把表读出来**再测，
// 而不是在测试里另抄一份 —— 抄一份必然会漂移。
//
// 用例里的错误原文全部来自**真实会话记录**（~/.pi/agent/sessions 里搜出来的
// assistant stopReason=error 条目），不是编的。

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, '..', '..', 'pi-plugin', 'extensions', 'quota-fallback.ts');

function loadPatterns() {
  const text = readFileSync(SRC, 'utf-8');
  const block = text.match(/const DEFAULT_PATTERNS = \[([\s\S]*?)\];/);
  assert.ok(block, '插件里找不到 DEFAULT_PATTERNS');
  // 先剔掉注释行：注释里会举例子（例如 DeepSeek 的 402 报文），
  // 那里面也有带引号的词，会被当成关键字收进来
  const code = block[1]
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .join('\n');
  return [...code.matchAll(/"([^"]+)"/g)].map((m) => m[1]);
}

/** 与插件里 matchesQuota 同一套判定：小写包含 */
function matches(text, patterns) {
  const lower = String(text).toLowerCase();
  return patterns.find((p) => lower.includes(p.toLowerCase()));
}

const PATTERNS = loadPatterns();

test('匹配表非空且包含各家的已知关键字', () => {
  assert.ok(PATTERNS.length >= 8, `只有 ${PATTERNS.length} 条`);
  for (const must of ['GoUsageLimitError', 'insufficient_quota', 'quota exceeded']) {
    assert.ok(PATTERNS.includes(must), `缺 ${must}`);
  }
});

test('真实报错①：DeepSeek 官方余额不足（本轮新增的那条）', () => {
  // 原文取自会话记录：402: {"message":"Insufficient Balance", ...}
  const real =
    '402: {"message":"Insufficient Balance","type":"unknown_error","param":null,"code":"invalid_request_error"}';
  const hit = matches(real, PATTERNS);
  assert.equal(hit, 'insufficient balance', `没命中，实际命中 = ${hit}`);
});

test('真实报错②：请求体过大不应被当成额度问题', () => {
  // 原文：413 Failed to buffer the request body: length limit exceeded
  // 它有 "limit" 字样，但**不是额度**；误判会导致无缘无故切走 provider
  const real = '413 Failed to buffer the request body: length limit exceeded';
  assert.equal(matches(real, PATTERNS), undefined);
});

test('各家的额度类报错都能命中', () => {
  // 返回的是匹配表里的**原值**（插件拿它显示给用户），不是小写形式
  const cases = [
    ['GoUsageLimitError: monthly limit reached', 'GoUsageLimitError'],
    ["You've reached your monthly usage limit reached", 'usage limit reached'],
    ['openai: insufficient_quota', 'insufficient_quota'],
    ['API error: out of budget', 'out of budget'],
    ['quota exceeded for this project', 'quota exceeded'],
    ['subscription_sharing_usage_limit_exceeded', 'subscription_sharing_usage_limit_exceeded'],
    ['Your available balance is 0', 'available balance'],
  ];
  for (const [text, expect] of cases) {
    assert.equal(matches(text, PATTERNS), expect, text);
  }
});

test('普通报错不该被误判', () => {
  const cases = [
    'ENOENT: no such file or directory',
    'Connection refused (127.0.0.1:30142)',
    'TypeError: undefined is not a function',
    'Request timed out after 30000ms',
  ];
  for (const text of cases) {
    assert.equal(matches(text, PATTERNS), undefined, text);
  }
});
