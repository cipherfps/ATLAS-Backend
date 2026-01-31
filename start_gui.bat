@echo off
setlocal
cd /d "%~dp0atlas_gui_flutter"
"%~dp0flutter\bin\flutter.bat" run -d windows
endlocal
