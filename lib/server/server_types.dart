// 与服务端通信的协议类型。
//
// 对应 pi-yz-server 的接口：
//   GET  /api/sessions                  会话列表
//   POST /api/sessions                  新建会话
//   GET  /api/sessions/:id/events       SSE 事件流
//   POST /api/sessions/:id/command      命令
//   POST /api/sessions/:id/ui-response  扩展对话框回应

export 'types/messages.dart';
export 'types/session.dart';
export 'types/files.dart';
export 'types/usage.dart';
export 'types/config.dart';
export 'types/pool.dart';
