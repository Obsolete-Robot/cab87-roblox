@echo off
setlocal enabledelayedexpansion
REM Publish script for the Cab87 Kinetic Text Blender add-on to all local Blender versions.
REM Handles both legacy scripts\addons and Blender 4.2+ extensions\user_default paths.

cd /d "%~dp0"

set "SCRIPT_DIR=%~dp0"
set "ADDON_DIR=cab87_kinetic_text_importer"
set "SOURCE_DIR=%SCRIPT_DIR%%ADDON_DIR%"
set "ADDON_NAME=%ADDON_DIR%"
set "EXTENSION_ID=cab87_kinetic_text_importer"

set "BLENDER_BASE_PATH=%USERPROFILE%\AppData\Roaming\Blender Foundation\Blender"
set "PUBLISHED_COUNT=0"
set "FAILED_COUNT=0"
set "SKIPPED_COUNT=0"

if not exist "%SOURCE_DIR%\__init__.py" (
    echo ERROR: Addon source not found:
    echo %SOURCE_DIR%
    pause
    exit /b 1
)

REM Prefer the extension ID from blender_manifest.toml when available.
if exist "%SOURCE_DIR%\blender_manifest.toml" (
    for /f "tokens=3" %%I in ('findstr /B /C:"id" "%SOURCE_DIR%\blender_manifest.toml"') do (
        set "EXTENSION_ID=%%~I"
    )
)

echo.
echo ========================================
echo Publishing %ADDON_NAME% Addon
echo Publishing to ALL Blender Versions
echo ========================================
echo.
echo Addon source: %SOURCE_DIR%
echo Extension ID: %EXTENSION_ID%
echo.

echo Removing local __pycache__ folders...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%SOURCE_DIR%' -Recurse -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue | ForEach-Object { Write-Host '  Removing:' $_.FullName; Remove-Item -Path $_.FullName -Recurse -Force }"
echo.

if not exist "%BLENDER_BASE_PATH%" (
    echo ERROR: Blender directory not found at:
    echo %BLENDER_BASE_PATH%
    echo.
    echo Please make sure Blender is installed.
    pause
    exit /b 1
)

for /d %%V in ("%BLENDER_BASE_PATH%\*") do (
    set "VERSION_FOLDER=%%~nxV"
    set "LEGACY_PATH=%%V\scripts\addons"
    set "EXTENSION_PATH=%%V\extensions\user_default"
    set "INSTALLED=0"

    echo.
    echo ----------------------------------------
    echo Processing Blender !VERSION_FOLDER!
    echo ----------------------------------------

    REM === Modern extensions path (Blender 4.2+) ===
    if exist "!EXTENSION_PATH!" (
        echo [Extensions] Target: !EXTENSION_PATH!\%EXTENSION_ID%

        if exist "!EXTENSION_PATH!\%EXTENSION_ID%" (
            echo [Extensions] Removing old %EXTENSION_ID%...
            rmdir /s /q "!EXTENSION_PATH!\%EXTENSION_ID%"
        )

        if exist "!LEGACY_PATH!\%ADDON_NAME%" (
            echo [Legacy] Removing duplicate at !LEGACY_PATH!\%ADDON_NAME%...
            rmdir /s /q "!LEGACY_PATH!\%ADDON_NAME%"
        )

        echo [Extensions] Copying addon files...
        xcopy /E /I /Y "%SOURCE_DIR%" "!EXTENSION_PATH!\%EXTENSION_ID%"
        if errorlevel 1 (
            echo ERROR: Failed to copy addon files
            set /a FAILED_COUNT+=1
        ) else (
            powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '!EXTENSION_PATH!\%EXTENSION_ID%' -Recurse -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force }"
            echo [Extensions] Published successfully!
            set /a PUBLISHED_COUNT+=1
            set "INSTALLED=1"
        )
    )

    REM === Legacy addons path (Blender < 4.2 or if no extensions folder) ===
    if "!INSTALLED!"=="0" (
        if exist "!LEGACY_PATH!" (
            echo [Legacy] Target: !LEGACY_PATH!\%ADDON_NAME%

            if exist "!LEGACY_PATH!\__pycache__" (
                rmdir /s /q "!LEGACY_PATH!\__pycache__"
            )
            if exist "!LEGACY_PATH!\%ADDON_NAME%" (
                echo [Legacy] Removing old %ADDON_NAME%...
                rmdir /s /q "!LEGACY_PATH!\%ADDON_NAME%"
            )

            echo [Legacy] Copying addon files...
            xcopy /E /I /Y "%SOURCE_DIR%" "!LEGACY_PATH!\%ADDON_NAME%"
            if errorlevel 1 (
                echo ERROR: Failed to copy addon files
                set /a FAILED_COUNT+=1
            ) else (
                powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '!LEGACY_PATH!\%ADDON_NAME%' -Recurse -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force }"
                echo [Legacy] Published successfully!
                set /a PUBLISHED_COUNT+=1
            )
        ) else (
            echo No addons or extensions folder found, skipping...
            set /a SKIPPED_COUNT+=1
        )
    )
)

echo.
echo ========================================
echo Publishing Summary
echo ========================================
echo.
echo Published successfully: !PUBLISHED_COUNT! version(s)
echo Failed: !FAILED_COUNT! version(s)
echo Skipped (not installed): !SKIPPED_COUNT! version(s)
echo.
echo Please restart Blender and enable the addon in:
echo Edit ^> Preferences ^> Add-ons
echo.
pause
