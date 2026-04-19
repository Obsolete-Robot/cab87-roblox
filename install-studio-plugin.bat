@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "SOURCE=%SCRIPT_DIR%studio-plugin\Cab87MapTools.plugin.lua"
set "TARGET_DIR=%LOCALAPPDATA%\Roblox\Plugins"
set "TARGET=%TARGET_DIR%\Cab87MapTools.plugin.lua"

if not exist "%SOURCE%" (
  echo [cab87] ERROR: plugin source not found:
  echo %SOURCE%
  exit /b 1
)

if not exist "%TARGET_DIR%" (
  mkdir "%TARGET_DIR%"
  if errorlevel 1 (
    echo [cab87] ERROR: could not create target folder:
    echo %TARGET_DIR%
    exit /b 1
  )
)

copy /Y "%SOURCE%" "%TARGET%" >nul
if errorlevel 1 (
  echo [cab87] ERROR: failed to copy plugin to:
  echo %TARGET%
  exit /b 1
)

echo [cab87] Installed plugin:
echo %TARGET%
echo [cab87] Restart Roblox Studio to load the toolbar.

endlocal
exit /b 0
