// 远程访问隧道（task-18）。
//
// 定位：让手机在**不在同一局域网**时也能连上这台电脑。
//
// 两条路都实现了，按可用性自动挑：
//   1. **Cloudflare quick tunnel**（首选）：需要 `server/bin/cloudflared[.exe]`。
//      实测在国内可达（DNS / QUIC / HTTP2 / Cloudflare API 四项 precheck 全过，
//      隧道 1.5 秒内响应），地址形如 https://xxx.trycloudflare.com。
//   2. **SSH 反向隧道（localhost.run）**：`ssh` 是系统自带，零安装。
//      但实测它的 *.lhr.life 在国内**不可达**（curl 21 秒超时，HTTP 000），
//      所以只当兜底 —— 网络能通的环境下依然可用。
//
// 代价（必须对用户说清楚）：
//   · 免费隧道不承诺 SLA，断了要重开（界面会如实报「隧道断开」）；
//   · 流量经过第三方（Cloudflare 或 localhost.run），所以**鉴权仍然必须做**
//     （服务端 token；实测不带 token 一律 401）；
//   · 延迟比局域网高（Cloudflare 走洛杉矶边缘，实测 +0.5~1.5 秒）。

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SSH_PROVIDER = 'localhost.run';
let provider = SSH_PROVIDER;

/** 找 cloudflared：先看项目自带的 bin/，再看 PATH */
export function cloudflaredPath() {
  const name = process.platform === 'win32' ? 'cloudflared.exe' : 'cloudflared';
  const local = join(HERE, '..', 'bin', name);
  if (existsSync(local)) return local;
  return name; // 交给 PATH
}

export function hasCloudflared() {
  const p = cloudflaredPath();
  return p === 'cloudflared' ? true : existsSync(p);
}

/** idle | starting | up | error | stopped */
let status = 'idle';
let publicUrl = '';
let lastError = '';
let startedAt = 0;
let proc = null;
let stdoutBuf = '';

export function tunnelState() {
  return {
    status,
    url: publicUrl,
    error: lastError,
    startedAt,
    running: status === 'up' || status === 'starting',
    provider,
    // 威胁模型：写在这里，App 端直接把这段话展示给用户（合同②）。
    // 必须按 provider 分开写 —— 早前只有一份 localhost.run 的文案，
    // 换成 Cloudflare 之后界面还在说「SSH 反向隧道」，等于骗人。
    threatModel: threatModelFor(provider),
  };
}

export function threatModelFor(which) {
  // 注意：这段话是 App 端逐行用 Text('· ' + line) 渲染的纯文本 ——
  // 所以（1）不能用 Markdown 的 ** 加粗；（2）不能有空行（会渲染成一个孤零零的「·」）。
  // 缩进用全角空格，否则在窄屏上换行后看不出层级。
  const common = [
    '鉴权仍然靠服务端 token：带错 token 一律 401，隧道不等于放行。',
    '地址是随机子域名，每次重启都变；但 URL 泄露就等于服务暴露。',
    '建议：隧道只在临时场景开，用完立刻关；开隧道时加 --no-pair，别让配对窗口暴露在公网。',
  ];

  if (which === 'cloudflare') {
    return [
      '链路：手机 →(HTTPS) Cloudflare 边缘 →(QUIC 隧道) 本机服务。',
      '⚠️ Cloudflare 能看到明文内容。手机连的是 https://xxx.trycloudflare.com，',
      '　　而那张证书是 Cloudflare 的 —— TLS 在它的边缘终止，之后以明文 HTTP',
      '　　经隧道送到你机器上的 cloudflared。所以对话内容、pi 执行的命令、',
      '　　读写的文件，Cloudflare 都能读到。',
      '　　（早前这里写的是「第三方看不到明文内容」，那句话是错的，已更正。）',
      '　　→ 要连内容也不被看到，请用 VPN（Tailscale 之类）而不是公共隧道。',
      ...common,
      '代价：流量绕 Cloudflare 海外边缘（实测洛杉矶），延迟比局域网高 0.5~1.5 秒；免费隧道不承诺 SLA，断了要重开。',
    ];
  }
  return [
    '链路：手机 →(HTTPS) localhost.run →(SSH 反向隧道) 本机服务。',
    '⚠️ 同样地，localhost.run 能看到明文内容 —— TLS 在它的服务端终止，',
    '　　之后才经 SSH 隧道送到你机器，明文在它那里是暴露的。',
    '　　→ 要连内容也不被看到，请用 VPN（Tailscale 之类）。',
    ...common,
    '注意：实测 *.lhr.life 在国内不可达（curl 21 秒超时），这条只适合网络能到的环境。',
  ];
}

