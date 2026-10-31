@echo off
setlocal
set "DORM_ENGINE=%~dp0..\Godot4.3\Godot_v4.3-stable_win64.exe"
if not exist "%DORM_ENGINE%" (
  echo Godot 4.3 was not found in the sibling Godot4.3 folder.
  echo Open project.godot in your installed Godot 4.3 editor and press F5.
  pause
  exit /b 1
)
if not exist "%~dp0.godot\editor" (
  "%DORM_ENGINE%" --headless --editor --path "%~dp0." --import --quit
  "%DORM_ENGINE%" --headless --editor --path "%~dp0." --import --quit
)
start "Dorm Life" "%DORM_ENGINE%" --path "%~dp0."
endlocal
