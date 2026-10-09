#!/usr/bin/env bash
# 在 MuMu 模拟器上验证「token 存进 Android Keystore」这条链，并把原始输出打出来。
#
# ## 为什么要做成脚本，而不是把结论写进文档
#
# 这件事的本质是「设备上那几个文件里到底有什么」。事后写在文档里的表格没法自证 ——
# 只能重跑一遍。做成脚本之后：任何装了 MuMu 的机器上执行
# `bash tool/verify-keystore-migration.sh` 都能复现，而且输出是**原始命令的回显**，
# 不是谁写的结论。审计要的正是这个。
#
# 脚本只做验证与打印，不改仓库里任何代码；但它对被验证的**设备**有副作用
# （装卸 App、改 prefs、换 host），所以请只在测试用的模拟器上跑。
#
# ## 用法
#
#   bash tool/verify-keystore-migration.sh
#
#   可选环境变量：
#     MUMU_MANAGER   MuMuManager.exe 路径（默认按常见安装位置找）
#     MUMU_SHARE     MuMu 共享文件夹在 Windows 侧的路径
#     SKIP_BUILD=1   不重新构建 debug 包（默认会构建，保证验的是当前代码）
#     PORT           假服务端端口（默认 18099）
#
# ## 验的是什么
#
#   ① 旧版本留下的明文 token 会被迁移走：连接配置里不再有明文、密文文件出现
#   ② 那段密文能**被正确解密**：把 host 指向一台记录式假服务端，它收到的
#      Authorization 必须正是当初那个 token
#   ③ 换机场景（密文在、Keystore 密钥已被重置）不崩：进程活着、无 FATAL、token 为空
#
# run-as 只对 debuggable 的包有效，所以全程用 debug 包。
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PKG=com.youzhi.piyz.pi_yz
DATA=/data/data/$PKG
# 端口：默认挑一个空闲的。
# 为什么不写死：被别的东西占着时，新实例 bind 失败、而探测会命中旧那个，
# 结果是「假服务端已就绪」的假象 + 请求全被旧服务端吃掉 + 日志写到别处 ——
# 断言只会说「App 没发请求」，排查半天。实测踩到过一次（上一轮遗留的实例）。
pick_free_port() {
  local p i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    p=$(( (RANDOM % 2000) + 18000 ))
    if ! netstat -ano 2>/dev/null | grep -q ":$p "; then echo "$p"; return 0; fi
  done
  echo 18099
}
PORT="${PORT:-$(pick_free_port)}"

MM="${MUMU_MANAGER:-}"
if [ -z "$MM" ]; then
  for candidate in \
    "/d/ruanjian/MuMuPlayer/nx_main/MuMuManager.exe" \
    "/c/Program Files/Netease/MuMuPlayer-12.0/nx_main/MuMuManager.exe"; do
    [ -x "$candidate" ] && MM="$candidate" && break
  done
fi
SHARE="${MUMU_SHARE:-/d/Documents/MuMu共享文件夹/Download}"
TMP="${TMPDIR:-/tmp}/piyz-verify"
mkdir -p "$TMP" "$SHARE"

# 同一个目录的 **Windows 风格**路径。
# 为什么要单独算一个：`/tmp/...` 这种 MSYS 虚拟路径传给 Windows 版 python 会找不到
# 文件 —— MSYS 的自动路径转换只对**部分**程序生效（node 认，python 不认）。
# bash 自己用 $TMP，交给 python 的用 $WIN_TMP。
WIN_TMP="$(cd "$TMP" && pwd -W 2>/dev/null || echo "$TMP")"

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ✓ $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
step() { echo; echo "─────────────────────────────── $1"; }

# 设备内执行（把原始输出原样打出来）
dev() { "$MM" sh -v 0 --cmd "$1" 2>&1; }
# 静默取一行
devq() { "$MM" sh -v 0 --cmd "$1" 2>/dev/null | tr -d '\r' | head -1; }

