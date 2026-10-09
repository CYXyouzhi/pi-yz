// chat 拆分后的**对外接口**（barrel）。
//
// 为什么要它：这一层被 40 多个地方 import（chat_page.dart、若干测试…）。拆成多个
// 文件后，若让每个调用点自己去 import 具体文件，改动面立刻铺开，而且以后挪动组件
// 位置还得再改一遍。保留一个 barrel，调用点一行都不用动。
//
// 分文件按**职责**、不按大小：
//   bars.dart           状态条与提示条（活动条 / 加载更多 / 离线横幅 / 撤销 / 通知 / 排队消息）
//   loading.dart        空态、加载中、实时速度
//   header.dart         会话页头部与模型徽标
//   composer.dart       输入区（待发图片 / 文件引用 / 候选面板）
//   message_detail.dart 回合尾（文件改动 / token / 树）与相关工具函数
//   message_area.dart   消息区与滚动按钮
//   sheets.dart         各类底部弹层（模型切换 / 输入菜单 / 会话详情 / 回合摘要）
//   dialogs.dart        确认对话框
export 'bars.dart';
export 'composer.dart';
export 'dialogs.dart';
export 'header.dart';
export 'loading.dart';
export 'message_area.dart';
export 'message_detail.dart';
export 'sheets.dart';
