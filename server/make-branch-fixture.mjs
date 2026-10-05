// 造一个「有分叉」的一次性会话，给 App 端的「切换分支（含摘要）」实测当靶子。
// 用法：node make-branch-fixture.mjs [cwd]
// 输出的 sessionId 就是靶子；测完用 DELETE /api/sessions/:id 删掉。

const base = process.env.PI_SERVER ?? 'http://127.0.0.1:30142';
const token = process.env.PI_TOKEN ?? 'pimobile2026';
const cwd = process.argv[2] ?? 'D:/powershell';

const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
const json = async (path, init) => (await fetch(base + path, { headers, ...init })).json();

const created = await json('/api/sessions', {
  method: 'POST',
  body: JSON.stringify({ cwd }),
});
const id = created.sessionId;
if (!id) throw new Error('建会话失败: ' + JSON.stringify(created));
console.log('靶子会话:', id, 'cwd:', created.cwd);

const cmd = (command) =>
  json(`/api/sessions/${id}/command`, { method: 'POST', body: JSON.stringify(command) });

async function waitIdle(label) {
  for (let i = 0; i < 240; i++) {
    const pool = await json('/api/pool');
    const me = pool.sessions?.find((s) => s.id === id);
    if (!me || !me.isStreaming) return;
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`${label}: 等回合结束超时`);
}

await cmd({ id: 'f1', type: 'prompt', message: 'Reply with exactly: alpha' });
await waitIdle('alpha');
await cmd({ id: 'f2', type: 'prompt', message: 'Reply with exactly: beta' });
await waitIdle('beta');

const tree = await cmd({ id: 'f3', type: 'get_tree' });
const count = (nodes) =>
  (nodes ?? []).reduce((n, node) => n + 1 + count(node.children), 0);
console.log('消息条数:', count(tree.data?.tree), '叶子:', tree.data?.leafId);
console.log('就绪：在 App 里打开它 → ⓘ 会话信息 → 分支树 → 点第一个节点 → 勾「顺手生成摘要」');
