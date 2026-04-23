@echo off
setlocal
cd /d "%~dp0"

where py >nul 2>nul
if not errorlevel 1 (
	start "" "http://127.0.0.1:8000/index.html"
	py -3 -m http.server 8000
	goto :eof
)

where python >nul 2>nul
if not errorlevel 1 (
	start "" "http://127.0.0.1:8000/index.html"
	python -m http.server 8000
	goto :eof
)

echo [cab87] Python was not found. Opening the static file directly instead.
start "" "%~dp0index.html"
