param([string]$ModelSimBin = 'D:\modeltech64_2020.4\win64')
# ============================================================================
# sim_ddr_fb_wbuf.ps1
#
# ModelSim regression for the EXPERIMENTAL registered word-buffer gearbox
# (pixel_gearbox_wbuf) in ddr_fb_hdmi_core. Also re-runs the default
# (USE_WBUF=0) integration case so the parameterised core is proven
# unchanged.
#
# The FULL_CHECK cases compare every active pixel against fb_pattern at the
# pixel position entering the TMDS encoder (pipe_hcount/pipe_vcount). They
# would catch a word-boundary duplication or one-word shift even inside a
# flat colour bar.
#
# Logs: build/sim_ddr_fb_wbuf/
# ============================================================================
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sim = Join-Path $repo 'build/sim_ddr_fb_wbuf'
New-Item -ItemType Directory -Force $sim | Out-Null
$sources = @(
    'rtl/ddr/ddr_axi_pattern_test.v', 'rtl/ddr/fb_pattern.v',
    'rtl/ddr/crc32_16.v', 'rtl/ddr/fb_writer.v', 'rtl/ddr/fb_reader.v',
    'rtl/ddr/pixel_gearbox.v', 'rtl/ddr/pixel_gearbox_wbuf.v',
    'rtl/common/async_fifo_gray.v',
    'rtl/display/video_timing.v', 'rtl/display/rgb565_to_rgb888.v',
    'rtl/display/tmds_encoder.v', 'rtl/display/tmds_serializer.v',
    'rtl/display/serial_load_gen.v', 'sim/models/pll_hdmi_sim.v',
    'sim/models/ph1p_logic_oddr_sim.v', 'sim/models/ddr_axi_slave_model.v',
    'rtl/fb/ddr_fb_hdmi_core.v', 'sim/tb/tb_ddr_fb_hdmi_core.v'
) | ForEach-Object { Join-Path $repo "fpga/$_" }
Push-Location $sim
try {
    if (!(Test-Path work)) { & "$ModelSimBin/vlib.exe" work }
    & "$ModelSimBin/vlog.exe" -sv -work work @sources
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    $cases = @(
        @('frame_ref',              'tb_ddr_fb_hdmi_core'),
        @('frame_ref_full',         'tb_ddr_fb_hdmi_core','-gFULL_CHECK=1'),
        @('frame_wbuf',             'tb_ddr_fb_hdmi_core','-gUSE_WBUF=1'),
        @('frame_wbuf_full',        'tb_ddr_fb_hdmi_core','-gUSE_WBUF=1','-gFULL_CHECK=1'),
        @('frame_wbuf_pressure',    'tb_ddr_fb_hdmi_core','-gUSE_WBUF=1','-gREADY_DELAY=2'),
        @('frame_wbuf_ddr_source',  'tb_ddr_fb_hdmi_core','-gUSE_WBUF=1','-gDDR_PROOF=1'),
        @('frame_wbuf_underflow',   'tb_ddr_fb_hdmi_core','-gUSE_WBUF=1','-gFIFO_FAULT=1'),
        @('frame_wbuf_corrupt',     'tb_ddr_fb_hdmi_core','-gUSE_WBUF=1','-gCORRUPT=1')
    )
    foreach ($case in $cases) {
        $log = "$($case[0]).log"
        $top = $case[1]
        $opts = @($case | Select-Object -Skip 2)
        & "$ModelSimBin/vsim.exe" -c -onfinish stop -lib work @opts $top -l $log -do 'run -all; quit -f'
        if ($LASTEXITCODE -ne 0 -or !(Select-String $log -Pattern 'TB: PASS' -Quiet) -or
            (Select-String $log -Pattern 'TB: FAIL|\*\* Fatal:|\*\* Error:' -Quiet)) {
            throw "Regression failed: $log"
        }
        Write-Host "PASS $($case[0])"
    }
} finally { Pop-Location }