# 把共享目录里的文件送进 App 私有目录（需要 run-as）。
#
# ⚠️ 引号写法不能改：
#   · 外层用 **单引号**（bash 原样传递，不展开变量）
#   · 管道与重定向交给设备 shell，内层用 **双引号**
# 写成「内层单引号」在真机上会**静默不生效**：MuMuManager 的 --cmd 在 Windows
# 上传参时会把内层单引号吃掉，命令根本没送到设备 —— 而不报错，只是什么都没发生。
# （第一轮手敲验证时用的是双引号，躲过了这个坑；写成脚本后踩到，白跑一轮才定位。）
push_to_app() {
  "$MM" sh -v 0 --cmd 'cat /sdcard/Download/'"$1"' | run-as '$PKG' sh -c "mkdir -p '"$DATA"'/shared_prefs; cat > '"$DATA"'/shared_prefs/'"$2"'"' 2>&1
}

echo "pi-yz · M3 真机验证：token 迁移到 Android Keystore"
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "MuMuManager: $MM"
echo "包名: $PKG   假服务端端口: $PORT"

step "① 环境"
if [ ! -x "$MM" ]; then
  echo "找不到 MuMuManager.exe —— 用 MUMU_MANAGER=/路径/到/MuMuManager.exe 指定"
  exit 2
fi
echo "Android 版本: $(devq 'getprop ro.build.version.release')（API $(devq 'getprop ro.build.version.sdk')）"
echo "设备型号: $(devq 'getprop ro.product.model')"
if ! devq "pidof $PKG" >/dev/null; then :; fi

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  step "构建 debug 包（run-as 只对 debuggable 的包有效）"
  (cd "$REPO" && flutter build apk --debug 2>&1 | tail -2)
fi
APK="$REPO/build/app/outputs/flutter-apk/app-debug.apk"
if [ ! -f "$APK" ]; then
  bad "没有 $APK —— 去掉 SKIP_BUILD 重新构建"
  exit 2
fi
cp "$APK" "$SHARE/piyz-verify-debug.apk"
SIZE=$(ls -l "$APK" | awk '{print $5}')
echo "debug 包: $SIZE 字节，已放到共享目录"

step "安装（先卸载，签名与 release 包不同）"
dev "pm uninstall $PKG" | head -1
dev "pm install /sdcard/Download/piyz-verify-debug.apk" | tail -1
echo "debuggable: $(devq "dumpsys package $PKG | grep -c 'DEBUGGABLE'")（1 表示可 run-as）"

step "② 注入「旧版本留下的明文 token」（模拟从 0.2.0 升级上来）"
TOKEN="MIGRATION-TOKEN-$RANDOM-$RANDOM"

# 关键：先启动一次，让 App 自己把 /data/data/<pkg>/shared_prefs 建出来。
# 为什么不靠脚本 mkdir：MuMu 上实测 run-as 上下文里新建这个目录不可靠（命令静默
# 不生效）；而**真实场景里目录本来就存在** —— 用户装过旧版本、存过连接配置。
# 先跑一次反而更贴近要模拟的情形。
#
# 这个顺序也是第一轮手敲验证时无意中走的（先装 App、跑过，再注入），所以当时一切
# 正常；写成脚本后把顺序「优化」掉就翻车了。
dev "am start -n $PKG/.MainActivity" | head -1
sleep 10
dev "am force-stop $PKG" | head -1
echo "shared_prefs 现有文件数: $(devq "run-as $PKG ls $DATA/shared_prefs/ 2>/dev/null | wc -l")"

echo "本次用的 token: $TOKEN"
echo "（每次随机：若有缓存或残留，grep 就不会命中，避免假绿）"

cat > "$SHARE/piyz-old-prefs.xml" <<EOF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="flutter.server_profiles_v1">[{"id":"p1","name":"verify","host":"10.1.1.195","port":$PORT,"token":"$TOKEN"}]</string>
</map>
EOF

