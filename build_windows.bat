@echo off
echo Building Windows executable...
echo.

echo Getting project dependencies...
flutter pub get
echo.

echo Starting Windows build...
flutter build windows --release
echo.

if %ERRORLEVEL% EQU 0 (
    echo Build successful!
    echo Executable location: build\windows\x64\runner\Release\flutter_word_dictation.exe
    echo.
    echo Open build directory? (Y/N)
    set /p choice="Please choose: "
    if /i "%choice%"=="Y" (
        explorer build\windows\x64\runner\Release
    )
) else (
    echo Build failed, please check error messages.
)

echo.
echo Press any key to exit...
pause >nul