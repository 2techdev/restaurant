@echo off
setlocal

rem -----------------------------------------------------------------------
rem Bootstrap the GastroCore monorepo.
rem   - Activates melos (if missing)
rem   - Runs melos bootstrap to wire every workspace package's path deps
rem -----------------------------------------------------------------------

pushd "%~dp0.."

where melos >nul 2>nul
if errorlevel 1 (
  echo ==^> Activating melos globally...
  dart pub global activate melos
  if errorlevel 1 goto :fail
)

echo ==^> Running melos bootstrap...
call melos bootstrap
if errorlevel 1 goto :fail

echo ==^> Bootstrap complete.
popd
endlocal
exit /b 0

:fail
echo ==^> Bootstrap FAILED.
popd
endlocal
exit /b 1
