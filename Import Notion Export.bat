@echo off
setlocal

cd /d "%~dp0"

if not exist "scripts\import-notion.ps1" (
  echo Cannot find scripts\import-notion.ps1
  echo Please keep this launcher in the repository root.
  pause
  exit /b 1
)

if not exist "inbox" (
  mkdir "inbox"
)

set "ZIP_FILE="
for /f "delims=" %%F in ('dir /b /a-d /o-d "inbox\*.zip" 2^>nul') do (
  set "ZIP_FILE=inbox\%%F"
  goto :found_zip
)

:found_zip
if "%ZIP_FILE%"=="" (
  echo No .zip file found in inbox.
  echo.
  echo Please export from Notion as "Markdown & CSV",
  echo put the exported .zip into:
  echo %CD%\inbox
  echo.
  pause
  exit /b 1
)

echo Importing latest Notion export:
echo %ZIP_FILE%
echo.

set "TAGS="
set /p "TAGS=Tags (optional, press Enter to skip): "
echo.

set "UPLOAD="
set /p "UPLOAD=Commit and push automatically? (y/N): "
echo.

set "EXTRA_ARGS=-NoPush"
if /i "%UPLOAD%"=="y" (
  set "EXTRA_ARGS="
)

if "%TAGS%"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\scripts\import-notion.ps1" -Source "%CD%\%ZIP_FILE%" %EXTRA_ARGS%
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\scripts\import-notion.ps1" -Source "%CD%\%ZIP_FILE%" -Tags "%TAGS%" %EXTRA_ARGS%
)

echo.
if errorlevel 1 (
  echo Import failed. Please check the error message above.
) else (
  echo Import finished.
)
pause
