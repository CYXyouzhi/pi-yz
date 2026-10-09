# APK 体积

## 结论

| 产物 | 体积 | 相比 universal |
|---|---|---|
| `app-armeabi-v7a-release.apk` | 19.21 MiB | **−66%** |
| `app-arm64-v8a-release.apk` | **21.51 MiB** | **−62%** |
| `app-x86_64-release.apk` | 22.92 MiB | −59% |
| `app-release.apk`（universal） | 56.52 MiB | — |

（另有 `app-debug.apk` 158.53 MiB —— 只用于真机调试，**不发布**。）

构建环境：Flutter 3.47.5 stable · 命令 `flutter build apk --release --split-per-abi`

## 为什么能省这么多

一个 release APK 里，**每个 ABI 都各自带一整套原生库**：

```
lib/x86_64/libflutter.so       13.1 MB   ┐
lib/x86_64/libapp.so            7.1 MB   │
lib/arm64-v8a/libflutter.so    11.7 MB   │
lib/arm64-v8a/libapp.so         6.9 MB   ├─ 55.1 MB
lib/armeabi-v7a/libflutter.so   8.6 MB   │
lib/armeabi-v7a/libapp.so       7.7 MB   ┘
res/ + assets/ + classes.dex     4.1 MB
```

一台 arm64 手机只会加载 arm64 那两份，**另外 36.8 MB 纯属陪跑**。

`--split-per-abi` 就是按架构拆成三个包：设备需要的那份一份不少，不需要的一份不带。

没有手写 Gradle 的 `splits { abi { … } }` 块 —— Flutter 的 `--split-per-abi` 会顺带
处理 versionCode（自动加 ABI 偏移，build.gradle.kts 里有注释），比手写少一个出错点。

## 怎么构建

```bash
flutter build apk --release --split-per-abi   # 三个分架构包（发布用）
flutter build apk --release                   # universal（给不确定架构的人）
```

## 发布时传哪几个包

三个分架构包**都要传**（Releases 页面），外加一个 universal 兜底 ——
不然「不知道自己手机是什么架构」的人就没得装。命名用默认的即可，
下载者看文件名就能对上。

## 用户该装哪个

| 设备 | 装 |
|---|---|
| 2017 年之后的手机（绝大多数） | `arm64-v8a` |
| 更老的手机 | `armeabi-v7a` |
| 模拟器（x86 主机） | `x86_64` |
| 不确定 | universal |

装错架构不会「装上去才发现」：系统在安装时就直接拒绝，报「架构不兼容」。

## 已经生效、不用你操心的优化

- **MaterialIcons 字体 tree-shaking**：构建日志里能看到
  `reducing it from 1645184 to 1600 bytes (99.9% reduction)` ——
  Flutter 只把代码里真正用到的图标打进字体，没用到的整块丢
- **Dart 的 AOT + tree shaking**：`libapp.so` 里只有可达代码

## 还能再省的方向（这次没做）

| 方向 | 大概能省 | 为什么没做 |
|---|---|---|
| 开 R8（`isMinifyEnabled`） | 1–2 MiB | Java/Kotlin 侧的反射调用可能被削掉，要逐个插件验证 |
| `--obfuscate --split-debug-info` | 0.5–1 MiB | 崩溃栈要拿符号表还原，排查成本上升 |
| 资源压缩 / 清掉没用到的 res | < 1 MiB | 手动维护，收益低 |
| 改成 App Bundle（`.aab`） | 与 split 同量级 | 由商店分发，自己发 APK 用不上 |

收益已经从 56.5 掉到 21.5 MiB，再抠 1–2 MiB 性价比不高，而每条都有引入问题的风险。

## 真机验证

x86_64 包在 MuMu（Android 15）上实测：

```
pm install app-x86_64-release.apk  → Success
primaryCpuAbi=x86_64                ← 装对了架构
versionName=0.2.0
pidof → 5604                        ← 进程活着
logcat 里 FATAL EXCEPTION 条数 → 0
```
