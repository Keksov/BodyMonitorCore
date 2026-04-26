@echo off
setlocal

set "ROOT_FPC_HOME=%~dp0..\..\VendorsCore\fpc\fpc-main"
set "ROOT_FPC_BIN=%ROOT_FPC_HOME%\bin\x86_64-win64"
set "ROOT_FPC_UNITS=%ROOT_FPC_HOME%\units\x86_64-win64"
set "CFG_FILE=%~dp0fpc-x64.cfg"

set "FPC=%ROOT_FPC_BIN%\fpc.exe"
if defined FPC_EXE_x64 (
    set "FPC=%FPC_EXE_x64%"
)
if not exist "%FPC%" (
    echo ERROR: FPC compiler not found.
    echo   Expected: %FPC%
    exit /b 1
)

if not exist "%CFG_FILE%" (
    echo ERROR: FPC config not found.
    echo   Expected: %CFG_FILE%
    exit /b 1
)

echo Using FPC: %FPC%
if not exist "%ROOT_FPC_BIN%\ppcx64.exe" (
    echo ERROR: FPC backend not found: %ROOT_FPC_BIN%\ppcx64.exe
    exit /b 1
)

if not exist "%ROOT_FPC_UNITS%\rtl\system.ppu" (
    echo ERROR: FPC RTL units not found: %ROOT_FPC_UNITS%\rtl\system.ppu
    exit /b 1
)

set "PATH=%ROOT_FPC_BIN%;%PATH%"

pushd "%~dp0"
if errorlevel 1 exit /b 1

set "MINDWAVE_VENDOR_ROOT=..\..\VendorsCore\MindWave"
set "MINDWAVE_THINKGEAR_DLL=%MINDWAVE_VENDOR_ROOT%\thinkgear64.dll"
set "MINDWAVE_ALGO_DLL=%MINDWAVE_VENDOR_ROOT%\AlgoSdkDll64.dll"
set "MINDWAVE_DOWNLOAD_SCRIPT=%MINDWAVE_VENDOR_ROOT%\scripts\win_sdk_download.bat"

if "%~1"=="clean" (
    echo Cleaning build artifacts...
    if exist build\x64\dcu del /Q build\x64\dcu\* 2>nul
    if exist build\x64\BodyMonitor.exe del /Q build\x64\BodyMonitor.exe
    if exist build\x64\thinkgear64.dll del /Q build\x64\thinkgear64.dll
    if exist build\x64\AlgoSdkDll64.dll del /Q build\x64\AlgoSdkDll64.dll
    if exist build\x64\simpleble-c.dll del /Q build\x64\simpleble-c.dll
    if exist build\x64\simpleble.dll del /Q build\x64\simpleble.dll
    echo Done.
    popd
    exit /b 0
)

if not exist build\x64\dcu mkdir build\x64\dcu

"%FPC%" -n @fpc-x64.cfg BodyMonitor.pas
if %ERRORLEVEL% neq 0 (
    echo BUILD FAILED
    popd
    exit /b %ERRORLEVEL%
)

if not exist "%MINDWAVE_THINKGEAR_DLL%" (
    echo ERROR: NeuroSky runtime DLL not found.
    echo   Expected: %MINDWAVE_THINKGEAR_DLL%
    echo   Run %MINDWAVE_DOWNLOAD_SCRIPT% first.
    popd
    exit /b 1
)

if not exist "%MINDWAVE_ALGO_DLL%" (
    echo ERROR: NeuroSky runtime DLL not found.
    echo   Expected: %MINDWAVE_ALGO_DLL%
    echo   Run %MINDWAVE_DOWNLOAD_SCRIPT% first.
    popd
    exit /b 1
)

copy /Y "%MINDWAVE_THINKGEAR_DLL%" build\x64\ >nul
if errorlevel 1 (
    echo ERROR: Failed to copy %MINDWAVE_THINKGEAR_DLL% into build\x64\
    popd
    exit /b 1
)

copy /Y "%MINDWAVE_ALGO_DLL%" build\x64\ >nul
if errorlevel 1 (
    echo ERROR: Failed to copy %MINDWAVE_ALGO_DLL% into build\x64\
    popd
    exit /b 1
)

if exist simpleble-c.dll copy /Y simpleble-c.dll build\x64\ >nul
if exist simpleble.dll copy /Y simpleble.dll build\x64\ >nul

popd
echo.
echo Build successful: build\x64\BodyMonitor.exe