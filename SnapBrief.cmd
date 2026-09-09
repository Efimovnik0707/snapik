@echo off
setlocal
set "SNAPBRIEF_EXE=%~dp0artifacts\publish\SnapBrief.exe"
if not exist "%SNAPBRIEF_EXE%" (
  echo SnapBrief is not built. Run scripts\build.ps1 first.
  exit /b 1
)
start "" "%SNAPBRIEF_EXE%"
endlocal

