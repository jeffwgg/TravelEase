@echo off
setlocal
rem Native asset hooks require a space-free SDK path on Windows.
set "SDK_PATH=%~dp0.fvm\flutter_sdk"
if not exist "%SDK_PATH%\bin\flutter.bat" (
  echo Missing project SDK. Run fvm install from mobile first. 1>&2
  exit /b 1
)
for %%I in ("%SDK_PATH%") do set "SDK_PATH=%%~sI"
echo(%SDK_PATH%| findstr /C:" " >nul
if not errorlevel 1 (
  echo Install the pinned Flutter SDK in a path without spaces; Windows short names are unavailable. 1>&2
  exit /b 1
)
call "%SDK_PATH%\bin\flutter.bat" %*
exit /b %errorlevel%