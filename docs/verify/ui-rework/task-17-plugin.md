# task-17 · 电脑端服务做成 pi 插件（已完成）

交付：`pi-plugin/` —— 一个可以直接 `pi install ./pi-plugin` 的 pi 包。

```
pi-plugin/
├── package.json                 # pi 清单：{"pi": {"extensions": ["extensions/yz-server.ts"]}}
├── extensions/yz-server.ts  # 插件本体：注册 /mobile 命令 + 一个只用于自证加载的 flag
└── lib/ctl.mjs                  # 纯 Node 的进程控制（start/stop/status/doctor/token）
```

## 命令

| 命令 | 作用 |
|---|---|
| `/mobile` | 状态：起没起、pid、监听地址、入口路径、配置与日志位置，以及**手机端该填的三行** |
| `/mobile start [端口]` | 后台拉起服务（detached + 日志落 `~/.pi/agent/pi-yz-server.log`），等 `/api/health` 通了才返回 |
| `/mobile stop` | 按 pidfile 停 |
| `/mobile doctor` | 自检：进程 / 打通 /api/health / pi 版本 / 会话数 / 端口 / 日志 |
| `/mobile token <t>` | 写配置（提示需 stop+start 生效） |

设计取舍：**服务端仍是独立 Node 进程**，插件只负责拉起/停止/探活 ——
pi 退出、切会话都不会把手机端连接带崩；反过来服务端也不会拖着 pi 进程。

## 验证（都是可复跑的）

| 项 | 证据 |
|---|---|
| ① 装得上 | `pi install ./pi-plugin` → `Installed ./pi-plugin` |
| 装完能被列出 | `pi list` → 末行 `..\..\Desktop\1\pi-yz\pi-plugin`（本机包路径） |
| 扩展真的被加载 | `pi --help` 里出现 `--yz-status  pi-yz-server：启动时打印一次服务状态` —— 这个 flag 就是这个插件注册的 |
| ② 一条命令起服务并给出连接信息 | `ctl.start({port:30199})` → `running:true, healthy:true, pid:25456`；`connectInfo` → `地址 10.1.1.195 / 端口 30199 / token plugin-test-token` |
| ③ 状态与自检 | `ctl.doctor()` → `healthy:true, sessions:246`（当时服务端会话数） |
| ④ 卸载不留残配置 | `pi remove ./pi-plugin` 后比对 `~/.pi/agent/settings.json`：**字段数 12→12、packages 完全相同、无多出/缺失字段** |
| ⑤ 与原有启动方式共存 | `doctor()` 能区分「本插件拉起的」与「start.cmd / 手动起的」：进程表里没有但端口活着时返回 `foreign:true` + 提示「`/mobile start` 不会重复拉起、`/mobile stop` 也不会去杀它」 |

## 诚实说明的缺口

- `/mobile` 这些**斜杠命令本身没有在交互式 TUI 里手点过** —— 自动化跑不了 TUI。
  命令的实现就是调用上面已经验证过的 `ctl.mjs`；加载则有 `--help` 的 flag 为证。
- 插件默认假设服务端入口在 `pi-plugin/../server/index.mjs`（本仓库结构），
  换位置时用配置项 `serverEntry` 或环境变量 `PI_YZ_SERVER_ENTRY` 覆盖。
- 测试用的端口/token 已改回正式值（`30142` / `piyz2026`，与 `server/start.cmd` 一致）。
