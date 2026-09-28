@echo off
setlocal EnableExtensions DisableDelayedExpansion
call "%~dp0Recover-Thai.bat" "%~1" --after-repair "%~2"
exit /b %ERRORLEVEL%
