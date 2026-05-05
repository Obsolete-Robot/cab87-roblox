@echo off
setlocal
cd /d "%~dp0"

call :ensure_node_runtime
if errorlevel 1 exit /b 1

set "NODE_ARCH=x64"
for /f "usebackq delims=" %%A in (`node -p "process.arch" 2^>nul`) do set "NODE_ARCH=%%A"

set "ROLLUP_NATIVE=node_modules\@rollup\rollup-win32-x64-msvc\package.json"
if /I "%NODE_ARCH%"=="arm64" set "ROLLUP_NATIVE=node_modules\@rollup\rollup-win32-arm64-msvc\package.json"
if /I "%NODE_ARCH%"=="ia32" set "ROLLUP_NATIVE=node_modules\@rollup\rollup-win32-ia32-msvc\package.json"

if not exist node_modules\.bin\vite.cmd (
	call :install_deps
	if errorlevel 1 exit /b 1
) else if not exist "%ROLLUP_NATIVE%" (
	echo [cab87] Windows Rollup native package is missing.
	echo [cab87] Reinstalling dependencies for this Windows Node.js runtime...
	call :install_deps
	if errorlevel 1 exit /b 1
)

if not defined CAB87_NO_BROWSER start "" "http://localhost:3000"
call npm run dev

if errorlevel 1 (
	echo [cab87] Visualizer server failed.
	pause
	exit /b 1
)

exit /b 0

:ensure_node_runtime
call :find_node_runtime
if not errorlevel 1 exit /b 0

echo [cab87] Node.js and npm were not found.
echo [cab87] Installing Node.js LTS with winget...

where winget >nul 2>nul
if errorlevel 1 (
	echo [cab87] winget was not found, so Node.js cannot be installed automatically.
	echo [cab87] Install Node.js LTS from https://nodejs.org/ and run this file again.
	pause
	exit /b 1
)

call winget install --id OpenJS.NodeJS.LTS -e --source winget --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
	echo [cab87] Node.js installation failed.
	pause
	exit /b 1
)

call :find_node_runtime
if errorlevel 1 (
	echo [cab87] Node.js was installed, but this command window cannot find node/npm yet.
	echo [cab87] Close this window and run run.bat again so Windows can refresh PATH.
	pause
	exit /b 1
)

exit /b 0

:find_node_runtime
where node >nul 2>nul
if errorlevel 1 goto try_node_install_paths

where npm >nul 2>nul
if not errorlevel 1 exit /b 0

:try_node_install_paths
if exist "%ProgramFiles%\nodejs\node.exe" if exist "%ProgramFiles%\nodejs\npm.cmd" (
	set "PATH=%ProgramFiles%\nodejs;%PATH%"
	exit /b 0
)

if exist "%ProgramFiles(x86)%\nodejs\node.exe" if exist "%ProgramFiles(x86)%\nodejs\npm.cmd" (
	set "PATH=%ProgramFiles(x86)%\nodejs;%PATH%"
	exit /b 0
)

if exist "%LOCALAPPDATA%\Programs\nodejs\node.exe" if exist "%LOCALAPPDATA%\Programs\nodejs\npm.cmd" (
	set "PATH=%LOCALAPPDATA%\Programs\nodejs;%PATH%"
	exit /b 0
)

exit /b 1

:install_deps
echo [cab87] Installing intersection visualizer dependencies...
if exist package-lock.json (
	call npm ci
) else (
	call npm install
)
if errorlevel 1 (
	echo [cab87] npm dependency install failed.
	pause
	exit /b 1
)
exit /b 0
