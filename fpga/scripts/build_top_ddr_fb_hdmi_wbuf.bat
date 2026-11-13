@echo off
setlocal

rem EXPERIMENTAL TD 6.2.1 build: Stage 2 DDR frame buffer -> HDMI test image
rem with the registered 128-bit word-buffer pixel gearbox.
rem Separate output files; the board-proven
rem top_ddr_fb_hdmi_paxi_fix_20261109.bit is NOT overwritten.
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

echo Building top_ddr_fb_hdmi_wbuf...
rem TD's Tcl interpreter treats backslashes as escapes; pass forward slashes.
set "TCL_SCRIPT=%~dp0build_top_ddr_fb_hdmi_wbuf.tcl"
set "TCL_SCRIPT=%TCL_SCRIPT:\=/%"
"%TD_HOME%\bin\td_commands_prompt.exe" "%TCL_SCRIPT%"

echo.
echo Output: %~dp0..\..\build\bitstream\top_ddr_fb_hdmi_wbuf_20261109.bit
pause
