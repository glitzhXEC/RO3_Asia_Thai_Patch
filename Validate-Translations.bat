@echo off
setlocal
chcp 65001 > nul
pushd "%~dp0"
py -3 "scripts\validate-thai-payload.py"
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%
