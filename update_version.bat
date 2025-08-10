@echo off
REM Version update script for Windows
REM Usage: update_version.bat <version> [build_number]
REM Example: update_version.bat 1.1.0-pre 1

if "%1"=="" (
    echo "Usage: update_version.bat ^<version^> [build_number]"
    echo "Example: update_version.bat 1.1.0-pre 1"
    exit /b 1
)

echo "Updating version number..."
call dart scripts\update_version.dart %*

if %ERRORLEVEL% EQU 0 (
    echo "Version updated successfully!"
    echo "Suggested commands to check changes:"
    echo   git diff
    echo.
    echo Commit changes after confirmation:
    echo   git add .
    echo   git commit -m "chore: bump version to %1"
) else (
    echo "Version update failed. Please check error messages."
)

pause