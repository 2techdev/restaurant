@echo off
REM ===========================================================================
REM  GastroCore POS - Android release APK build
REM ===========================================================================
REM  Produces: apps\pos\build\app\outputs\flutter-apk\app-pos-release.apk
REM
REM  Requirements:
REM    * Flutter SDK on PATH (tested with 3.9.2)
REM    * Android SDK + build-tools installed
REM    * JDK 17 on PATH (for keytool)
REM    * apps\pos\android\key.properties present (else falls back to debug
REM      signing - fine for internal sideload, NOT for Play Store)
REM
REM  For production release:
REM    1. Rotate the pilot keystore BEFORE uploading to Play Store.
REM       See apps\pos\android\key.properties.template.
REM    2. Store the real .jks in 1Password / Vault - losing it breaks
REM       future Play Store updates forever.
REM ===========================================================================

setlocal ENABLEDELAYEDEXPANSION

REM Resolve repo root from this script's location (scripts\..)
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.." >nul
set "REPO_ROOT=%CD%"
popd >nul

set "POS_DIR=%REPO_ROOT%\apps\pos"
set "KEY_PROPS=%POS_DIR%\android\key.properties"
set "APK_OUT=%POS_DIR%\build\app\outputs\flutter-apk\app-pos-release.apk"

echo ============================================================
echo  Building GastroCore POS release APK
echo  Repo: %REPO_ROOT%
echo ============================================================

if not exist "%KEY_PROPS%" (
  echo [warn] key.properties not found at %KEY_PROPS%
  echo [warn] Release build will fall back to DEBUG signing.
  echo [warn] For signed release, run apps\pos\android\scripts\generate-keystore.sh
  echo [warn] then copy key.properties.template to key.properties.
)

pushd "%POS_DIR%" >nul

echo.
echo [1/3] flutter clean
call flutter clean || goto :fail

echo.
echo [2/3] flutter pub get
call flutter pub get || goto :fail

echo.
echo [3/3] flutter build apk --flavor pos --release
call flutter build apk --flavor pos --release || goto :fail

popd >nul

if not exist "%APK_OUT%" (
  echo.
  echo [error] Build reported success but APK not found at:
  echo         %APK_OUT%
  exit /b 1
)

echo.
echo ============================================================
echo  Build SUCCESS
echo  APK: %APK_OUT%
for %%F in ("%APK_OUT%") do echo  Size: %%~zF bytes
echo ============================================================
exit /b 0

:fail
popd >nul 2>&1
echo.
echo [error] Build FAILED - see output above.
exit /b 1
