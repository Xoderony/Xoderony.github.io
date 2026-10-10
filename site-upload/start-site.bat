@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 exit /b 1
set "WEBSHARE_ROOT=%~dp0"
if not defined WEBSHARE_PORT set "WEBSHARE_PORT=8080"
echo Local URL: http://127.0.0.1:%WEBSHARE_PORT%/
echo Keep this window open. Press Ctrl+C to stop.
dotnet ".\app\WebShare.dll"
set "SITE_EXIT=%ERRORLEVEL%"
echo Website exited with code %SITE_EXIT%.
pause
exit /b %SITE_EXIT%
