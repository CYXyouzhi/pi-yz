// 敏感信息脱敏（task-16 合同③④）。
//
// 为什么单独一个文件、还要有测试：这类函数一旦写错，泄漏是**静默**的 ——
// 日志看起来正常，密钥却已经在里面了。所以它必须能被单测钉死。
//
// 规则：
//   · 长度 ≤ 6 一律全遮（短串露头露尾就等于全给了）
//   · 否则留前 4 后 2，中间省略号，并标出原长度（方便排查「是不是截断了」）

export function maskSecret(value) {
  const s = value == null ? '' : String(value);
  if (s.length === 0) return '(空)';
  if (s.length <= 6) return '*'.repeat(s.length);
  return `${s.slice(0, 4)}…${s.slice(-2)}（${s.length} 位，已脱敏）`;
}

/**
 * 把一段文本里出现过的敏感串换掉。
 * 日志/报错里最危险的是「把整条请求或整个对象 stringify 出来」，
 * 那种地方用它兜一道。
 */
export function redact(text, secrets = []) {
  let out = String(text ?? '');
  for (const secret of secrets) {
    const s = String(secret ?? '');
    if (s.length < 4) continue;
    while (out.includes(s)) out = out.split(s).join(maskSecret(s));
  }
  return out;
}
