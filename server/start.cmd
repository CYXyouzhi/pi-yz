@echo off
chcp 65001 > nul
cd /d "%~dp0"

REM pi-mobile-server 启动脚本（前台运行，关窗口即停止）
REM
REM   --host 0.0.0.0   监听所有网卡，手机/模拟器才能连进来
REM                     （只在本机用就改成 127.0.0.1）
REM   --token          手机端要填同一个值
REM
REM 启动后会打印：监听地址、token。手机端在「连接」里填 IP + 端口 + token。

set TOKEN=pimobile2026

echo.
echo   pi-mobile-server
echo   ---------------------------------------------
echo   按 Ctrl+C 停止
echo.

node index.mjs --host 0.0.0.0 --token %TOKEN%

echo.
echo   服务端已退出。
pause
