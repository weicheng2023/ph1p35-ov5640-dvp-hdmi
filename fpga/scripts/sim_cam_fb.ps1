param(
    [string]$ModelSimBin = 'D:\modeltech64_2020.4\win64',
    [switch]$Full
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

function Invoke-Vsim {
    param([string]$Title, [string]$Lib, [string]$Top, [string[]]$Opts)
    Write-Host "=== $Title"
    $log = "$Title.log"
    & "$ModelSimBin/vsim.exe" -c -voptargs=+acc -onfinish stop -lib work @Opts $Top -l $log -do 'run -all; quit -f'
    if ($LASTEXITCODE -ne 0 -or
        !(Select-String (Join-Path $Lib $log) -Pattern 'TB: PASS' -Quiet) -or
        (Select-String (Join-Path $Lib $log) -Pattern 'TB: FAIL|\*\* Fatal:' -Quiet)) {
        throw "Regression failed: $log"
    }
}

# ---------------------------------------------------------------------------
# Capture unit test
# ---------------------------------------------------------------------------
$capLib = Join-Path $repo 'build/sim_cam_cap'
New-Item -ItemType Directory -Force $capLib | Out-Null
Push-Location $capLib
try {
    if (!(Test-Path work)) { & "$ModelSimBin/vlib.exe" work }
    & "$ModelSimBin/vlog.exe" -sv -work work `
        (Join-Path $repo 'fpga/rtl/camera/ov5640_frame_capture.v') `
        (Join-Path $repo 'fpga/sim/tb/tb_ov5640_frame_capture.v')
    if ($LASTEXITCODE -ne 0) { throw 'capture compile failed' }

    $capCases = @(
        @('cap_basic',        @()),
        @('cap_href_low',     @('-gHREF_ACTIVE_HIGH=0')),
        @('cap_pad',          @('-gV_ACTIVE=5', '-gCAM_LINES=4')),
        @('cap_long_line',    @('-gV_ACTIVE=5', '-gCAM_LINES=4', '-gLONG_LINE=1')),
        @('cap_window_640',   @('-gCAP_START=640')),
        @('cap_byte_swap',    @('-gSWAP=1')),
        @('cap_buf_busy',     @('-gBUF_FREE_OFF=1')),
        @('cap_combined',     @('-gV_ACTIVE=5', '-gCAM_LINES=4', '-gCAP_START=640',
                                '-gSWAP=1', '-gLONG_LINE=1'))
    )
    foreach ($c in $capCases) {
        Invoke-Vsim -Title $c[0] -Lib $capLib -Top 'tb_ov5640_frame_capture' -Opts $c[1]
    }
} finally { Pop-Location }

# ---------------------------------------------------------------------------
# Integration test (camera -> DDR ping-pong -> HDMI)
# ---------------------------------------------------------------------------
$intLib = Join-Path $repo 'build/sim_cam_fb'
New-Item -ItemType Directory -Force $intLib | Out-Null
Push-Location $intLib
try {
    if (!(Test-Path work)) { & "$ModelSimBin/vlib.exe" work }
    $sources = @(
        'rtl/common/async_fifo_gray.v', 'rtl/camera/ov5640_frame_capture.v',
        'rtl/fb/cam_fb_writer.v', 'rtl/fb/cam_fb_reader.v',
        'rtl/fb/cam_fb_hdmi_core.v', 'rtl/ddr/ddr_axi_pattern_test.v',
        'rtl/ddr/pixel_gearbox.v', 'rtl/display/video_timing.v',
        'rtl/display/rgb565_to_rgb888.v', 'rtl/display/tmds_encoder.v',
        'rtl/display/tmds_serializer.v', 'rtl/display/serial_load_gen.v',
        'sim/models/pll_hdmi_sim.v', 'sim/models/ph1p_logic_oddr_sim.v',
        'sim/models/ddr_axi_slave_model.v', 'sim/tb/tb_cam_fb_hdmi_core.v'
    ) | ForEach-Object { Join-Path $repo "fpga/$_" }
    & "$ModelSimBin/vlog.exe" -sv -work work @sources
    if ($LASTEXITCODE -ne 0) { throw 'integration compile failed' }

    Invoke-Vsim -Title 'int_quick'    -Lib $intLib -Top 'tb_cam_fb_hdmi_core' -Opts @()
    Invoke-Vsim -Title 'int_pressure' -Lib $intLib -Top 'tb_cam_fb_hdmi_core' -Opts @('-gREADY_DELAY=2')

    if ($Full) {
        Invoke-Vsim -Title 'int_full_640x480' -Lib $intLib -Top 'tb_cam_fb_hdmi_core' -Opts @(
            '-gH_ACTIVE=640', '-gV_ACTIVE=480', '-gCAM_LINES=480',
            '-gFRAME_STRIDE=307200', '-gTOTAL_BEATS=38400', '-gPREFILL=192')
    }
} finally { Pop-Location }

Write-Host 'All Stage 3 simulations passed.'
