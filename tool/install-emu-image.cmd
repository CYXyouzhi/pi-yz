@echo off
rem 装一个 Android 系统镜像给官方模拟器用（避开 bash 到 cmd 的引号/分号转义）
set ANDROID_SDK_ROOT=E:\Android\Sdk
set ANDROID_HOME=E:\Android\Sdk
cd /d E:\Android\Sdk\cmdline-tools\latest\bin
call sdkmanager.bat "system-images;android-34;google_apis;x86_64"
echo EXITCODE=%ERRORLEVEL%
