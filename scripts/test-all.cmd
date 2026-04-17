@echo off
setlocal

pushd "%~dp0.."

where melos >nul 2>nul
if errorlevel 1 (
  echo ==^> melos not found. Run scripts\bootstrap.cmd first.
  popd
  endlocal
  exit /b 1
)

echo ==^> Running melos run test across all packages with tests...
call melos run test
if errorlevel 1 goto :fail

echo ==^> Tests complete.
popd
endlocal
exit /b 0

:fail
echo ==^> Tests FAILED.
popd
endlocal
exit /b 1
