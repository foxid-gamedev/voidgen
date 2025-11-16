@echo off
REM ===============================
REM Voidgen Build Script for Windows
REM Usage: build.bat [debug|release|clean] [static|dynamic]
REM Defaults: debug static
REM ===============================

REM Parse arguments
set BUILD_TYPE=%1
if "%BUILD_TYPE%"=="" set BUILD_TYPE=debug

set LIB_MODE=%2
if "%LIB_MODE%"=="" set LIB_MODE=static

REM Set directories
set BUILD_DIR=export
set DEBUG_DIR=%BUILD_DIR%\debug
set RELEASE_DIR=%BUILD_DIR%\release

REM Clean option
if /i "%BUILD_TYPE%"=="clean" (
    echo Cleaning build directories...
    rmdir /s /q "%BUILD_DIR%"
    echo Done!
    exit /b 0
)

REM Determine target directories
if /i "%BUILD_TYPE%"=="debug" (
    set OUT_DIR=%DEBUG_DIR%
    set FLAGS=-debug
) else (
    set OUT_DIR=%RELEASE_DIR%
    set FLAGS=-o:speed
)

REM Create output directory if not exists
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

REM Determine library build mode
if /i "%LIB_MODE%"=="dynamic" (
    set LIB_BUILD_MODE=-build-mode:dll
    set LIB_EXT=.dll
    set LIB_LINK_EXT=
) else (
    set LIB_BUILD_MODE=-build-mode:lib
    set LIB_EXT=.lib
    set LIB_LINK_EXT=-extra-linker-flags:%OUT_DIR%\voidgen.lib
)

REM ===============================
REM 1. Build voidgen library
REM ===============================
echo Building Voidgen library (%BUILD_TYPE%, %LIB_MODE%)...

odin build voidgen -file %LIB_BUILD_MODE% %FLAGS% -out:%OUT_DIR%\voidgen%LIB_EXT%
if errorlevel 1 (
    echo Failed to build voidgen library!
    exit /b 1
)

REM ===============================
REM 2. Build application linking voidgen
REM ===============================
echo Building application (%BUILD_TYPE%)...

odin build app -file -build-mode:exe %FLAGS% %LIB_LINK_EXT% -out:%OUT_DIR%\voidgen_app.exe
if errorlevel 1 (
    echo Failed to build application!
    exit /b 1
)

REM ===============================
REM 3. Copy DLL to app directory if dynamic
REM ===============================
if /i "%LIB_MODE%"=="dynamic" (
    echo Copying voidgen.dll to app output directory...
    copy /Y "%OUT_DIR%\voidgen.dll" "%OUT_DIR%\voidgen_app.exe"
)

echo.
echo Build finished successfully! Output in %OUT_DIR%