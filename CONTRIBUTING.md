# 怎么贡献

个人项目，没那么多规矩。下面几条是**已经被验证有用**的，不是形式要求。

## 环境

| | 要求 |
|---|---|
| Flutter | 3.47.x（stable） |
| Node | ≥ 20.6（服务端用到 `import.meta.resolve`） |
| 平台 | 主力开发在 Windows + MuMu 模拟器；CI 跑 Ubuntu |

## 跑起来

```bash
flutter pub get
flutter test                       # Flutter 侧

cd server && node --test           # 服务端侧（不需要 npm install，测试只用内置模块）
```

真机调试用 MuMu 模拟器；本机 adb 不在 PATH 时可以走
`MuMuManager.exe sh -v 0 --cmd "..."` 执行设备命令（见 `docs/threat-model.md`
里的真机验证记录）。

## 提交前必过的门禁

```bash
dart format lib test tool         # CI 会检查格式
flutter analyze                   # 期望 No issues found
flutter test                      # 期望全过（golden 也跑；CI 上跳过 golden）
```

三条都要干净。**别攒到最后** —— 一次改一大片再修，排查成本会翻几倍。

## 提交信息

中文，`type(scope): 描述`。type 用这几个（与仓库现有历史一致）：

| type | 什么时候用 |
|---|---|
| `feat` | 新功能 |
| `fix` | 修 bug |
| `perf` | 性能（APK 体积、启动速度也算） |
| `refactor` | 不改行为的重构 |
| `test` | 只动测试 |
| `docs` | 只动文档 |
| `ci` | CI / workflow |
| `chore` | 版本号、依赖、杂项 |

scope 写模块名，例如 `security` / `chat` / `apk` / `notif` / `server_store` /
`reducer/client`。真实例子：

```
feat(security): token 从连接配置里拆出来（M3 第一批：抽象层 + 迁移编排）
perf(apk): ABI split —— 真机包 56.5 MiB → 21.5 MiB（−62%）
test(server_store): 补 20 条动作层用例（未覆盖 440 → 184 行；逻辑层 76.5%）
fix(i18n): 存储占用删除确认的文案主语
```

**正文比标题重要。** 写清三件事：

1. **为什么**要改（尤其当改动看起来「多此一举」时 —— 那通常是踩过坑的痕迹）
2. 有没有**有意保留的取舍**（比如「宁可留明文也不丢 token」这类）
3. **验证方式**（跑了什么、真机测了什么、数字前后对比）

## 代码风格

- **注释用中文**，写在「为什么」上而不是「是什么」上。
  `// 递增计数` 这种没信息量；`// 服务端会拒绝删正在跑的会话（409），除非显式 force`
  才有价值。
- **踩过的坑要留下来**。发现某处写法看着多余但其实是必要的，就在旁边写清
  当年是怎么坏的 —— 否则下一个人（包括三个月后的你）会「顺手简化」掉它。
- 不引第三方依赖之前先想想自研成本。这个项目里 `shareText`、`saveImage`、
  Keystore 加密都是自己写的 MethodChannel，总共不到 200 行，
  省掉了「插件版本与 Flutter 版本打架」这一类问题。

## 测试

- **新行为要带测试**；改了已有行为，先改测试再改代码。
- 断言写在**行为契约**上，不要复述实现。反例：断言某个私有字段等于 42。
  正例：断言「没有会话时发消息，会先 POST /api/sessions 再 POST command」——
  它对应的是用户报过的「打完字点发送什么也没发生」。
- 新写的用例请做一次**负向验证**：把被测的那段逻辑破坏掉，确认用例会红，
  再改回来。不做这一步，你写的可能是个永远绿的摆设。
  （`docs/testing.md` 里有具体做法与踩过的五个坑。）

## 文档

改了行为就更新对应的文档，**只维护一处**：

| 改了什么 | 更新哪 |
|---|---|
| 安全边界 / 存储方式 | `SECURITY.md`、`docs/threat-model.md` |
| 发布流程 / 版本 | `docs/release.md` |
| 体积、架构拆分 | `docs/apk-size.md` |
| 平板 / 横屏行为 | `docs/tablet-landscape.md` |
| 测试方法 | `docs/testing.md` |
| 进度 | `ROADMAP.md`（README 不重复写） |

## 不要提交这些

```
server/.token              服务端 token（已 gitignore）
android/key.properties     keystore 口令
android/app/*.jks          签名密钥本体
server/bin/cloudflared.exe 53MB 的第三方二进制
```

签名密钥一旦进仓库，任何人都能签包冒充你更新 App。**丢了也麻烦**：
包名相同就必须同一个签名，密钥没了就再也发不了更新 —— 仓库外的离线备份
是唯一保险（见 `docs/release.md`）。