dev "mkdir -p $DATA/shared_prefs"
printf '\n--- 注入：%s\n' "piyz-old-prefs.xml → shared_prefs/FlutterSharedPreferences.xml"
push_to_app piyz-old-prefs.xml FlutterSharedPreferences.xml
echo "--- 注入后的连接配置（应当能看到明文 token）---"
dev "run-as $PKG cat $DATA/shared_prefs/FlutterSharedPreferences.xml"
if dev "run-as $PKG cat $DATA/shared_prefs/FlutterSharedPreferences.xml" | grep -q "$TOKEN"; then
  ok "注入成功：连接配置里确实有明文 token"
else
  bad "注入失败：连接配置里找不到明文 token"
fi

step "③ 启动 App（迁移就发生在 ServerProfileStore.loadAll 里）"
dev "am force-stop $PKG" | head -1
sleep 1
dev "am start -n $PKG/.MainActivity" | head -1
sleep 14
dev "am force-stop $PKG" | head -1

echo "--- shared_prefs 目录 ---"
dev "run-as $PKG ls -la $DATA/shared_prefs/"

echo "--- ① 连接配置（明文应当已消失）---"
PROFILES=$(dev "run-as $PKG cat $DATA/shared_prefs/FlutterSharedPreferences.xml")
echo "$PROFILES"
if echo "$PROFILES" | grep -q "$TOKEN"; then
  bad "明文 token 仍在连接配置里 —— 迁移没发生"
else
  ok "连接配置里已经没有明文 token"
fi

echo "--- ② 密文文件（应当是 base64，看不到 token 本身）---"
DEVICE_SECRETS=$(dev "run-as $PKG cat $DATA/shared_prefs/pi_yz_secure_tokens.xml")
echo "$DEVICE_SECRETS"
if echo "$DEVICE_SECRETS" | grep -q "t_p1"; then
  ok "出现了密文条目 t_p1"
else
  bad "没有 pi_yz_secure_tokens.xml 或没有 t_p1 —— 没写进 Keystore 路径"
fi
if echo "$DEVICE_SECRETS" | grep -q "$TOKEN"; then
  bad "密文文件里居然有明文 token"
else
  ok "密文文件里找不到明文 token"
fi

step "④ 密文能否被正确解密：让 App 带着它去请求一台记录式假服务端"
cat > "$TMP/fake-server.py" <<'PYEOF'
import http.server, socketserver, pathlib, sys
LOG = pathlib.Path(sys.argv[2])
PORT = int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def _h(self):
        with LOG.open('a', encoding='utf-8') as f:
            f.write(f'{self.command} {self.path} auth={self.headers.get("Authorization", "(无)")}\n')
        body = b'{"ok":true,"piVersion":"1.0.4","activeSessions":0}'
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    do_GET = do_POST = do_DELETE = do_PATCH = _h
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('0.0.0.0', PORT), H) as s:
    s.serve_forever()
PYEOF

rm -f "$TMP/hits.txt"
(python -u "$WIN_TMP/fake-server.py" "$PORT" "$WIN_TMP/hits.txt" > "$TMP/fake-server.log" 2>&1 &)
sleep 4
# 注意这里**不用 curl 探端口**：探到通只能说明「有人在 18099 上应答」，
# 而那可能不是我们起的那个实例。要看的是我们自己的启动日志。
if grep -q "listening on $PORT" "$TMP/fake-server.log" 2>/dev/null; then
  echo "  假服务端已就绪（自己的日志里确认了 listening）"
else
  echo "  ✗ 假服务端没起来（或端口被别的东西占着）—— 下面是它的输出"
  cat "$TMP/fake-server.log" 2>/dev/null | head -8
fi
echo "假服务端: $(head -1 "$TMP/fake-server.log" 2>/dev/null || echo '(启动输出为空)')（$PORT）"

