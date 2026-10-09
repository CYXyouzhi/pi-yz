#!/usr/bin/env bash
# pi-yz-server 启动脚本（Linux / macOS）。
#
# 与 start.cmd 等价，前台运行、Ctrl+C 停止。
#
#   --host 0.0.0.0   监听所有网卡，手机才连得进来
#                    （只在本机用就删掉这个参数，默认只监听 127.0.0.1）
#
# token 不写死在这里，也不传 --token：服务端首次启动会生成一个 192 bit 的随机
# token 写进 .token，之后每次启动复用它 —— 既强，又不会每次重启都变（手机不用重配）。
# 想看 token：cat .token
# 想自己指定：./start.sh --token 你的值
#
# 其余参数（--port / --default-cwd / --no-pair / --tunnel）见 README.md。
set -euo pipefail
cd "$(dirname "$0")"

exec node index.mjs --host 0.0.0.0 "$@"
