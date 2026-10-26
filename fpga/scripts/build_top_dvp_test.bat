@echo off
setlocal

rem TD 6.2.1 command-line build for top_dvp_test.
rem Override TD_HOME if TD is installed elsewhere.
if not defined TD_HOME (
    echo ERROR: TD_HOME is not set.
    echo Example: set TD_HOME=C:\path\to\TD_6.2.1
    pause
    exit /b 1
)

if not exist "%TD_HOME%\bin\td_commands_prompt.exe" (
    echo ERROR: td_commands_prompt.exe not found under "%TD_HOME%".
    pause
    exit /b 1
)

echo Building top_dvp_test...
rem TD's Tcl interpreter treats backslashes as escapes; pass forward slashes.
set "TCL_SCRIPT=%~dp0build_top_dvp_test.tcl"
set "TCL_SCRIPT=%TCL_SCRIPT:\=/%"
"%TD_HOME%\bin\td_commands_prompt.exe" "%TCL_SCRIPT%"

echo.
echo Output: %~dp0..\..\build\bitstream\top_dvp_test.bit
pause
