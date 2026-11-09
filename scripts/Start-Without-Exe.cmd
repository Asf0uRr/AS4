@echo off
rem Fallback launcher for when the exe files are blocked by policy. Same behaviour, uses this scripts folder's parent as the AS4 root.
rem Usage: Start-Without-Exe.cmd [-Cli | -Check | -Batch quick -Case "name"]   (no argument = GUI)
setlocal
set "AS4_ROOT=%~dp0.."
for %%I in ("%AS4_ROOT%") do set "AS4_ROOT=%%~fI"
if not exist "%AS4_ROOT%\app\Main.ps1" ( echo AS4: "%AS4_ROOT%\app\Main.ps1" not found. & pause & exit /b 2 )
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" ( echo AS4: Windows PowerShell not found. & pause & exit /b 2 )
if not "%~1"=="" ( "%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%AS4_ROOT%\app\Main.ps1" %* & goto :done )
"%PSEXE%" -NoProfile -STA -ExecutionPolicy Bypass -File "%AS4_ROOT%\app\Main.ps1" -Gui
:done
endlocal & exit /b %ERRORLEVEL%