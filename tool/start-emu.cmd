@echo off
cd /d E:\Android\Sdk\emulator
start "" emulator.exe -avd piyz -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect
