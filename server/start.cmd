@echo off
chcp 65001 > nul
cd /d "%~dp0"

REM pi-yz-server 启动脚本（前台运行，关窗口即停止）
REM
REM   --host 0.0.0.0   监听所有网卡，手机/模拟器才能连进来
REM                     （只在本机用就改成 127.0.0.1）
REM   --token          手机端要填同一个值
REM
REM 启动后会打印：监听地址、token。手机端在「连接」里填 IP + 端口 + token。

REM token 不再写死在脚本里。
REM
REM 原因（这也是一个安全问题）：原来的 `set TOKEN=piyz2026` 是「项目名 + 年份」，
REM 而这个项目是开源的 —— 猜中成本几乎为零。而且这个文件一旦提交，token 就跟着公开了。
REM
REM 现在的行为：不传 --token 时，服务端首次启动会生成一个强随机 token（192 bit）
REM 写进 server/.token，之后每次启动复用它 —— 既强，又不会每次重启都变（手机不用重配）。
REM
REM 想看 token：type .token（就在本目录）
REM 想自己指定：给下面的命令加 --token 你的值

echo.
echo   pi-yz-server
echo   ---------------------------------------------
echo   按 Ctrl+C 停止
echo.

node index.mjs --host 0.0.0.0

echo.
echo   服务端已退出。
pause
