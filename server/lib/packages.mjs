// pi 包（插件）管理：列出已装、安装、卸载、更新。
//
// 为什么用 SDK 的 DefaultPackageManager 而不是自己拼 npm 命令：
//   装的来源有三种（npm 包、git 仓库、本地目录），pi 自己负责解析与落到
//   `.pi/`（或 user 级）目录下，并写进 settings。自己拼一遍必然会漏语义。
//
// 注意：install / update 会真的联网下载（npm / git），耗时几十秒很正常，
// 所以 HTTP 请求是阻塞的，客户端超时要放宽。

import { packageZhCount } from './hanhua.mjs';
import { DefaultPackageManager, getAgentDir } from '@earendil-works/pi-coding-agent';
import { servicesFor } from './config-info.mjs';

async function managerFor(cwd) {
  const workdir = cwd && String(cwd).trim() ? String(cwd) : getAgentDir();
  const { settingsManager } = await servicesFor(workdir);
  return new DefaultPackageManager({
    cwd: workdir,
    agentDir: getAgentDir(),
    settingsManager,
  });
}

/** 已配置的包 + 可更新列表 */
export async function listPackages(cwd) {
  const manager = await managerFor(cwd);
  const packages = manager.listConfiguredPackages().map((item) => ({
    source: item.source,
    scope: item.scope,
    filtered: item.filtered === true,
    installedPath: item.installedPath ?? null,
    // 电脑端汉化扩展在这个包里翻译了多少处文案（没有就是 0）
    zhCount: packageZhCount(item.installedPath ?? null),
  }));

  let updates = [];
  let updateError = null;
  try {
    updates = (await manager.checkForAvailableUpdates()).map((item) => ({
      source: item.source,
      displayName: item.displayName,
      type: item.type,
      scope: item.scope,
    }));
  } catch (error) {
    // 没网 / 不是 git 仓库 / npm 不可用都会走到这里，不该让整个列表失败
    updateError = String(error?.message ?? error);
  }

  return { packages, updates, updateError };
}

/**
 * 安装 / 卸载 / 更新。
 * @param {'install'|'remove'|'update'} action
 * @param {string} source npm 包名、git 地址或本地路径
 * @param {boolean} local true = 项目级（写进项目 .pi），false = 用户级
 */
export async function runPackageAction({ cwd, action, source, local = false }) {
  const manager = await managerFor(cwd);
  const events = [];
  manager.setProgressCallback((event) => {
    events.push({ type: event.type, action: event.action, source: event.source, message: event.message ?? null });
  });

  try {
    if (action === 'install') {
      const target = String(source ?? '').trim();
      if (!target) throw new Error('要装的包名/地址不能空');
      await manager.installAndPersist(target, { local });
    } else if (action === 'remove') {
      const target = String(source ?? '').trim();
      if (!target) throw new Error('要卸载的包名不能空');
      await manager.removeAndPersist(target, { local });
    } else if (action === 'update') {
      await manager.update(String(source ?? '').trim() || undefined);
    } else {
      throw new Error(`未知操作：${action}`);
    }
  } finally {
    manager.setProgressCallback(undefined);
  }

  console.log(`[packages] ${action} ${source ?? '(全部)'}：${events.length} 条进度`);
  const packages = manager.listConfiguredPackages().map((item) => ({
    source: item.source,
    scope: item.scope,
    filtered: item.filtered === true,
    installedPath: item.installedPath ?? null,
  }));
  return { action, source: source ?? null, packages, events: events.slice(-15) };
}
