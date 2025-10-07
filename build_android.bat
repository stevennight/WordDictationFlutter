@echo off
chcp 65001 >nul
echo ========================================
echo Flutter Android Build Script
echo ========================================
echo.

REM Check Flutter installation
echo [1/5] Checking Flutter environment...
call flutter --version
echo Flutter environment check passed
echo.

REM Check Android SDK
echo [2/5] Checking Android SDK...
if not defined ANDROID_HOME (
    echo Warning: ANDROID_HOME environment variable not set
    echo Please ensure Android SDK is properly installed and configured
) else (
    echo Android SDK path: %ANDROID_HOME%
)
echo.

REM Clean project (skip global clean to preserve other platform builds)
echo [3/5] Skipping global Flutter clean to avoid deleting non-Android builds...
echo If you need a full clean, run: flutter clean
echo.

REM Get dependencies
echo [4/5] Getting project dependencies...
call flutter pub get
echo Dependencies get completed
echo.

REM Build APK
echo [5/5] Building Android APK...
echo Building release APK, please wait...
call flutter build apk --release
echo.
echo ========================================
echo Android APK build completed!
echo ========================================
echo.
echo APK file location:
echo    build\app\outputs\flutter-apk\app-release.apk
echo.
echo File information:
if exist "build\app\outputs\flutter-apk\app-release.apk" (
    for %%A in ("build\app\outputs\flutter-apk\app-release.apk") do (
        echo    File size: %%~zA bytes
        echo    Modified time: %%~tA
    )
) else (
    echo    APK file not found
)
echo.
echo You can install the APK file to Android device for testing
echo.
pause