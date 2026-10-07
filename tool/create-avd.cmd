@echo off
rem 建一个 AVD（Pixel 6 外形，1080x2400），供 pi-yz 逐页实测用
set ANDROID_SDK_ROOT=E:\Android\Sdk
set ANDROID_HOME=E:\Android\Sdk
cd /d E:\Android\Sdk\cmdline-tools\latest\bin
echo no | call avdmanager.bat create avd -n piyz -k "system-images;android-34;google_apis;x86_64" -d pixel_6 --force
echo EXITCODE=%ERRORLEVEL%
