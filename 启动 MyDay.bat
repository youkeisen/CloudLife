@echo off
chcp 65001 >nul
cd /d "%~dp0"
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY (where python >nul 2>nul && set "PY=python")
if not defined PY (
  echo [MyDay] Python not found. Install Python 3 and add it to PATH.
  echo [MyDay] Or edit this file and add: set "PY=D:\python\python.exe"
  pause
  exit /b 1
)
echo [MyDay] starting, please keep this window open...
%PY% "app\server.py"
echo [MyDay] stopped.
pause
