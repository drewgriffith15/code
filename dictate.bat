@echo off
REM ============================================================
REM  VoiceDictate — Quick Launch
REM  Double-click this to start the dictation tool.
REM  A system tray icon will appear (right-click to quit).
REM ============================================================

REM Run as admin is recommended so keyboard hotkeys work in all apps
REM including UAC prompts and admin windows.

echo Starting VoiceDictate...
echo (A tray icon will appear — right-click it to quit)
echo.
py "%~dp0dictate.py"
pause
