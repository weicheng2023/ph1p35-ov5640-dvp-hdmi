@echo off
setlocal

rem TD 6.2.1 command-line build for top_ddr_debug.
rem Default: CAL_EN=1 -> top_ddr_debug.bit
rem Control: set DDR_CAL0=1 before running -> top_ddr_debug_cal0.bit
rem (CAL_EN=0 is diagnosis only; it does not prove data reliability.)
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

if defined DDR_CAL0 (
    echo Building top_ddr_debug CAL_EN=0 control...
) else (
    echo Building top_ddr_debug CAL_EN=1...
)

set "TCL_SCRIPT=%~dp0build_top_ddr_debug.tcl"
set "TCL_SCRIPT=%TCL_SCRIPT:\=/%"
"%TD_HOME%\bin\td_commands_prompt.exe" "%TCL_SCRIPT%"

echo.
if defined DDR_CAL0 (
    echo Output: %~dp0..\..\build\bitstream\top_ddr_debug_cal0.bit
) else (
    echo Output: %~dp0..\..\build\bitstream\top_ddr_debug.bit
)
pause
