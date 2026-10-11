@echo off
setlocal
set "PACTICK_BUNDLE=%~dp0"
if not exist "%PACTICK_BUNDLE%bin\server.exe" set "PACTICK_BUNDLE=%~dp0..\..\"
where pwsh.exe >nul 2>nul
if errorlevel 1 goto windows_powershell
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%PACTICK_BUNDLE%deploy\desktop\run-server.ps1" -BundleDir "%PACTICK_BUNDLE%." %*
exit /b %errorlevel%
:windows_powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PACTICK_BUNDLE%deploy\desktop\run-server.ps1" -BundleDir "%PACTICK_BUNDLE%." %*
exit /b %errorlevel%
