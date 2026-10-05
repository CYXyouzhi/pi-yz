// Provider 凭据（API Key）的查看与增删。
//
// 手机上补一个 API Key 是「配置 pi 自己」的一部分，不用回电脑。
//
// 关键点：用 createAgentSessionServices() 独立拿 modelRuntime，
// 不需要先有一条会话 —— 设置页在没有打开任何会话时也应该能用。
// 服务创建约 1 秒，所以缓存起来复用。
//
// 注意：setRuntimeApiKey / removeRuntimeApiKey 会写 pi 的凭据库（auth.json），
// 属于真实写入；调用方要确认是用户明确操作。

import { createAgentSessionServices, getAgentDir } from '@earendil-works/pi-coding-agent';

let servicesPromise = null;

function services() {
  servicesPromise ??= createAgentSessionServices({ cwd: getAgentDir() });
  return servicesPromise;
}

/** 已配置凭据的清单（不返回密钥本身，只报"哪个 provider 配了"） */
export async function listCredentials() {
  const { modelRuntime } = await services();
  const credentials = await modelRuntime.listCredentials();
  return {
    credentials: credentials.map((item) => ({
      provider: item.providerId ?? item.provider ?? '?',
      type: item.type ?? 'api_key',
    })),
  };
}

/** 写入一个 API Key */
export async function setApiKey(provider, apiKey) {
  const id = String(provider ?? '').trim();
  const key = String(apiKey ?? '').trim();
  if (!id) throw new Error('缺少 provider');
  if (!key) throw new Error('缺少 apiKey');

  const { modelRuntime } = await services();
  await modelRuntime.setRuntimeApiKey(id, key);
  return { provider: id };
}

/** 删除某个 provider 的凭据 */
export async function removeApiKey(provider) {
  const id = String(provider ?? '').trim();
  if (!id) throw new Error('缺少 provider');

  const { modelRuntime } = await services();
  await modelRuntime.removeRuntimeApiKey(id);
  return { provider: id };
}