/** 从隧道进程的输出里抓公网地址（两种格式都认，别只等一种） */
export function parseTunnelUrl(text) {
  // 只认真实隧道域名：
  //   · trycloudflare.com —— Cloudflare quick tunnel
  //   · lhr.life / lhrtunnel.link —— localhost.run
  // 实测坑：localhost.run 的**欢迎信息**里带一条 `https://admin.localhost.run`，
  // 早先把泛化的 `*.localhost.run` 也放进来，于是把欢迎信息当成了隧道地址。
  const m = String(text ?? '').match(
    /https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)*\.(lhr\.life|lhrtunnel\.link|trycloudflare\.com)/i,
  );
  return m ? m[0] : '';
}

/**
 * 起隧道。已在上或正在起就直接返回当前状态（幂等）。
 */
export function startTunnel({ localPort, prefer = 'auto' }) {
  if (proc) return tunnelState();

  status = 'starting';
  lastError = '';
  stdoutBuf = '';
  startedAt = Date.now();

  // 默认优先 Cloudflare（实测国内可达）；没有二进制时退回 SSH 隧道（零安装但要网络能到）
  const useCloudflare =
    prefer === 'cloudflare' ||
    (prefer !== 'ssh' && hasCloudflared());

  let cmd;
  let args;
  if (useCloudflare) {
    provider = 'cloudflare';
    cmd = cloudflaredPath();
    args = ['tunnel', '--url', `http://localhost:${localPort}`, '--no-autoupdate'];
  } else {
    provider = SSH_PROVIDER;
    cmd = 'ssh';
    args = [
      '-o', 'StrictHostKeyChecking=no',
      '-o', 'UserKnownHostsFile=/dev/null',
      '-o', 'ServerAliveInterval=30',
      '-o', 'ExitOnForwardFailure=yes',
      '-R', `80:localhost:${localPort}`,
      `nokey@${SSH_PROVIDER}`,
    ];
  }

  try {
    proc = spawn(cmd, args, { windowsHide: true });
  } catch (error) {
    status = 'error';
    lastError = `起不了隧道进程（${cmd}）：${error?.message ?? error}`;
    proc = null;
    return tunnelState();
  }

  const onData = (chunk) => {
    const text = chunk.toString();
    stdoutBuf += text;
    if (stdoutBuf.length > 40000) stdoutBuf = stdoutBuf.slice(-40000);
    if (!publicUrl) {
      const url = parseTunnelUrl(text);
      if (url) {
        publicUrl = url;
        status = 'up';
        console.log(`[tunnel] 远程入口已就绪(${provider}): ${url}（→ 本机 :${localPort}）`);
      }
    }
  };

  proc.stdout?.on('data', onData);
  proc.stderr?.on('data', onData);

  proc.on('error', (error) => {
    status = 'error';
    lastError = `隧道进程启动失败：${error?.message ?? error}` +
      (cmd === 'ssh' ? '（系统里有没有 ssh？）' : `（${cmd} 跑不起来？）`);
    proc = null;
  });

  proc.on('exit', (code) => {
    proc = null;
    const tail = lastMeaningful(stdoutBuf);
    if (status === 'up' && publicUrl) {
      status = 'error';
      lastError = `隧道断开（${provider} 进程退出码 ${code}）—— 免费隧道会被服务端清理，重新开启即可`;
    } else if (status === 'starting') {
      status = 'error';
      lastError = `隧道没起来（退出码 ${code}）${tail ? `：${tail}` : ''}`;
    }
  });

  // 起不来的兜底：Cloudflare 一般 5-10 秒、SSH 一般 3-8 秒
  setTimeout(() => {
    if (status === 'starting' && !publicUrl) {
      status = 'error';
      lastError = provider === 'cloudflare'
        ? '20 秒内没拿到 trycloudflare 地址（到 Cloudflare 的网络不通？）'
        : '15 秒内没拿到公网地址（网络到不了 localhost.run？）';
      stopTunnel();
    }
  }, 20000).unref?.();

  return tunnelState();
}

/** 从输出里挑一行有意义的话做错误说明（cloudflared 会打一堆带 ANSI 的日志） */
function lastMeaningful(text) {
  const lines = String(text ?? '')
    .split('\n')
    .map((l) => l.replace(/\[[0-9;]*m/g, '').trim())
    .filter((l) => l && !/^[\s|_-]+$/.test(l) && !l.startsWith('INF |'));
  return lines.length ? lines[lines.length - 1].slice(0, 160) : '';
}

export function stopTunnel() {
  if (proc) {
    try {
      proc.kill();
    } catch {
      // 已经死了就算了
    }
    proc = null;
  }
  status = 'idle';
  publicUrl = '';
  startedAt = 0;
  // 关掉之后要把上一次的错误也清掉：界面上挂着一句「HTTP 502」而状态是「未开启」，
  // 用户会以为关都没关干净（实测踩到）
  lastError = '';
  console.log('[tunnel] 远程入口已关闭');
  return tunnelState();
}
