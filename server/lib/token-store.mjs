// token 持久化：一次生成、永久使用。
//
// ## 为什么需要它
//
// 原来只有两条路，都不好用：
//
//   · `--token pimobile2026`（`start.cmd` 里写死的）：是「项目名 + 年份」，
//     而这个项目在 GitHub 上就叫 pi-mobile —— 猜中的成本几乎为零；
//   · 不给 `--token`：每次启动 `randomBytes(24)` 随机生成，**很强**，
//     但**每次重启都变**，手机端得重新填一遍 —— 等于不可用。
//
// 现在：首次启动生成强随机 token 写入 `.token`，之后每次启动读它。
// 于是同时拿到「足够强」和「不随重启变化」。
//
// 优先级：`--token` 参数  >  `.token` 文件  >  首次生成并写入。
// 显式传参时不落盘 —— 免得把「临时试一下」的值固化成长期凭据。
//
// ## 文件是明文的，这一点要说清楚，不做假的安全感
//
// 没有加密，理由：能读这个文件的人，本来就能读你的会话记录、你的 `~/.pi`
// 配置、你的 SSH 私钥 —— 多一个 token 对他没有增量。而且 Windows 上没有
// 跨平台、无依赖的「安全存储」可用（DPAPI 是 Windows 专用，Linux/macOS 是另一套）。
//
// 所以这里只做两件正确的小事：
//   1. 文件写进 `.gitignore`（别跟着仓库跑到 GitHub 上）；
//   2. 启动日志只打印**脱敏**后的值（`maskSecret`），因为启动日志经常被截图。

import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));

/** token 文件位置：server/.token（与 index.mjs 同级的上一层） */
export const TOKEN_FILE = join(HERE, '..', '.token');

/** 生成一个强随机 token：192 bit 熵 -> 48 位十六进制 */
export function generateToken() {
  return randomBytes(24).toString('hex');
}

/**
 * 决定本次进程使用哪个 token。
 *
 * @param {string|undefined} explicit `--token` 传进来的值
 * @returns {{ token: string, source: 'explicit'|'file'|'generated', path: string }}
 */
export function resolveToken(explicit) {
  if (explicit) {
    return { token: explicit, source: 'explicit', path: TOKEN_FILE };
  }

  if (existsSync(TOKEN_FILE)) {
    const saved = readFileSync(TOKEN_FILE, 'utf8').trim();
    if (saved) return { token: saved, source: 'file', path: TOKEN_FILE };
    // 文件在但内容是空的：当成损坏，走下面重新生成（不抛错，用户不该被一个空文件卡住）
  }

  const token = generateToken();
  // mode 只在类 Unix 上生效；Windows 忽略它（不报错），所以别把它当安全保证
  writeFileSync(TOKEN_FILE, token + '\n', { encoding: 'utf8', mode: 0o600 });
  return { token, source: 'generated', path: TOKEN_FILE };
}

/** 给日志用的说明：这次 token 是哪来的 */
export function describeSource(source) {
  switch (source) {
    case 'explicit':
      return '来自 --token 参数（不落盘）';
    case 'file':
      return '来自 .token 文件（与上次相同，重启不用重配）';
    case 'generated':
      return '首次生成并已写入 .token（以后重启都会复用它）';
    default:
      return '未知来源';
  }
}
