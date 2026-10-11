@echo off
setlocal
set "PACTICK_BUNDLE=%~dp0"
if not exist "%PACTICK_BUNDLE%bin\manager.exe" set "PACTICK_BUNDLE=%~dp0..\..\"
"%PACTICK_BUNDLE%bin\manager.exe" --bundle-dir "%PACTICK_BUNDLE%." %*
exit /b %errorlevel%
