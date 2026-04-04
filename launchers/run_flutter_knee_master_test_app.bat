@echo off
setlocal

cd /d "%~dp0\..\mobile\knee_master_test_app"

echo [1/3] Generating Android project files if needed...
flutter create --platforms=android --org com.kesav.kneerehab .
if errorlevel 1 goto :end

echo [2/3] Restoring Flutter packages...
flutter pub get
if errorlevel 1 goto :end

echo [3/3] Launching on the selected device...
flutter run

:end
endlocal
