// Provider 登录（API Key 向导 + OAuth）。
//
// 为什么要做：手机上补一个 key 只是「能用」；pi 的 /login 还支持 OAuth
// （订阅制账号、设备码流程），pi-web 也是在这层做的。
//
// 实现方式：HTTP 是请求-响应，而登录流程是「服务端问一句、用户答一句」的长交互。
// 所以做成**可轮询的任务**：
//   POST /api/login {provider,type} → 拿到 id
//   GET  /api/login/:id            → state(running|prompt|done|error|cancelled)
//                                    + prompt（待回答）+ events（授权链接/设备码）
//   POST /api/login/:id {answer}   → 回答当前提示
//   POST /api/login/:id/cancel     → 取消
// 比 SSE 简单，也不怕手机切后台。

import { getAgentDir } from '@earendil-works/pi-coding-agent';
import { servicesFor } from './config-info.mjs';

let seq = 0;
const attempts = new Map();

/** 已登录/可登录的 provider 清单 */
export async function listProviders() {
  const { modelRuntime } = await servicesFor(getAgentDir());
  return {
    providers: modelRuntime.getProviders().map((provider) => {
      const status = modelRuntime.getProviderAuthStatus(provider.id);
      const auth = [];
      if (provider.auth?.apiKey) {
        auth.push({
          type: 'api_key',
          label: provider.auth.apiKey.name ?? 'API Key',
          // login 不存在 = 只能靠环境变量/配置文件，界面上要说明
          interactive: typeof provider.auth.apiKey.login === 'function',
        });
      }
      if (provider.auth?.oauth) {
        auth.push({
          type: 'oauth',
          label: provider.auth.oauth.name ?? 'OAuth',
          interactive: true,
          subscription: provider.auth.oauth.isSubscription === true,
        });
      }
      return {
        id: provider.id,
        name: provider.name ?? provider.id,
        configured: status.configured === true,
        source: status.source ?? null,
        label: status.label ?? null,
        auth,
      };
    }),
  };
}

/** 起一次登录，返回任务 id */
export async function startLogin(providerId, type = 'api_key') {
  const id = String(providerId ?? '').trim();
  if (!id) throw new Error('缺少 provider');
  const { modelRuntime, settingsManager } = await servicesFor(getAgentDir());

  const controller = new AbortController();
  const attempt = {
    id: `login-${++seq}`,
    provider: id,
    type,
    controller,
    state: 'running', // running | prompt | done | error | cancelled
    prompt: null,
    events: [],
    result: null,
    error: null,
    resolveAnswer: null,
    startedAt: Date.now(),
  };
  attempts.set(attempt.id, attempt);

  const interaction = {
    signal: controller.signal,
    prompt(prompt) {
      return new Promise((resolve, reject) => {
        attempt.state = 'prompt';
        attempt.prompt = {
          type: prompt.type,
          message: prompt.message,
          placeholder: prompt.placeholder ?? null,
          options: (prompt.options ?? []).map((option) => ({
            id: option.id,
            label: option.label,
            description: option.description ?? null,
          })),
        };
        attempt.resolveAnswer = (value) => {
          attempt.prompt = null;
          attempt.state = 'running';
          attempt.resolveAnswer = null;
          resolve(value);
        };
        // 提示自带的 signal：例如设备码流程里回调服务器先拿到了 token，
        // 手输那条提示就该作废（不是错误）
        prompt.signal?.addEventListener('abort', () => {
          if (attempt.prompt === null) return;
          attempt.prompt = null;
          attempt.resolveAnswer = null;
          attempt.state = 'running';
          reject(new Error('prompt-aborted'));
        }, { once: true });
      });
    },
    notify(event) {
      attempt.events.push(event);
    },
  };

  modelRuntime
    .login(id, type, interaction, {
      // 有些 OAuth 流程（如 OpenAI/ChatGPT）要一个安装级 UUID 当 host id，
      // 没给会直接报错。pi 的 CLI 也是用 settingsManager 的这个值。
      getDeviceId: () => settingsManager.getOrCreateDeviceId(),
    })
    .then((credential) => {
      attempt.state = 'done';
      attempt.result = { type: credential?.type ?? type };
      console.log(`[login] ${id} 登录成功（${type}）`);
    })
    .catch((error) => {
      if (controller.signal.aborted) {
        attempt.state = 'cancelled';
        return;
      }
      attempt.state = 'error';
      attempt.error = String(error?.message ?? error);
      console.warn(`[login] ${id} 失败: ${attempt.error}`);
    });

  return { id: attempt.id, provider: id, type };
}

/** 轮询状态；events 取走即清空（避免重复弹已看过的提示） */
export function loginStatus(taskId) {
  const attempt = attempts.get(taskId);
  if (!attempt) return null;
  const events = attempt.events.splice(0, attempt.events.length);
  return {
    id: attempt.id,
    provider: attempt.provider,
    type: attempt.type,
    state: attempt.state,
    prompt: attempt.prompt,
    events,
    result: attempt.result,
    error: attempt.error,
  };
}

/** 回答当前提示 */
export function answerLogin(taskId, answer) {
  const attempt = attempts.get(taskId);
  if (!attempt || !attempt.resolveAnswer) return false;
  const resolve = attempt.resolveAnswer;
  attempt.resolveAnswer = null;
  resolve(String(answer ?? ''));
  return true;
}

/** 取消登录 */
export function cancelLogin(taskId) {
  const attempt = attempts.get(taskId);
  if (!attempt) return false;
  attempt.controller.abort();
  attempt.state = 'cancelled';
  attempt.prompt = null;
  attempt.resolveAnswer = null;
  attempts.delete(taskId);
  return true;
}

/** 退出登录（删掉该 provider 的凭据） */
export async function logoutProvider(providerId) {
  const id = String(providerId ?? '').trim();
  if (!id) throw new Error('缺少 provider');
  const { modelRuntime } = await servicesFor(getAgentDir());
  await modelRuntime.logout(id);
  return { provider: id };
}
