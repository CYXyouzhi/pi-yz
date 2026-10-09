# 发布流程

配套：[docs/apk-size.md](apk-size.md)（产物体积与「用户该装哪个」）·
[SECURITY.md](../SECURITY.md)（密钥为什么要这么绕）

## 一、一次性配置：把签名密钥交给 CI

签名材料不能在仓库里（`key.properties` 是口令、`*.jks` 是密钥本体，
一旦公开任何人都能签包冒充你更新 App）。所以走 Secrets：
CI 构建前还原、构建后随 runner 一起销毁。

**先确认这两个文件在**：

```bash
ls android/key.properties android/app/pi-yz-release.jks
```

**再设两个 Secret**（本机装了 `gh` 的话，两条命令搞定）：

```bash
cd <仓库根目录>

# 1) jks 本体（base64 之后才能放进 Secret）
gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 -w0 android/app/pi-yz-release.jks)

# 2) key.properties 全文
gh secret set ANDROID_KEY_PROPERTIES < android/key.properties

# 核对（只列名字，不显示值）
gh secret list
```

没有 `gh` 就在网页上设：仓库 → Settings → Secrets and variables → Actions →
New repository secret，名字用上面那两个。

> `base64 -w0` 的 `-w0` 是「不换行」—— 有换行的 base64 在 CI 里 `base64 -d` 会失败。

**密钥要留好备份**：`key.properties` + `pi-yz-release.jks` 丢了，就用同一个包名发不了
更新（Android 只认同一个签名）。仓库外的备份（压缩包、离线盘）是唯一保险。

## 二、发一个版本

```bash
# 1) 改版本号（tag 会和它比对，不一致会直接失败）
#    pubspec.yaml: version: 0.3.0+3
git commit -am "chore: 版本 0.3.0"

# 2) 打 tag 并推上去 —— 这一步就是「发布」的动作
git tag v0.3.0
git push origin main --tags
```

推 tag 会触发 `.github/workflows/release.yml`：

```
校验 tag 与 pubspec 版本一致  ← 不一致直接失败（不然包内版本与 Release 页对不上）
      ↓
检查 Secrets 是否齐全
      ↓
还原签名材料 → 构建（--split-per-abi + universal）
      ↓
改名 → 上传 workflow artifact（总是）
      ↓
创建 Release + 挂 4 个 APK（仅当有签名）
```

**补发**：Actions 页面手动跑 Release，`tag` 填 `v0.3.0`。
**只想构建、不发布**：手动跑，`tag` 留空 —— 产物在 workflow 的 artifact 里。

## 三、产物命名

```
pi-yz-0.3.0-arm64-v8a.apk      ← 2017 年之后的手机（绝大多数）
pi-yz-0.3.0-armeabi-v7a.apk    ← 更老的手机
pi-yz-0.3.0-x86_64.apk         ← 模拟器
pi-yz-0.3.0-universal.apk      ← 不确定架构的人（大 2.6 倍）
```

四个都传，缺了 universal 的话「不知道自己手机什么架构」的人就没得装。
体积与选择理由见 [apk-size.md](apk-size.md)。

## 四、没有配 Secret 会怎样（刻意的行为）

**照常构建、上传 artifact，但不创建 Release。**

因为 `build.gradle.kts` 在没有 `key.properties` 时会退回 **debug 签名**，
而 debug 签名的包发出去之后，用户装了**后续版本再也覆盖不上**：
Android 只允许同签名的包升级，签名不一致会直接拒绝安装。

用户看到的会是「下载了新版本，装的时候说『应用未安装』」，而且他没有办法自救
（除非卸载重装，丢掉全部配置）。所以宁可只留构建产物，也不发这种包。
CI 日志里会有明确的 `::warning::`。

## 五、本地手动发（不走 CI）

CI 挂了或想本地出包时：

```bash
flutter analyze && flutter test        # 门禁先过
flutter build apk --release --split-per-abi
flutter build apk --release
```

产物在 `build/app/outputs/flutter-apk/`。本地能跑通签名是因为
`android/key.properties` 与 `.jks` 都在本机（它们只是不进版本库）。
