param([string]$ModelSimBin = 'D:\modeltech64_2020.4\win64')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sim = Join-Path $repo 'build/sim_ddr_fb_paxi_fix'
New-Item -ItemType Directory -Force $sim | Out-Null
$sources = @(
    'rtl/ddr/ddr_axi_pattern_test.v', 'rtl/ddr/fb_pattern.v',
    'rtl/ddr/crc32_16.v', 'rtl/ddr/fb_writer.v', 'rtl/ddr/fb_reader.v',
    'rtl/ddr/pixel_gearbox.v', 'rtl/common/async_fifo_gray.v',
    'rtl/display/video_timing.v', 'rtl/display/rgb565_to_rgb888.v',
    'rtl/display/tmds_encoder.v', 'rtl/display/tmds_serializer.v',
    'rtl/display/serial_load_gen.v', 'sim/models/pll_hdmi_sim.v',
    'sim/models/ph1p_logic_oddr_sim.v', 'sim/models/ddr_axi_slave_model.v',
    'rtl/fb/ddr_fb_hdmi_core.v', 'sim/tb/tb_ddr_fb_hdmi_core.v',
    'sim/tb/tb_ddr_axi_pattern_test.v'
) | ForEach-Object { Join-Path $repo "fpga/$_" }
Push-Location $sim
try {
    if (!(Test-Path work)) { & "$ModelSimBin/vlib.exe" work }
    & "$ModelSimBin/vlog.exe" -sv -work work @sources
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
    $cases = @(
        @('normal','tb_ddr_axi_pattern_test'),
        @('pressure','tb_ddr_axi_pattern_test','-gREADY_DELAY=2'),
        @('corrupt','tb_ddr_axi_pattern_test','-gCORRUPT=1'),
        @('old_step','tb_ddr_axi_pattern_test','-gLEGACY_STEP=1'),
        @('old_mask','tb_ddr_axi_pattern_test','-gLEGACY_MASK=1'),
        @('frame_normal','tb_ddr_fb_hdmi_core'),
        @('frame_pressure','tb_ddr_fb_hdmi_core','-gREADY_DELAY=2'),
        @('frame_corrupt','tb_ddr_fb_hdmi_core','-gCORRUPT=1'),
        @('self_corrupt','tb_ddr_fb_hdmi_core','-gCORRUPT=1','-gCORRUPT_ADDR=40'),
        @('fifo_underflow','tb_ddr_fb_hdmi_core','-gFIFO_FAULT=1'),
        @('fifo_overflow','tb_ddr_fb_hdmi_core','-gFIFO_FAULT=2'),
        @('ddr_source','tb_ddr_fb_hdmi_core','-gDDR_PROOF=1')
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
    }
} finally { Pop-Location }
