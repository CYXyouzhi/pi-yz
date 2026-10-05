// 扩展 UI 桥接：把扩展的 ctx.ui 调用转发到手机端。
//
// 为什么必须有这一层：pi 的扩展可以随时弹对话框（比如让用户确认一条危险命令）。
// 在 SDK 模式下必须通过 session.bindExtensions({ uiContext }) 注入一套 UI 实现，
// 否则扩展的 ctx.ui 是空的，一调用就崩。
//
// 实现照抄 dist/modes/rpc/rpc-mode.js 的 createExtensionUIContext，
// 只把"写到 stdout"换成"通过 SSE 广播给手机端，等客户端回响应"。
//
// 两类方法：
//   对话框类（select/confirm/input/editor）：发请求，阻塞等响应
//   通知类（notify/setStatus/setWidget/setTitle/setEditorText）：只发不等

import { randomUUID } from 'node:crypto';

// 主题实例：扩展会用它取颜色。
//
// 必须调 initTheme()：不调的话 theme 是个未初始化的壳，
// 任何取颜色的扩展都会抛 "Theme not initialized"（实测 token-total、
// pi-token-speed 两个扩展就因此全程报错）。CLI 是在启动时初始化的，
// 我们直接用 SDK，得自己补上这一步。
let theme;
try {
  const entry = import.meta.resolve('@earendil-works/pi-coding-agent');
  const themeModule = await import(new URL('./modes/interactive/theme/theme.js', entry).href);
  themeModule.initTheme?.();
  theme = themeModule.theme;
} catch (error) {
  console.warn('[extension-ui] 主题初始化失败:', error?.message ?? error);
  theme = undefined;
}

/**
 * @param {{ emit: (request: object) => void }} options
 *        emit 把 UI 请求交给会话的事件广播（最终到达手机端）
 */
export function createExtensionUIContext({ emit }) {
  // id → { resolve(客户端响应), reject }
  const pending = new Map();

  /**
   * 对话框通用流程：登记一个待响应请求，广播出去，等客户端回。
   * 支持超时与取消信号（与 pi 的 RPC 实现一致）。
   */
  function createDialogPromise(opts, defaultValue, request, parseResponse) {
    if (opts?.signal?.aborted) return Promise.resolve(defaultValue);

    const id = randomUUID();
    return new Promise((resolve, reject) => {
      let timeoutId;
      const cleanup = () => {
        if (timeoutId) clearTimeout(timeoutId);
        opts?.signal?.removeEventListener('abort', onAbort);
        pending.delete(id);
      };
      const onAbort = () => {
        cleanup();
        resolve(defaultValue);
      };
      opts?.signal?.addEventListener('abort', onAbort, { once: true });

      // 超时由服务端处理，客户端不必自己计时
      if (opts?.timeout) {
        timeoutId = setTimeout(() => {
          cleanup();
          resolve(defaultValue);
        }, opts.timeout);
      }

      pending.set(id, {
        resolve: (response) => {
          cleanup();
          resolve(parseResponse(response));
        },
        reject,
      });

      emit({ type: 'extension_ui_request', id, ...request });
    });
  }

  const context = {
    // ---------- 对话框：需要客户端回应 ----------
    select: (title, options, opts) => createDialogPromise(
      opts,
      undefined,
      { method: 'select', title, options, timeout: opts?.timeout },
      (r) => (r.cancelled ? undefined : r.value),
    ),

    confirm: (title, message, opts) => createDialogPromise(
      opts,
      false,
      { method: 'confirm', title, message, timeout: opts?.timeout },
      (r) => (r.cancelled ? false : Boolean(r.confirmed)),
    ),

    input: (title, placeholder, opts) => createDialogPromise(
      opts,
      undefined,
      { method: 'input', title, placeholder, timeout: opts?.timeout },
      (r) => (r.cancelled ? undefined : r.value),
    ),

    // 多行编辑器：手机端用多行输入框呈现
    editor: (title, prefill) => createDialogPromise(
      undefined,
      undefined,
      { method: 'editor', title, prefill },
      (r) => (r.cancelled ? undefined : r.value),
    ),

    // ---------- 通知类：发出去就不管 ----------
    notify(message, type) {
      emit({
        type: 'extension_ui_request',
        id: randomUUID(),
        method: 'notify',
        message,
        notifyType: type,
      });
    },

    setStatus(key, text) {
      emit({
        type: 'extension_ui_request',
        id: randomUUID(),
        method: 'setStatus',
        statusKey: key,
        statusText: text,
      });
    },

    setWidget(key, content, options) {
      // 只支持纯文本行；TUI 组件工厂在手机端没有对应物
      if (content === undefined || Array.isArray(content)) {
        emit({
          type: 'extension_ui_request',
          id: randomUUID(),
          method: 'setWidget',
          widgetKey: key,
          widgetLines: content,
          widgetPlacement: options?.placement,
        });
      }
    },

    setTitle(title) {
      emit({ type: 'extension_ui_request', id: randomUUID(), method: 'setTitle', title });
    },

    setEditorText(text) {
      emit({
        type: 'extension_ui_request',
        id: randomUUID(),
        method: 'set_editor_text',
        text,
      });
    },

    // ---------- 终端专有：明确降级（与 pi 的 RPC 模式一致） ----------
    onTerminalInput() {
      return () => {};
    },
    setWorkingMessage() {},
    setWorkingVisible() {},
    setWorkingIndicator() {},
    setHiddenThinkingLabel() {},
    setFooter() {},
    setHeader() {},
    addAutocompleteProvider() {},
    setEditorComponent() {},
    getEditorComponent() {
      return undefined;
    },
    async custom() {
      return undefined;
    },
    pasteToEditor(text) {
      this.setEditorText(text);
    },
    getEditorText() {
      return '';
    },
    getToolsExpanded() {
      return false;
    },
    setToolsExpanded() {},

    // ---------- 主题：终端概念，手机端不用 ----------
    get theme() {
      return theme;
    },
    getAllThemes() {
      return [];
    },
    getTheme() {
      return undefined;
    },
    setTheme() {
      return { success: false, error: '手机端不支持切换主题' };
    },
  };

  return {
    context,
    /** 客户端回响应时调用 */
    resolve(id, response) {
      const entry = pending.get(id);
      if (!entry) return false;
      entry.resolve(response ?? {});
      return true;
    },
    get pendingCount() {
      return pending.size;
    },
  };
}
