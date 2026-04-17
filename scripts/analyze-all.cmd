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

echo ==^> Running melos run analyze across all workspace packages...
call melos run analyze
if errorlevel 1 goto :fail

echo ==^> Analyze complete.
popd
endlocal
exit /b 0

:fail
echo ==^> Analyze FAILED.
popd
endlocal
exit /b 1
