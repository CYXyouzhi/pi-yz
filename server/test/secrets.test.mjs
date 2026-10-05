// 脱敏函数的确定性验证（task-16 合同③④）。
//
// 为什么值得单测：这类函数写错了不会报错，只会**静默泄漏** ——
// 日志看起来很正常，密钥已经在里面了。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { maskSecret, redact } from '../lib/secrets.mjs';

test('短串一律全遮（露头露尾等于全给）', () => {
  assert.equal(maskSecret('abc'), '***');
  assert.equal(maskSecret('abcdef'), '******');
  assert.equal(maskSecret(''), '(空)');
  assert.equal(maskSecret(null), '(空)');
});

test('长串只留前 4 后 2，并标出原长度', () => {
  const out = maskSecret('pimobile2026secretvalue');
  assert.ok(out.startsWith('pimo'), out);
  assert.ok(out.endsWith('ue（23 位，已脱敏）'), out);
  assert.ok(!out.includes('bile2026'), '中间那截不能出现');
});

test('原串本身不出现在结果里', () => {
  const secret = 'sk-abcdefghijklmnopqrstuvwxyz0123456789';
  assert.ok(!maskSecret(secret).includes(secret));
});

test('redact 能把整段文本里的密钥换掉', () => {
  const secret = 'pimobile2026';
  const text = `GET /api/health?token=${secret} 与再次出现 ${secret} 都换掉`;
  const out = redact(text, [secret]);
  assert.ok(!out.includes(secret), out);
  assert.equal(out.split('已脱敏').length - 1, 2, out);
});

test('redact 不动太短的串（避免把正常文字打碎）', () => {
  const text = 'token=abc 这种三字母不当密钥处理';
  assert.equal(redact(text, ['abc']), text);
});
