@echo off
setlocal
set "rules_node="
for /f "delims=" %%N in ('where node.exe 2^>nul') do if not defined rules_node set "rules_node=%%N"
if not defined rules_node set "rules_node=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
if not exist "%rules_node%" (
  echo Node.js was not found on PATH or in the Codex runtime.
  echo Install Node.js or restore the Codex runtime, then retry.
  set "rules_exit=1"
  goto finish
)
"%rules_node%" "%~dp0scripts\update-codex-rules.mjs" %*
set "rules_exit=%errorlevel%"
:finish
echo.
if "%rules_exit%"=="0" (echo Update completed.) else (echo Update failed. See the details above.)
pause
exit /b %rules_exit%
