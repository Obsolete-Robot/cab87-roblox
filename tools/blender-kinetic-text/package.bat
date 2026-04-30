@echo off
setlocal enabledelayedexpansion
REM Package script for the Cab87 Kinetic Text Blender add-on.
REM Builds a versioned zip from the nested cab87_kinetic_text_importer add-on folder.

cd /d "%~dp0"

set "SCRIPT_DIR=%~dp0"
set "ADDON_DIR=cab87_kinetic_text_importer"
set "SOURCE_DIR=%SCRIPT_DIR%%ADDON_DIR%"
set "FOLDER_NAME=%ADDON_DIR%"

if not exist "%SOURCE_DIR%\__init__.py" (
    echo ERROR: Addon source not found:
    echo %SOURCE_DIR%
    pause
    exit /b 1
)

REM Extract version from __init__.py (bl_info["version"] = (x, y, z)).
set "VERSION=unknown"
for /f "tokens=1,* delims=:" %%A in ('findstr /N /C:"version" "%SOURCE_DIR%\__init__.py"') do (
    if %%A LEQ 20 (
        for /f "tokens=2 delims=()" %%V in ("%%B") do (
            set "VERSION=%%V"
            set "VERSION=!VERSION: =!"
            set "VERSION=!VERSION:,=.!"
        )
    )
)

if "%VERSION%"=="unknown" (
    echo ERROR: Could not extract bl_info version from:
    echo %SOURCE_DIR%\__init__.py
    pause
    exit /b 1
)

REM Validate blender_manifest.toml version stays in sync with bl_info.
set "MANIFEST_VERSION="
if exist "%SOURCE_DIR%\blender_manifest.toml" (
    for /f "tokens=3" %%V in ('findstr /B /C:"version" "%SOURCE_DIR%\blender_manifest.toml"') do (
        set "MANIFEST_VERSION=%%~V"
    )
)

if not "%MANIFEST_VERSION%"=="" (
    if not "%MANIFEST_VERSION%"=="%VERSION%" (
        echo ERROR: Version mismatch.
        echo __init__.py version: %VERSION%
        echo manifest version:    %MANIFEST_VERSION%
        pause
        exit /b 1
    )
)

set "ZIP_NAME=%FOLDER_NAME%_v%VERSION%.zip"

echo.
echo ========================================
echo Packaging %FOLDER_NAME% v%VERSION%
echo ========================================
echo.
echo Addon source: %SOURCE_DIR%
echo Output zip:   %SCRIPT_DIR%%ZIP_NAME%
echo.

if exist "%ZIP_NAME%" (
    echo Removing existing %ZIP_NAME%...
    del "%ZIP_NAME%"
)

echo Removing __pycache__ folders...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& {$ErrorActionPreference='Stop'; $folders=Get-ChildItem -Path '%SOURCE_DIR%' -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq '__pycache__'}; if($folders){foreach($folder in $folders){Write-Host 'Removing:' $folder.FullName; Remove-Item -Path $folder.FullName -Recurse -Force}}; Write-Host 'Cleanup complete.'}"
echo.

echo Creating zip file: %ZIP_NAME%...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& {$ErrorActionPreference='Stop';try{$source='%SOURCE_DIR%';$folderName='%FOLDER_NAME%';$zipFile=Join-Path '%SCRIPT_DIR%' '%ZIP_NAME%';Write-Host 'Source directory:' $source;Write-Host 'Zip file:' $zipFile;Write-Host '';$files=@();Get-ChildItem -Path $source -Recurse -File|ForEach-Object{$relativePath=$_.FullName.Substring($source.Length).TrimStart('\');if(-not $_.Name.StartsWith('.') -and -not($relativePath -like '*\__pycache__\*') -and -not($_.Extension -eq '.bat') -and -not($_.Extension -eq '.zip') -and -not($_.Extension -eq '.md') -and -not($_.Extension -eq '.command') -and -not($_.Extension -eq '.sh')){$files+=$_}};Write-Host 'Found' $files.Count 'files to include';if($files.Count -eq 0){throw 'No files found to include in zip'};$tempZip=[System.IO.Path]::Combine([System.IO.Path]::GetTempPath(),[System.IO.Path]::GetRandomFileName()+'.zip');Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem;$zip=[System.IO.Compression.ZipFile]::Open($tempZip,[System.IO.Compression.ZipArchiveMode]::Create);try{foreach($file in $files){$relativePath=$file.FullName.Substring($source.Length).TrimStart('\');$zipPath=$folderName+'\'+$relativePath;[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$zipPath)|Out-Null}}finally{$zip.Dispose()};Move-Item -Path $tempZip -Destination $zipFile -Force;Write-Host '';Write-Host 'Zip file created successfully:' $zipFile -ForegroundColor Green}catch{Write-Host '';Write-Host 'ERROR:' $_.Exception.Message -ForegroundColor Red;if($_.ScriptStackTrace){Write-Host 'Stack trace:' $_.ScriptStackTrace};exit 1}}"
set "PS_ERROR=%ERRORLEVEL%"

echo.
echo ========================================
if %PS_ERROR% EQU 0 (
    echo Packaging Complete!
    echo ========================================
    echo.
    echo Created: %ZIP_NAME%
) else (
    echo Packaging Failed!
    echo ========================================
    echo.
    echo ERROR: Failed to create zip file
    echo Error code: %PS_ERROR%
)
echo.
echo Press any key to exit...
pause >nul
exit /b %PS_ERROR%
