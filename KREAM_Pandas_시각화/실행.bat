@echo off
chcp 65001 >nul
cd /d "%~dp0"
set PYTHONUTF8=1
python "코드\make_visualizations.py"
if errorlevel 1 (
  echo Python execution failed. See requirements.txt and the error above.
  pause
  exit /b 1
)
start "" "결과\시각화_모아보기.html"
pause
