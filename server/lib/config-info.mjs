// 会话无关的配置信息：模型 / 思考等级 / 技能与提示模板。
//
// 为什么单独做一层：AI 配置页原先全走会话命令（get_available_models / get_commands），
// 而会话命令必须有「一条打开的会话」当通道 —— 开机后没打开会话时，
// 那页会显示成「— / 无」，看起来像坏了，其实只是没通道。
// 但"配置 pi 自己"本来就不该依赖某条会话（pi-web 也是无会话可配的）。
//
// createAgentSessionServices() 能独立拿到 modelRuntime 与 resourceLoader（约 1s），
// 所以按 cwd 缓存起来复用（和 credentials.mjs 是同一个思路）。
//
// 拿不到的部分：扩展命令（/汉化 这类）是 ExtensionRunner 在会话启动时注册的，
// SDK 没有导出独立的构造入口，所以仍然只能从「打开的会话」里读。
// App 端对这类分组的处理是显示"需打开会话"，而不是显示"无"。

import { withChineseDescriptions } from './hanhua.mjs';
import { createAgentSessionServices, getAgentDir } from '@earendil-works/pi-coding-agent';
import { BUILTIN_COMMANDS } from './builtin-commands.mjs';

// 照 pi-ai 的 getSupportedThinkingLevels 复刻（见 pi-ai/dist/models.js:681）。
// 不能直接 import：pi-ai 是 pi-coding-agent 的内嵌依赖（装在它自己的 node_modules 下），
// 从本项目 import 会解析失败。逻辑就这十来行，照抄比绕路径稳。
const EXTENDED_THINKING_LEVELS = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];

function supportedThinkingLevels(model) {
  if (!model?.reasoning) return ['off'];
  return EXTENDED_THINKING_LEVELS.filter((level) => {
    const mapped = model.thinkingLevelMap?.[level];
    if (mapped === null) return false; // 显式不支持
    if (level === 'xhigh' || level === 'max') return mapped !== undefined; // 只有显式映射才有
    return true;
  });
}

// cwd → services 缓存。创建要 ~1s，手机端通常只有一两个工作区。
const cache = new Map();
const MAX_CACHE = 4;

export async function servicesFor(cwd) {
  const key = cwd && String(cwd).trim() ? String(cwd) : getAgentDir();
  const hit = cache.get(key);
  if (hit) return hit;
  const promise = createAgentSessionServices({ cwd: key });
  cache.set(key, promise);
  if (cache.size > MAX_CACHE) cache.delete(cache.keys().next().value); // 淘汰最旧的
  try {
    return await promise;
  } catch (error) {
    cache.delete(key); // 失败不留在缓存里，下次可重试
    throw error;
  }
}

/** 可用模型（含每个模型支持的思考等级，省一次往返） */
export async function configModels(cwd) {
  const { modelRuntime } = await servicesFor(cwd);
  const models = modelRuntime.getAvailableSnapshot();
  return {
    models: models.map((model) => ({
      provider: model.provider,
      id: model.id,
      name: model.name ?? model.id,
      contextWindow: model.contextWindow ?? null,
      reasoning: Boolean(model.reasoning),
      thinkingLevels: supportedThinkingLevels(model),
    })),
  };
}

/** 某个模型可用的思考等级；不指定就按默认模型 */
export async function configThinkingLevels(cwd, provider, modelId) {
  const { modelRuntime, settingsManager } = await servicesFor(cwd);
  const models = modelRuntime.getAvailableSnapshot();
  const model =
    models.find((m) => m.provider === provider && m.id === modelId) ?? models[0] ?? null;
  return {
    levels: model ? supportedThinkingLevels(model) : [...EXTENDED_THINKING_LEVELS],
    current: settingsManager?.getDefaultThinkingLevel?.() ?? null,
    model: model ? { provider: model.provider, id: model.id } : null,
  };
}

/** 会话无关就能拿到的命令：提示模板 + 技能 + 内置命令（缺扩展命令，见文件头说明） */
export async function configCommands(cwd) {
  const { resourceLoader } = await servicesFor(cwd);
  const commands = [];

  // ① 提示模板（.pi/prompts/*.md）
  for (const template of resourceLoader.getPrompts().prompts ?? []) {
    commands.push({
      name: template.name,
      description: template.description,
      source: 'prompt',
      sourceInfo: template.sourceInfo,
    });
  }

  // ② 技能（名字带 skill: 前缀，和会话命令保持一致）
  //    sourcePath = SKILL.md 的路径：App 端点进去看内容要用它
  for (const skill of resourceLoader.getSkills().skills ?? []) {
    commands.push({
      name: `skill:${skill.name}`,
      description: skill.description,
      source: 'skill',
      sourceInfo: skill.sourceInfo,
      sourcePath: skill.filePath ?? null,
    });
  }

  // ③ 内置命令（pi 的 get_commands 不报它们，由我们维护）
  for (const item of BUILTIN_COMMANDS) {
    commands.push({
      name: item.name,
      description: item.description,
      argHint: item.argHint,
      source: 'builtin',
    });
  }

  // 复用电脑端的 commands-cn.json：补中文说明（未翻译的项原样保留）
  return { commands: withChineseDescriptions(commands) };
}
