@echo off
setlocal
set "SNAPIK_EXE=%~dp0artifacts\publish\Snapik.exe"
if not exist "%SNAPIK_EXE%" (
  echo Snapik is not built. Run scripts\build.ps1 first.
  exit /b 1
)
start "" "%SNAPIK_EXE%"
endlocal

