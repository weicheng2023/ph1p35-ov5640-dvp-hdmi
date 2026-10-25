@echo off
setlocal
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
set "TCL_SCRIPT=%~dp0build_top_led_test.tcl"
set "TCL_SCRIPT=%TCL_SCRIPT:\=/%"
"%TD_HOME%\bin\td_commands_prompt.exe" "%TCL_SCRIPT%"
echo.
echo Output: %~dp0..\..\build\bitstream\top_led_test.bit
pause
