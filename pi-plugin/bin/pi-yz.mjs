#!/usr/bin/env node
// pi-yz —— pi-mobile 服务端的命令行入口（不依赖 pi 主进程）。
//
// 用它的理由：/yz 只能在 pi 里敲；pi 没开着的时候（或干脆不想开 TUI 的时候）
// 你还是得有个办法把服务端拉起来。这条命令就是那个入口。
//
//   pi-yz            后台启动，并把「手机该填什么」打在屏幕上
//   pi-yz stop       停止（只停本工具拉起的那个）
//   pi-yz status     看状态
//   pi-yz doctor     自检（进程 / 端口 / 健康接口 / 版本 / 会话数）
//   pi-yz token <t>  设置 token
//   pi-yz logs       看日志尾部
//
// 设计取舍：所有逻辑都复用 pi-plugin/lib/ctl.mjs —— 跟 pi 里的 /yz 走同一套代码。
// 两套实现会让「命令行说在跑、pi 里说没跑」这种分歧悄悄长出来。

import { existsSync, readFileSync } from 'node:fs';

const ctlPath = new URL('../lib/ctl.mjs', import.meta.url).href;
const ctl = await import(ctlPath);

const argv = process.argv.slice(2);
const action = (argv[0] ?? 'start').toLowerCase();

const C = process.stdout.isTTY
  ? { dim: '\x1b[2m', bold: '\x1b[1m', green: '\x1b[32m', yellow: '\x1b[33m', red: '\x1b[31m', off: '\x1b[0m' }
  : { dim: '', bold: '', green: '', yellow: '', red: '', off: '' };

/**
 * 算显示宽度：中文字符占两格，而 padEnd 只数字符个数。
 * 不修正的话 label 里混了中文时列会参差不齐。
 */
function displayWidth(text) {
  let width = 0;
  for (const ch of text) width += ch.codePointAt(0) > 0x2e80 ? 2 : 1;
  return width;
}

function line(label, value) {
  const pad = ' '.repeat(Math.max(1, 10 - displayWidth(label)));
  console.log(`  ${C.dim}${label}${pad}${C.off}${value}`);
}

/**
 * 从日志里抓最近一次启动打印的配对码。
 *
 * 为什么要抓日志：配对码只由服务端启动那一刻打印到 stdout（没有 API 暴露它），
 * 而 stdout 被重定向到了 LOG_PATH —— 日志就是唯一的来源。
 */
function readPairCode() {
  try {
    const text = readFileSync(ctl.LOG_PATH, 'utf8');
    const matches = [...text.matchAll(/配对码\s*[:：]\s*(\d{4,8})/g)];
    return matches.length ? matches[matches.length - 1][1] : null;
  } catch {
    return null;
  }
}

/** 启动成功后要打的东西：手机端真正需要的三行 + 怎么停 */
function printConnect(info) {
  const cfg = ctl.readConfig();

  // 配对码只有启动后 5 分钟内有效。服务已经在跑很久了还把它拿出来，
  // 只会让人白填一次再失败 —— 不如直说它过期了。
  const startedMs = info.startedAt ? new Date(info.startedAt).getTime() : 0;
  const fresh = startedMs && Date.now() - startedMs < 5 * 60 * 1000;
  const pairCode = fresh ? readPairCode() : null;

  console.log();
  line('地址', `${info.hostAddress}  (端口 ${info.port})`);
  line('token', info.token ?? '(未设置)');
  if (pairCode) {
    const leftSec = Math.max(0, Math.round((5 * 60 * 1000 - (Date.now() - startedMs)) / 1000));
    let desc = `约 ${leftSec} 秒后过期`;
    if (leftSec > 60) desc = `约 ${Math.round(leftSec / 60)} 分钟后过期`;
    line('配对码', `${pairCode}  ${C.dim}（${desc}）${C.off}`);
  } else if (startedMs) {
    console.log(`  ${C.dim}配对码已过期（启动超过 5 分钟）。要重新拿：pi-yz stop && pi-yz start${C.off}`);
  }
  console.log();
  line('日志', info.logPath);
  line('停止', `${C.bold}pi-yz stop${C.off}`);
  console.log();
  if (cfg.port !== info.port) {
    console.log(`  ${C.yellow}注意：配置里记的端口是 ${cfg.port}，实际监听在 ${info.port}${C.off}`);
  }
}

