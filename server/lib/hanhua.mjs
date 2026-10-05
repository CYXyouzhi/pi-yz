// 复用电脑端已有的汉化资源。
//
// 机器上原本就有一套汉化（用 pi 的汉化扩展做的）：
//   ~/.pi/agent/commands-cn.json   48 条命令的中文说明
//   ~/.pi/agent/hanhua-auto.json   插件界面文案的对照（给 CLI 打补丁用，App 这边用不上）
//
// 这里的做法：**不另造一份翻译表**，直接读 commands-cn.json，
// 给命令对象补一个 descriptionZh 字段；英文原文仍然原样保留。
// 这样 App 只要看语言设置决定显示哪个，未翻译的项自然会露出原文。

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const ZH_PATH = join(homedir(), '.pi', 'agent', 'commands-cn.json');

// 电脑端还有第二份汉化表：hanhua-auto.json。
// 它是「汉化扩展」生成的补丁表：{ "<插件 dist 文件路径>": [["原文", "中文"], ...] }。
// 里面既有扩展注册的命令标题（Goal Complete → Goal Complete（目标完成）），
// 也有扩展弹出的整句提示。这里把它拍平成一个 原文 → 中文 的字典复用，
// 顺带记下每个插件包被汉化了多少处（给 App 的插件列表当中文注释用）。
const AUTO_PATH = join(homedir(), '.pi', 'agent', 'hanhua-auto.json');

let cache = null;

/** 读中文对照表（读不到就返回空表，绝不因为汉化文件缺失让命令列表挂掉） */
export function commandZhMap() {
  if (cache) return cache;
  try {
    if (existsSync(ZH_PATH)) {
      const parsed = JSON.parse(readFileSync(ZH_PATH, 'utf8'));
      const map = new Map();
      for (const [key, value] of Object.entries(parsed)) {
        if (typeof value === 'string' && value.trim() !== '') {
          map.set(key, value.trim());
        }
      }
      cache = map;
      return cache;
    }
  } catch {
    // 坏文件当作没有
  }
  cache = new Map();
  return cache;
}

let autoCache = null;

function unquote(text) {
  const trimmed = String(text ?? '').trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

/** 拍平 hanhua-auto.json：{ 原文 → 中文 } */
export function hanhuaPairMap() {
  if (autoCache) return autoCache;
  const map = new Map();
  try {
    if (existsSync(AUTO_PATH)) {
      const parsed = JSON.parse(readFileSync(AUTO_PATH, 'utf8'));
      for (const pairs of Object.values(parsed)) {
        if (!Array.isArray(pairs)) continue;
        for (const pair of pairs) {
          if (!Array.isArray(pair) || pair.length < 2) continue;
          const original = unquote(pair[0]);
          const chinese = unquote(pair[1]);
          if (original && chinese && original !== chinese) map.set(original, chinese);
        }
      }
    }
  } catch {
    // 坏文件当作没有
  }
  autoCache = map;
  return map;
}

/** 某个已安装包在电脑端被汉化了多少处（按 dist 文件路径归属） */
export function packageZhCount(installedPath) {
  if (!installedPath) return 0;
  const needle = String(installedPath).replace(/\\/g, '\\').toLowerCase();
  let count = 0;
  try {
    if (!existsSync(AUTO_PATH)) return 0;
    const parsed = JSON.parse(readFileSync(AUTO_PATH, 'utf8'));
    for (const [file, pairs] of Object.entries(parsed)) {
      if (!Array.isArray(pairs)) continue;
      if (file.toLowerCase().startsWith(needle)) count += pairs.length;
    }
  } catch {
    return 0;
  }
  return count;
}

/** 已经是中文就不动（内置命令的说明本来就是中文） */
function looksChinese(text) {
  return /[\u4e00-\u9fff]/.test(text ?? '');
}

/**
 * 给命令列表补 descriptionZh。
 *
 * 匹配规则（按优先级）：
 *   1. 原名精确匹配（/compact → "compact"）
 *   2. 去掉 skill: / prompt: 前缀后再匹配
 *   3. 反查：对照表里的 key 出现在命令名里（例如扩展命令带命名空间前缀）
 */
export function withChineseDescriptions(commands) {
  const map = commandZhMap();
  return commands.map((command) => {
    const name = String(command.name ?? '');
    if (looksChinese(command.description)) {
      // 说明本身就是中文（技能大多如此）—— 中文说明就是原文，标出来免得看数据时分不清
      return { ...command, descriptionZh: command.description, descriptionZhSource: '原文本就是中文' };
    }
    const bare = name.includes(':') ? name.slice(name.indexOf(':') + 1) : name;
    let zh = map.get(name) ?? map.get(bare) ?? null;
    if (!zh) {
      for (const [key, value] of map) {
        if (name.endsWith(key) || key.endsWith(bare)) {
          zh = value;
          break;
        }
      }
    }
    if (zh) return { ...command, descriptionZh: zh, descriptionZhSource: 'commands-cn' };

    // 第二份表：扩展命令的英文说明/标题常常和 hanhua-auto.json 里的原文一模一样
    const pairs = hanhuaPairMap();
    const description = String(command.description ?? '').trim();
    for (const candidate of [name, bare, description]) {
      const hit = candidate ? pairs.get(candidate) : null;
      if (hit) return { ...command, descriptionZh: hit, descriptionZhSource: 'hanhua-auto' };
    }
    return command;
  });
}

export function hanhuaStatus() {
  return {
    commandsCn: { source: ZH_PATH, entries: commandZhMap().size },
    hanhuaAuto: { source: AUTO_PATH, entries: hanhuaPairMap().size },
  };
}
