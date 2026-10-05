// 会话池：管理当前"活着"的会话。
//
// 为什么需要池：pi 的 AgentSession 是进程内对象，创建一个要读设置、发现资源、
// 加载扩展（实测约 1 秒）。手机端每次打开会话都重建太浪费，所以按 id 缓存，
// 空闲后回收。

import { createAgentSession, SessionManager } from '@earendil-works/pi-coding-agent';
import { existsSync, statSync } from 'node:fs';
import { LiveSession } from './live-session.mjs';
import { resolveSessionMeta } from './sessions.mjs';

// 空闲回收时长：手机端断开后服务端不该一直占着会话。
// 比 pi-web 默认的 10 分钟长，因为手机切后台/锁屏更频繁。
const IDLE_TIMEOUT_MS = 30 * 60 * 1000;
const REAP_INTERVAL_MS = 60 * 1000;

export class SessionPool {
  #live = new Map(); // id → LiveSession
  #reaper = null;

  /**
   * 打开一条已有会话。已在池中则直接返回。
   * @param {string} id 会话 id（不是文件路径）
   */
  async open(id) {
    const existing = this.#live.get(id);
    if (existing?.isAlive) return existing;

    const { path, cwd } = await resolveSessionMeta(id);
    const sessionManager = SessionManager.open(path);
    const { session, modelFallbackMessage } = await createAgentSession({ sessionManager, cwd });

    const live = new LiveSession({ session, cwd, info: { id, path } });
    await live.bind(); // 注入扩展 UI 上下文，必须在首次 prompt 之前
    if (modelFallbackMessage) {
      console.warn(`[pool] 会话 ${id} 模型回退: ${modelFallbackMessage}`);
    }
    this.#live.set(live.id, live);
    console.log(`[pool] 打开会话 ${live.id} (cwd=${cwd}, 池内 ${this.#live.size})`);
    return live;
  }

  /**
   * 新建一条会话。
   * @param {string} cwd 工作目录，必须是已存在的目录
   */
  async create(cwd) {
    const target = cwd || process.cwd();
    if (!existsSync(target) || !statSync(target).isDirectory()) {
      throw new Error(`工作目录不存在或不是目录: ${target}`);
    }

    // 先释放池里那些“没说过话”的空会话。
    // 实测：用户连点 10 次「新会话」，池里就真的堆了 10 个空会话。
    for (const [id, live] of [...this.#live]) {
      const isEmpty = live.session.messages.length === 0;
      if (isEmpty && !live.isStreaming && live.listenerCount === 0) {
        await live.dispose();
        this.#live.delete(id);
      }
    }

    const sessionManager = SessionManager.create(target);
    const { session } = await createAgentSession({ sessionManager, cwd: target });
    const live = new LiveSession({ session, cwd: target, info: null });
    await live.bind(); // 注入扩展 UI 上下文，必须在首次 prompt 之前
    this.#live.set(live.id, live);
    console.log(`[pool] 新建会话 ${live.id} (cwd=${target}, 池内 ${this.#live.size})`);
    return live;
  }

  /** 取池中的活会话；不存在或已死返回 null */
  get(id) {
    const live = this.#live.get(id);
    if (!live) return null;
    if (!live.isAlive) {
      this.#live.delete(id);
      return null;
    }
    return live;
  }

  /** 池内会话概览（调试用） */
  list() {
    return [...this.#live.values()].filter((live) => live.isAlive).map((live) => ({
      id: live.id,
      cwd: live.cwd,
      isStreaming: live.isStreaming,
      listeners: live.listenerCount,
      idleMs: Date.now() - live.lastActivity,
    }));
  }

  /**
   * 带细节的活跃会话：多会话总览要回答「哪个在跑、跑到哪、花了多少」。
   *
   * 这些数都从会话自己的消息里现算，不做第二本账 ——
   * 记一份额外账本迟早会跟消息对不上，而消息是唯一权威。
   */
  listDetailed() {
    const now = Date.now();
    return this.list().map((row) => {
      const live = this.#live.get(row.id);
      const messages = live?.session?.messages ?? [];
      let outputTokens = 0;
      let cost = 0;
      let title = '';
      let lastAction = '';
      let lastMessageAt = 0;
      for (const msg of messages) {
        if (msg?.role === 'user' && !title) title = textOfMessage(msg).slice(0, 60);
        const usage = msg?.usage;
        if (usage) {
          outputTokens += Number(usage.output ?? 0);
          cost += Number(usage.cost?.total ?? 0);
        }
        const at = Number(msg?.timestamp ?? 0);
        if (at > lastMessageAt) lastMessageAt = at;
        for (const call of msg?.toolCalls ?? []) {
          if (call?.name) lastAction = call.name;
        }
      }
      return {
        ...row,
        title,
        messageCount: messages.length,
        outputTokens,
        cost,
        lastAction,
        lastMessageAt,
        startedAt: live?.createdAt ?? 0,
        runningMs: live ? now - live.createdAt : 0,
      };
    });
  }

  async dispose(id) {
    const live = this.#live.get(id);
    this.#live.delete(id);
    if (live) await live.dispose();
  }

  startIdleReaper() {
    if (this.#reaper) return;
    this.#reaper = setInterval(() => {
      void this.#reap();
    }, REAP_INTERVAL_MS);
    this.#reaper.unref?.();
  }

  async #reap() {
    const now = Date.now();
    for (const [id, live] of [...this.#live]) {
      if (!live.isAlive) {
        this.#live.delete(id);
        continue;
      }
      // 有客户端连着就不回收——手机可能只是暂时没在发消息
      if (live.listenerCount > 0) continue;
      // 正在运行也不回收，否则会把用户的回答掐断
      if (live.isStreaming) continue;
      if (now - live.lastActivity < IDLE_TIMEOUT_MS) continue;

      console.log(`[pool] 回收空闲会话 ${id}（空闲 ${Math.round((now - live.lastActivity) / 1000)}s）`);
      await live.dispose();
      this.#live.delete(id);
    }
  }

  async disposeAll() {
    if (this.#reaper) {
      clearInterval(this.#reaper);
      this.#reaper = null;
    }
    await Promise.all([...this.#live.values()].map((live) => live.dispose()));
    this.#live.clear();
  }
}

/** 从 pi 的消息里抠出纯文本（content 可能是字符串，也可能是内容块数组） */
function textOfMessage(msg) {
  const c = msg?.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) {
    return c
      .filter((x) => x?.type === 'text' && typeof x.text === 'string')
      .map((x) => x.text)
      .join(' ');
  }
  return '';
}
