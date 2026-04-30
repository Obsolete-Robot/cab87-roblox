@echo off
setlocal
cd /d "%~dp0"

where npm >nul 2>nul
if errorlevel 1 (
	echo [cab87] npm was not found. Install Node.js, then run this file again.
	pause
	exit /b 1
)

if not exist node_modules\.bin\vite.cmd (
	echo [cab87] Installing intersection visualizer dependencies...
	call npm install
	if errorlevel 1 (
		echo [cab87] npm install failed.
		pause
		exit /b 1
	)
)

start "" "http://localhost:3000"
call npm run dev

if errorlevel 1 (
	echo [cab87] Visualizer server failed.
	pause
	exit /b 1
)
