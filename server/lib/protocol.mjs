// 响应协议：与 pi 的 RPC 协议保持一致。
//   { id, type:"response", command, success:true, data }
//   { id, type:"response", command, success:false, error }

export const success = (id, command, data) => ({
  id,
  type: 'response',
  command,
  success: true,
  ...(data === undefined ? {} : { data }),
});

export const failure = (id, command, error) => ({
  id,
  type: 'response',
  command,
  success: false,
  error: String(error?.message ?? error),
});

/**
 * 模型对象裁剪：客户端只需要展示信息。
 * 完整 Model 对象含端点与凭证相关字段，不该发到手机上。
 */
export function clipModel(model) {
  if (!model) return null;
  return {
    provider: model.provider,
    id: model.id,
    name: model.name ?? model.id,
    contextWindow: model.contextWindow ?? null,
    reasoning: Boolean(model.reasoning),
  };
}
