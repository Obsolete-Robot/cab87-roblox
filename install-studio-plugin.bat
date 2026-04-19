@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PLUGIN_SRC_DIR=%SCRIPT_DIR%studio-plugin"
set "TARGET_DIR=%LOCALAPPDATA%\Roblox\Plugins"

if not exist "%PLUGIN_SRC_DIR%" (
  echo [cab87] ERROR: plugin source folder not found:
  echo %PLUGIN_SRC_DIR%
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

set "COPIED=0"
for %%F in (Cab87MapTools.plugin.lua Cab87RoadCurveTools.plugin.lua) do (
  set "SRC=%PLUGIN_SRC_DIR%\%%F"
  set "DST=%TARGET_DIR%\%%F"
  if exist "!SRC!" (
    copy /Y "!SRC!" "!DST!" >nul
    if errorlevel 1 (
      echo [cab87] ERROR: failed to copy %%F
      exit /b 1
    )
    echo [cab87] Installed plugin: %%F
    set /a COPIED+=1
  ) else (
    echo [cab87] WARNING: missing plugin file %%F
  )
)

if "%COPIED%"=="0" (
  echo [cab87] ERROR: no plugin files were installed.
  exit /b 1
)

echo [cab87] Done. Restart Roblox Studio to load plugin updates.

endlocal
exit /b 0