# 把 host 改成宿主地址，且**故意不带 token** —— 若 App 还能发出正确的 Bearer，
# 那只能是从密文里解出来的
HOST_IP=$(ipconfig 2>/dev/null | grep -oE '10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+' | head -1)
echo "宿主地址: $HOST_IP"
cat > "$SHARE/piyz-new-prefs.xml" <<EOF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="flutter.server_profiles_v1">[{"id":"p1","name":"verify","host":"$HOST_IP","port":$PORT}]</string>
</map>
EOF
push_to_app piyz-new-prefs.xml FlutterSharedPreferences.xml
echo "--- 改好之后的连接配置（里面没有 token）---"
dev "run-as $PKG cat $DATA/shared_prefs/FlutterSharedPreferences.xml"

dev "am force-stop $PKG" | head -1
sleep 1
dev "am start -n $PKG/.MainActivity" | head -1
sleep 14

echo "--- 假服务端收到的请求 ---"
cat "$TMP/hits.txt" 2>/dev/null | head -6
if grep -q "auth=Bearer $TOKEN" "$TMP/hits.txt" 2>/dev/null; then
  ok "服务端收到了 Bearer $TOKEN —— 密文被正确解密，且配置里没 token"
else
  bad "没收到正确的 Bearer（说明密文没解出来，或 App 没去请求）"
fi

step "⑤ 换机场景：密文在、Keystore 密钥已重置"
dev "run-as $PKG cat $DATA/shared_prefs/pi_yz_secure_tokens.xml" > "$TMP/backup-secrets.xml"
dev "run-as $PKG cat $DATA/shared_prefs/FlutterSharedPreferences.xml" > "$TMP/backup-profiles.xml"
cp "$TMP/backup-secrets.xml" "$SHARE/piyz-backup-secrets.xml"
cp "$TMP/backup-profiles.xml" "$SHARE/piyz-backup-profiles.xml"
echo "已备份密文与配置（就是上面那两份）"

dev "pm uninstall $PKG" | head -1
dev "pm install /sdcard/Download/piyz-verify-debug.apk" | tail -1
echo "重装完成 —— 此时 Keystore 里的密钥与加密时那把已经不是同一把"

push_to_app piyz-backup-secrets.xml pi_yz_secure_tokens.xml
push_to_app piyz-backup-profiles.xml FlutterSharedPreferences.xml

rm -f "$TMP/hits.txt"
dev "am start -n $PKG/.MainActivity" | head -1
sleep 14

echo "进程: $(devq "pidof $PKG")（有值 = 还活着）"
FATAL=$(dev "logcat -d -t 500 | grep -cE 'FATAL EXCEPTION|AndroidRuntime'")
echo "崩溃日志条数: $FATAL"
echo "--- 假服务端收到的请求（token 解不开，应当是空的）---"
cat "$TMP/hits.txt" 2>/dev/null | head -4

if [ -n "$(devq "pidof $PKG")" ]; then
  ok "解密失败没有把 App 弄崩"
else
  bad "App 进程不在了 —— 解密失败把它弄崩了"
fi
if [ "$FATAL" = "0" ]; then
  ok "logcat 里没有 FATAL EXCEPTION"
else
  bad "logcat 里有 $FATAL 条 FATAL EXCEPTION"
fi
if grep -q "auth=Bearer $TOKEN" "$TMP/hits.txt" 2>/dev/null; then
  bad "换机后居然还能用旧密文 —— 那密钥根本没被重置，这步验证没意义"
else
  ok "旧密文解不开（符合预期），App 退化成「没有 token」而不是猜一个"
fi

step "结果"
echo "通过 $PASS 项，失败 $FAIL 项"
if [ "$FAIL" -eq 0 ]; then
  echo "PASS —— M3 的真机迁移链是通的"
  exit 0
else
  echo "FAIL —— 有 $FAIL 项没通过，往上翻看原始输出"
  exit 1
fi