switch (action) {
  case 'start': {
    const port = argv[1] && /^\d+$/.test(argv[1]) ? Number(argv[1]) : undefined;
    const info = await ctl.start({ port });

    if (info.foreign) {
      console.log(`${C.yellow}端口 ${info.port} 上已有服务在跑，但不是 pi-yz 拉起的。${C.off}`);
      console.log(`  ${info.hint ?? ''}`);
      console.log();
      console.log('  如果是你自己起的（比如 start.cmd），手机上直接连它就行。');
      process.exitCode = 0;
    }

    if (!info.healthy) {
      console.error(`${C.red}启动失败：${info.reason ?? '健康检查未通过'}${C.off}`);
      console.error(`  日志：${info.logPath}`);
      if (info.logTail) {
        console.error();
        console.error(`${C.dim}${info.logTail}${C.off}`);
      }
      process.exitCode = 1;
    }

    if (info.alreadyRunning) {
      console.log(`${C.green}服务已在运行${C.off}${C.dim}（pid ${info.pid}，已复用，没重复启动）${C.off}`);
    } else {
      console.log(`${C.green}pi-mobile-server 已在后台启动${C.off}${C.dim}（pid ${info.pid}）${C.off}`);
    }
    printConnect(info);
    // 后台进程已 detached，这里正常退出，不占终端
    process.exitCode = 0;
    break;
  }

  case 'stop': {
    const result = await ctl.stop();
    if (result.stopped) {
      console.log(`${C.green}已停止${C.off}${C.dim}（pid ${result.pid}）${C.off}`);
      if (result.portStillBusy) {
        console.log(`${C.yellow}但端口还占着，可能没完全退出，稍等或再执行一次${C.off}`);
      }
    } else {
      console.log(`${C.yellow}没停：${result.reason}${C.off}`);
    }
    process.exitCode = 0;
    break;
  }

  case 'status': {
    const info = await ctl.resolveStatus();
    const label = {
      self: `${C.green}运行中${C.off}（pi-yz 拉起）`,
      foreign: `${C.green}运行中${C.off}（别的进程拉起）`,
      zombie: `${C.yellow}僵死${C.off}：进程在，但端口上没服务`,
      down: `${C.dim}未运行${C.off}`,
    }[info.kind] ?? info.kind;

    console.log();
    line('状态', label);
    if (info.pid) line('pid', String(info.pid));
    line('监听', `${info.hostAddress}:${info.port}`);
    if (info.kind === 'self' || info.kind === 'foreign') {
      line('token', info.token ?? '(未设置)');
    }
    line('配置', info.configPath);
    line('日志', info.logPath);
    console.log();
    if (info.kind === 'down') console.log(`  启动：${C.bold}pi-yz${C.off}`);
    if (info.kind === 'zombie') console.log(`  修复：${C.bold}pi-yz start${C.off}（会自动清掉僵死进程再拉起）`);
    console.log();
    process.exitCode = 0;
    break;
  }

  case 'doctor': {
    const info = await ctl.doctor();
    console.log();
    line('状态', info.healthy ? `${C.green}健康${C.off}` : `${C.red}异常${C.off}`);
    if (info.pid) line('pid', String(info.pid));
    line('端口', String(info.port));
    if (info.healthy && info.health) {
      line('服务端', `v${info.health.version ?? '?'}`);
      line('pi 版本', info.health.piVersion ?? '—');
      line('会话数', String(info.sessions ?? '—'));
    } else if (info.hint) {
      line('说明', info.hint);
    }
    line('日志', info.logPath);
    console.log();
    process.exitCode = info.healthy ? 0 : 1;
    break;
  }

  case 'token': {
    const token = argv[1];
    if (!token) {
      console.error('用法：pi-yz token <新token>');
      process.exitCode = 1;
    }
    ctl.writeConfig({ ...ctl.readConfig(), token });
    console.log(`token 已写入 ${ctl.CONFIG_PATH}`);
    console.log(`注意：正在跑的服务端要 ${C.bold}pi-yz stop${C.off} 再 ${C.bold}pi-yz start${C.off} 才生效`);
    process.exitCode = 0;
    break;
  }

  case 'logs': {
    if (!existsSync(ctl.LOG_PATH)) {
      console.log(`还没有日志文件：${ctl.LOG_PATH}`);
      process.exitCode = 0;
    }
    const lines = readFileSync(ctl.LOG_PATH, 'utf8').split('\n').slice(-(Number(argv[1]) || 40));
    console.log(lines.join('\n'));
    process.exitCode = 0;
    break;
  }

  case 'help':
  case '--help':
  case '-h': {
    console.log(`
${C.bold}pi-yz${C.off} —— 手机端 pi 的电脑侧服务

  ${C.bold}pi-yz${C.off}              后台启动，并打印手机要填的地址与 token
  ${C.bold}pi-yz start${C.off} [端口]  同上，可指定端口
  ${C.bold}pi-yz stop${C.off}         停止服务
  ${C.bold}pi-yz status${C.off}       看状态（谁拉起的、在不在跑）
  ${C.bold}pi-yz doctor${C.off}       自检：进程、端口、健康接口、pi 版本、会话数
  ${C.bold}pi-yz token${C.off} <token> 设置 token（之后要 stop + start）
  ${C.bold}pi-yz logs${C.off} [行数]  看日志尾部

服务端是独立进程（detached），这个命令退出后它继续跑。
在 pi 里操作等价命令：${C.bold}/yz${C.off}
`);
    process.exitCode = 0;
    break;
  }

  default: {
    console.error(`未知命令：${action}`);
    console.error(`试试 ${C.bold}pi-yz help${C.off}`);
    process.exitCode = 1;
  }
}
