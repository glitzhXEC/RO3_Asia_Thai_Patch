@echo off
setlocal
chcp 65001 > nul
pushd "%~dp0"

echo ========================================================
echo   RO3 Asia Thai Translation Validator
echo ========================================================
echo.
echo The legacy Japanese generator is disabled in the Thai repository.
echo Edit the split workspace and tracked Client payload together.
echo.
py -3 "scripts\validate-thai-payload.py"
set "RC=%ERRORLEVEL%"

popd
exit /b %RC%
