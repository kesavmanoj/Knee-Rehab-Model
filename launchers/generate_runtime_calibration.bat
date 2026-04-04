@echo off
cd /d "%~dp0\.."
py -3 tools\calibration\generate_runtime_calibration.py
