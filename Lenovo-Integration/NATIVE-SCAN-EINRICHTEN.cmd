@echo off
chcp 65001 >nul
title Engels Kueche - Native Scan Verbindung
cd /d "%~dp0"
py -3 "%~dp0NATIVE-SCAN-EINRICHTEN.py"
if errorlevel 1 (
  echo.
  echo Bitte die Fehlermeldung beachten. Keine Rezeptdaten wurden veraendert.
)
echo.
pause
