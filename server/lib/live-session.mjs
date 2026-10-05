// LiveSession：一条活跃会话的包装。
//
// 职责：
//   - 持有 AgentSession
//   - 把 pi 的原始事件裁剪后广播给所有客户端连接（多设备共享同一会话）
//   - 合并高频的工具进度更新
//   - 命令分派

import { toClientEvent, isDroppable, isNestedToolEvent } from './wire.mjs';
import { executeCommand } from './commands.mjs';
import { createExtensionUIContext } from './extension-ui.mjs';

// 工具进度合并窗口：每条 update 携带的是完整 partial result，中间态无意义。
// 实测一次 11MB 的对话，大头就在这里。
const TOOL_UPDATE_COALESCE_MS = 150;

export class LiveSession {
  #listeners = new Set();
  #pendingToolUpdates = new Map();
  #toolUpdateTimer = null;
  #unsubscribe;
  #disposed = false;

  constructor({ session, cwd, info }) {
    this.session = session;
    this.cwd = cwd;
    this.info = info ?? null;
    this.lastActivity = Date.now();
    this.createdAt = Date.now();

    // 扩展 UI 桥接：对话框请求会作为事件广播到手机端，
    // 客户端回应后由 resolveUiRequest 唤醒等待中的扩展
    this.ui = createExtensionUIContext({ emit: (request) => this.#emit(request) });

    this.#unsubscribe = session.subscribe((event) => this.#handleRawEvent(event));
  }

  /**
   * 注入扩展运行时上下文。必须在第一次 prompt 之前完成，否则扩展的
   * ctx.ui 是空的，一调用就崩。
   */
  async bind() {
    try {
      await this.session.bindExtensions({
        uiContext: this.ui.context,
        // 'rpc' 表示“非终端，但有对话框能力”：扩展会据此跳过 TUI 专有功能
        mode: 'rpc',
        commandContextActions: {
          waitForIdle: () => this.session.waitForIdle(),
          reload: () => this.session.reload(),
          // 以下四个需要 AgentSessionRuntime（会话替换机制），当前未接入。
          // 给出明确错误而不是让扩展碰到 undefined。
          newSession: async () => {
            throw new Error('手机端暂不支持从扩展命令新建会话');
          },
          fork: async () => {
            throw new Error('手机端暂不支持从扩展命令创建分支');
          },
          navigateTree: async () => {
            throw new Error('手机端暂不支持会话树跳转');
          },
          switchSession: async () => {
            throw new Error('手机端暂不支持从扩展命令切换会话');
          },
        },
        shutdownHandler: () => this.#emit({ type: 'session_shutdown' }),
        onError: (error) => this.#emit({
          type: 'extension_error',
          extensionPath: error?.extensionPath,
          event: error?.event,
          error: String(error?.error ?? error),
        }),
      });
    } catch (error) {
      console.error(`[live] 扩展绑定失败（${this.id}）:`, error?.message ?? error);
    }
  }

  /** 手机端回应扩展对话框 */
  resolveUiRequest(id, response) {
    return this.ui.resolve(id, response);
  }

  get id() {
    return this.session.sessionId;
  }

  get isStreaming() {
    return this.session.isStreaming;
  }

  get isAlive() {
    return !this.#disposed;
  }

  /** 订阅裁剪后的事件流。返回退订函数。 */
  subscribe(listener) {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  get listenerCount() {
    return this.#listeners.size;
  }

  /** 标记活动时间，用于空闲回收 */
  touch() {
    this.lastActivity = Date.now();
  }

  #emit(event) {
    // 复制一份再遍历：订阅者可能在回调里退订（比如连接断开）
    for (const listener of [...this.#listeners]) {
      try {
        listener(event);
      } catch (error) {
        console.error('[live] 事件投递失败:', error);
      }
    }
  }

  #handleRawEvent(rawEvent) {
    this.touch();

    // 会话被关闭（例如 /new 或 fork 替换了会话）
    if (rawEvent.type === 'session_shutdown') {
      this.#flushToolUpdates();
      this.#emit({ type: 'session_shutdown' });
      return;
    }

    const event = toClientEvent(rawEvent);
    if (!event) return;

    // 嵌套工具调用（codemode 脚本里 ctx.executeTool 发起的）：
    // 只保留起止骨架，丢弃进度，避免一次脚本执行产生成百上千条更新
    if (isNestedToolEvent(event) && event.type === 'tool_execution_update') return;

    if (event.type === 'tool_execution_update') {
      this.#queueToolUpdate(event);
      return;
    }

    // 工具的结束事件会取代仍在等待的进度，且客户端若先收到进度后收到结束，
    // 会误判工具"又跑起来了"
    if (event.type === 'tool_execution_end') {
      this.#pendingToolUpdates.delete(event.toolCallId);
    } else if (event.type === 'agent_end' || event.type === 'agent_settled') {
      this.#pendingToolUpdates.clear();
    }

    this.#emit(event);
  }

  #queueToolUpdate(event) {
    this.#pendingToolUpdates.set(event.toolCallId, event);
    this.#toolUpdateTimer ??= setTimeout(() => this.#flushToolUpdates(), TOOL_UPDATE_COALESCE_MS);
  }

  #flushToolUpdates() {
    if (this.#toolUpdateTimer) {
      clearTimeout(this.#toolUpdateTimer);
      this.#toolUpdateTimer = null;
    }
    if (this.#pendingToolUpdates.size === 0) return;
    const updates = [...this.#pendingToolUpdates.values()];
    this.#pendingToolUpdates.clear();
    for (const update of updates) this.#emit(update);
  }

  /** 执行一条命令，返回给客户端的响应对象 */
  async send(command, pool) {
    this.touch();
    return executeCommand({ live: this, session: this.session, pool }, command);
  }

  /** 供背压判断：这条事件在客户端积压时能否安全丢弃 */
  static isDroppable = isDroppable;

  async dispose() {
    if (this.#disposed) return;
    this.#disposed = true;
    this.#flushToolUpdates();
    this.#listeners.clear();
    try {
      this.#unsubscribe?.();
    } catch { /* 已失效 */ }
    try {
      this.session.dispose();
    } catch (error) {
      console.error('[live] 释放会话失败:', error);
    }
  }
}
