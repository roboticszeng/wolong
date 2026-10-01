@echo off
setlocal
pushd "%~dp0"
if not exist ".tools\godot\4.7.2\Godot_v4.7.2-stable_win64.exe" (
  echo Godot 4.7.2 was not found in .tools\godot\4.7.2.
  pause
  exit /b 1
)
start "Wolong Editor" ".tools\godot\4.7.2\Godot_v4.7.2-stable_win64.exe" --editor --path "%~dp0game"
popd
