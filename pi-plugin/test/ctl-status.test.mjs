// ctl.mjs 状态机测试
//
// 背景（真实踩过的坑）：原来的 status() 用 alive(pid) 判断「服务在不在跑」。
// 结果 pid 文件里记着一个早就死掉的号时，/yz start 会认为「已经在跑」，
// 直接返回、什么都不做 —— 用户以为起了，手机连上却是连接被拒绝。
//
// 这里把状态判断的四条分支钉死，防止再退化回去。

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// 必须在 import ctl 之前设好 —— 它是模块级读取环境变量
const sandbox = mkdtempSync(join(tmpdir(), 'pi-ctl-test-'));
process.env.PI_YZ_CONFIG_PATH = join(sandbox, 'config.json');
process.env.PI_YZ_STATE_PATH = join(sandbox, 'state.pid');
process.env.PI_YZ_LOG_PATH = join(sandbox, 'server.log');

const ctl = await import('../lib/ctl.mjs');

const HTTP_PORT = 31771;      // 假服务端监听的端口（故意选个不常用的）
let fakeServer = null;        // 一个真在监听的 HTTP 服务，用来制造 "foreign"
let orphan = null;            // 一个活着但不监听的进程，用来制造 "zombie"

/** 起一个只会应答 /api/health 的假服务端 */
function startFakeServer(port) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      ['-e', `
        require('http').createServer((req, res) => {
          if (req.url === '/api/health') { res.writeHead(200, {'content-type':'application/json'}); res.end('{"ok":true}'); return; }
          res.writeHead(404); res.end();
        }).listen(${port}, '127.0.0.1');
      `],
      { stdio: 'ignore', windowsHide: true },
    );
    // 给 listen 一点时间
    setTimeout(() => resolve(child), 900);
    child.on('error', reject);
  });
}

before(async () => {
  fakeServer = await startFakeServer(HTTP_PORT);
  // 一个只是活着、什么都不做的进程 —— 模拟「进程在但端口没服务」的僵死态
  orphan = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 60000)'], {
    stdio: 'ignore',
    windowsHide: true,
  });
  await new Promise((r) => setTimeout(r, 500));
});

after(() => {
  for (const child of [fakeServer, orphan]) {
    try { child?.kill(); } catch { /* 已经退了 */ }
  }
  try { rmSync(sandbox, { recursive: true, force: true }); } catch { /* 沙箱清理失败不影响结论 */ }
});

function writeState(next) {
  writeFileSync(process.env.PI_YZ_STATE_PATH, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
}

function writeConfig(next) {
  writeFileSync(process.env.PI_YZ_CONFIG_PATH, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
}

test('down：进程没了、端口也没人应 —— 顺手清掉陈旧 pid 文件', async () => {
  writeConfig({ port: HTTP_PORT + 100, token: 'x' });   // 一个绝对没服务的端口
  writeState({ pid: 999999, port: HTTP_PORT + 100, host: '0.0.0.0', startedAt: '2026-01-01T00:00:00.000Z' });

  const info = await ctl.resolveStatus();
  assert.equal(info.kind, 'down');
  assert.equal(info.serving, false);
  // 关键：陈旧的 pid 文件必须被清掉，否则 /yz stop 会对着空气挥刀
  assert.equal(existsSync(process.env.PI_YZ_STATE_PATH), false, '陈旧 pid 文件应被删除');
});

test('foreign：端口有人应，但不是我们的 pid —— 如实识别，不当成自己起的', async () => {
  writeConfig({ port: HTTP_PORT, token: 'x' });
  writeState({ pid: 999999, port: HTTP_PORT, host: '0.0.0.0', startedAt: '2026-01-01T00:00:00.000Z' });

  const info = await ctl.resolveStatus();
  assert.equal(info.kind, 'foreign', '端口上有服务但 pid 对不上，应识别为 foreign');
  assert.equal(info.serving, true);
  assert.equal(info.pidAlive, false);
});

test('foreign：start() 不重复拉起，并给出人话说明', async () => {
  writeConfig({ port: HTTP_PORT, token: 'x' });
  writeState({ pid: 999999, port: HTTP_PORT, host: '0.0.0.0', startedAt: '2026-01-01T00:00:00.000Z' });
  const pidFileBefore = readFileSync(process.env.PI_YZ_STATE_PATH, 'utf8');

  const result = await ctl.start();
  assert.equal(result.alreadyRunning, true, '不该重复拉起');
  assert.equal(result.foreign, true);
  assert.match(String(result.hint), /不是本插件拉起/);
  // 旧实现到这步会「认为已在跑」直接 return，而它认为的依据是不可靠的 pid
  assert.equal(
    readFileSync(process.env.PI_YZ_STATE_PATH, 'utf8'),
    pidFileBefore,
    '不该动 pid 文件',
  );
});

test('foreign：stop() 不乱杀别人的服务', async () => {
  writeConfig({ port: HTTP_PORT, token: 'x' });
  writeState({ pid: 999999, port: HTTP_PORT, host: '0.0.0.0', startedAt: '2026-01-01T00:00:00.000Z' });

  const result = await ctl.stop();
  assert.equal(result.stopped, false);
  assert.match(String(result.reason), /不归 \/yz 管/);
});

test('zombie：进程活着但端口没服务 —— 识别出来，不当成健康', async () => {
  const deadPort = HTTP_PORT + 200;   // 没人监听
  writeConfig({ port: deadPort, token: 'x' });
  writeState({ pid: orphan.pid, port: deadPort, host: '0.0.0.0', startedAt: '2026-01-01T00:00:00.000Z' });

  const info = await ctl.resolveStatus();
  assert.equal(info.kind, 'zombie', '进程在但端口没服务，应识别为 zombie');
  assert.equal(info.pidAlive, true);
  assert.equal(info.serving, false);
});

test('status() 仍是同步的（向后兼容），但不再是权威判断', () => {
  writeConfig({ port: HTTP_PORT, token: 'x' });
  writeState({ pid: orphan.pid, port: HTTP_PORT, host: '0.0.0.0', startedAt: '2026-01-01T00:00:00.000Z' });

  const sync = ctl.status();
  assert.equal(sync.port, HTTP_PORT);
  assert.equal(sync.pid, orphan.pid);
  assert.equal(typeof sync.running, 'boolean');
});

test('readConfig/writeConfig 往返', () => {
  ctl.writeConfig({ port: 12345, token: 'abc' });
  assert.deepEqual(ctl.readConfig(), { port: 12345, token: 'abc' });
});
