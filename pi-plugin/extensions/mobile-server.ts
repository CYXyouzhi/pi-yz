/**
 * pi-mobile-server —— 把「电脑端服务」做成 pi 插件。
 *
 * 装了它以后不用再记「cd 到某个目录再 node index.mjs」：
 *   /mobile            看状态（起没起、端口、手机该填什么、日志在哪）
 *   /mobile start      起服务（后台跑，日志落到 ~/.pi/agent/pi-mobile-server.log）
 *   /mobile stop       停服务
 *   /mobile doctor     自检：进程、端口、/api/health、当前会话数
 *   /mobile token <t>  设置/更换 token（手机端要填同一个）
 *
 * 设计取舍：
 *   · 服务端是独立 Node 进程，插件只负责**拉起/停止/探活**，不在 pi 进程里跑 HTTP；
 *     这样 pi 退出、切会话都不会把手机端连接带崩。
 *   · 真正的逻辑在 lib/ctl.mjs（纯 Node），插件只做命令与展示 ——
 *     于是它既能被 /mobile 调用，也能被命令行/测试直接验证。
 */

import { existsSync, rmSync } from 'node:fs';
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// 用动态 import 拿纯 JS 模块：让 pi 的加载器不必关心它的类型
const ctlPath = new URL('../lib/ctl.mjs', import.meta.url).href;

async function ctl(): Promise<any> {
  return await import(ctlPath);
}

export default function mobileServer(pi: ExtensionAPI) {
  // 这个 flag 只是为了让 `pi --help` 里能看到这个插件确实被加载了（无副作用）
  pi.registerFlag('mobile-status', {
    description: 'pi-mobile-server：启动时打印一次服务状态（不启动服务）',
    type: 'boolean',
    default: false,
  });

  // 不做「pi 启动就自动拉起服务」—— 启动/停止一律手动，/mobile start 与 /mobile stop，
  // 这样服务什么时候在跑完全由你决定，不会在你不知情时躺着一个进程。
  pi.on('session_start', async (_event, ctx) => {
    if (pi.getFlag('mobile-status') !== true) return;

    const mod = await ctl();
    const info = await mod.resolveStatus();
    const label = {
      self: '运行中（本插件拉起）',
      foreign: '运行中（别的进程拉起）',
      zombie: '僵死（进程在、端口没服务）',
      down: '未运行（用 /mobile start 启动）',
    }[info.kind] ?? info.kind;

    const lines = [
      '[pi-mobile-server]',
      `  状态 : ${label}`,
      `  监听 : ${info.hostAddress}:${info.port}`,
      `  配置 : ${info.configPath}`,
      `  日志 : ${info.logPath}`,
    ];
    // print/json 模式下没有 UI，只能往 stdout 打；交互模式顺带给个通知
    console.log(lines.join('\n'));
    ctx.ui.notify(`pi-mobile-server：${label}（${info.hostAddress}:${info.port}）`, 'info');
  });

  pi.registerCommand('mobile', {
    description: 'pi 远程服务：status / start / stop / doctor / token <新token>',
    handler: async (args, ctx) => {
      const mod = await ctl();
      const parts = (args ?? '').trim().split(/\s+/);
      const action = (parts[0] ?? 'status').toLowerCase();

      if (action === 'start') {
        ctx.ui.notify('正在启动 pi-mobile-server…', 'info');
        try {
          const port = parts[1] ? Number(parts[1]) : undefined;
          const info = await mod.start({ port });

          // 端口上有服务但不是插件起的 —— 如实说，不能报成「启动成功」
          if (info.foreign) {
            ctx.ui.notify(info.hint ?? `端口 ${info.port} 上已有别的服务`, 'warning');
            return;
          }

          if (!info.healthy) {
            ctx.ui.notify(
              `启动未成功：${info.reason ?? '健康检查未通过'}\n日志：${info.logPath}`,
              'error',
            );
            return;
          }

          ctx.ui.notify(
            info.alreadyRunning
              ? `服务已在运行（pid ${info.pid}）\n手机端填：\n${mod.connectInfo(info)}`
              : `服务已启动（pid ${info.pid}）\n手机端填：\n${mod.connectInfo(info)}`,
            'info',
          );
        } catch (error) {
          ctx.ui.notify(`启动失败：${String((error as Error).message ?? error)}`, 'error');
        }
        return;
      }

      if (action === 'stop') {
        const result = await mod.stop();
        if (result.stopped) {
          ctx.ui.notify(`已停止（pid ${result.pid}）`, 'info');
        } else {
          ctx.ui.notify(`没停：${result.reason}`, 'warning');
        }
        return;
      }

      if (action === 'doctor') {
        const info = await mod.doctor();
        const kindLabel = { self: '本插件拉起', foreign: '别的进程拉起', zombie: '僵死表', down: '没在跑' }[info.kind as string]
          ?? (info.running ? '在跑' : '没在跑');
        const lines = [
          `状态   : ${kindLabel}${info.pid ? `（pid ${info.pid}）` : ''}`,
          `探活   : ${info.healthy ? '通过' : (info.hint ?? '失败')}`,
          `版本   : ${info.health?.piVersion ? `pi ${info.health.piVersion}` : '—'}`,
          `会话数 : ${info.sessions ?? '—'}`,
          `端口   : ${info.port}`,
          `日志   : ${info.logPath}`,
        ];
        ctx.ui.notify(lines.join('\n'), info.healthy ? 'info' : 'warning');
        return;
      }

      if (action === 'token') {
        const token = parts[1];
        if (!token) {
          ctx.ui.notify('用法：/mobile token <新token>', 'warning');
          return;
        }
        const config = mod.readConfig();
        mod.writeConfig({ ...config, token });
        ctx.ui.notify(
          `token 已写入 ${mod.CONFIG_PATH}\n注意：正在跑的服务端要 /mobile stop 再 /mobile start 才生效`,
          'info',
        );
        return;
      }

      // default: status
      const info = await mod.resolveStatus();
      const kindLabel = { self: '运行中（本插件拉起）', foreign: '运行中（别的进程拉起）', zombie: '僵死：进程在但端口没服务', down: '未运行' }[info.kind as string]
        ?? (info.running ? '运行中' : '未运行');
      const lines = [
        `状态   : ${kindLabel}${info.pid ? `（pid ${info.pid}，${info.startedAt ?? ''}）` : ''}`,
        `监听   : ${info.hostAddress}:${info.port}`,
        `入口   : ${info.entry}${existsSync(info.entry) ? '' : '（不存在！用 PI_MOBILE_SERVER_ENTRY 指定）'}`,
        `配置   : ${info.configPath}`,
        `日志   : ${info.logPath}`,
        '',
        '手机端连接信息：',
        mod.connectInfo(info),
      ];
      ctx.ui.notify(lines.join('\n'), info.kind === 'down' || info.kind === 'zombie' ? 'warning' : 'info');
    },
  });
}
