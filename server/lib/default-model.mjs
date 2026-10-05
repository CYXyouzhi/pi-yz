// 读写 pi 的「默认模型」——即新会话用哪个 provider + 模型。
//
// 为什么要单独一个模块：
//   pi 的会话级 set_model 只改当前会话；要让**新会话**默认用另一个模型，
//   只能改 ~/.pi/agent/settings.json 里的 defaultProvider / defaultModel。
//   这是唯一一处我们会写 pi 自己的配置文件的地方，所以集中在这里，
//   写入时保留其它字段（12 个字段里我们只碰 2 个），并做原子替换。

import { readFile, writeFile, rename } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const SETTINGS = join(homedir(), '.pi', 'agent', 'settings.json');

/** 当前默认模型；文件不存在或坏了就返回空值（不抛） */
export async function readDefaultModel() {
  try {
    const raw = await readFile(SETTINGS, 'utf8');
    const parsed = JSON.parse(raw);
    return {
      provider: typeof parsed.defaultProvider === 'string' ? parsed.defaultProvider : null,
      modelId: typeof parsed.defaultModel === 'string' ? parsed.defaultModel : null,
      path: SETTINGS,
    };
  } catch {
    return { provider: null, modelId: null, path: SETTINGS };
  }
}

/**
 * 写默认模型。
 *
 * 先写临时文件再 rename —— 避免写到一半失败把 settings.json 弄坏
 * （那是 pi 的启动配置，坏了以后 pi 都起不来）。
 */
export async function writeDefaultModel(provider, modelId) {
  if (!provider || !modelId) {
    throw new Error('缺少 provider 或 modelId');
  }
  const parsed = existsSync(SETTINGS)
    ? JSON.parse(await readFile(SETTINGS, 'utf8'))
    : {};
  const next = { ...parsed, defaultProvider: provider, defaultModel: modelId };
  const tmp = `${SETTINGS}.tmp-${Date.now()}`;
  await writeFile(tmp, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
  await rename(tmp, SETTINGS);
  return { provider, modelId, path: SETTINGS };
}
