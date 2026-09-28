@echo off
REM ============================================================
REM  SADINhub live dashboard
REM  Double-click this file. It starts the server and opens the
REM  dashboard in your browser. Close this black window to stop.
REM ============================================================
title SADINhub live dashboard
cd /d "%~dp0"

set PY=..\ML_WORK\.venv\Scripts\python.exe
if not exist "%PY%" (
  echo.
  echo   Could not find the project Python at:
  echo     %~dp0%PY%
  echo.
  echo   That virtual environment is the one with psycopg installed.
  echo   If it moved, edit the PY= line at the top of this file.
  echo.
  pause
  exit /b 1
)

echo.
echo   Starting the SADINhub dashboard...
echo   The first start takes a few seconds while it counts rows.
echo.
echo   Dashboard:  http://localhost:8770
echo   To stop:    close this window, or press Ctrl-C
echo.

REM give the server a moment to bind the port, then open the browser
start "" /b cmd /c "timeout /t 6 /nobreak >nul && start http://localhost:8770"

"%PY%" serve.py

echo.
echo   The server has stopped.
pause
