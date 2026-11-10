# Vivado flow for the PYNQ-Z2 FPGA harness of tt_um_santhosh_rvsoc, run on Windows
# against the project inside WSL. From PowerShell:
#   powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu-22.04\home\santhosh\tt-sky26d-rvsoc\fpga\pynq_z2\build_on_windows.ps1
#
# Steps (all run by default):
#   1. firmware + flash image, built in WSL               (-SkipFirmware: reuse fpga/build/rvsoc_fw_nibbles.hex)
#   2. xsim, RTL, "fast"   : fpga/sim/tb_fpga.v        MMCM bypassed, FAST_SIM (2 Mbaud)
#   3. xsim, RTL, "board"  : fpga/sim/tb_fpga_board.v  real MMCM model, 115200 baud, pins only
#   4. Vivado synthesis, implementation, reports, bitstream, post-route netlist   (-SkipBuild)
#   5. xsim, netlist, "board": tb_fpga_board.v on the post-route netlist (the bitstream's logic)
#   6. -Program: load the bitstream into the board over JTAG
#   (-SkipSim skips steps 2, 3 and 5)
# Results: fpga/build/   bitstream, routed checkpoint, post-route netlist, reports
#          reports/fpga/ reports and simulation logs (kept in git)
#          logs/vivado_build.log
# The sources are copied to a local folder first: Vivado and xsim are much faster
# on a local disk than on the \\wsl.localhost share.
param(
    [string]$Vivado = "C:\Xilinx\2025.1\Vivado\bin\vivado.bat",
    [string]$Repo = "\\wsl.localhost\Ubuntu-22.04\home\santhosh\tt-sky26d-rvsoc",
    [switch]$Program,
    [switch]$SkipFirmware,
    [switch]$SkipSim,
    [switch]$SkipBuild
)
$ErrorActionPreference = "Continue"      # native tools write to stderr; exit codes are checked instead
$bin   = Split-Path $Vivado
$xvlog = Join-Path $bin "xvlog.bat"
$xelab = Join-Path $bin "xelab.bat"
$xsim  = Join-Path $bin "xsim.bat"
$glbl  = (Join-Path (Split-Path $bin) "data\verilog\src\glbl.v") -replace '\\', '/'
$work  = Join-Path $env:TEMP "rvsoc_vivado"
$stage = Join-Path $work "repo"
$build = Join-Path $stage "fpga\build"
$root  = $stage -replace '\\', '/'
$rep   = Join-Path $Repo "reports\fpga"
$summary = New-Object System.Collections.Generic.List[string]
$failed = $false

function Step($msg) { Write-Host ""; Write-Host "=== [$(Get-Date -Format HH:mm:ss)] $msg ===" -ForegroundColor Cyan }
function Note($msg) { Write-Host $msg; $summary.Add($msg) }

# ------------------------------------------------------------ 1. firmware
if (-not $SkipFirmware) {
    Step "Firmware and flash image (WSL)"
    wsl -d Ubuntu-22.04 --exec bash -lc "cd ~/tt-sky26d-rvsoc && source scripts/env.sh && make -s -C firmware && make -s -C fpga build/rvsoc_fw_nibbles.hex"
    if ($LASTEXITCODE -ne 0) { throw "firmware build failed" }
}

# ------------------------------------------------------- stage the sources
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $build | Out-Null
Copy-Item -Recurse "$Repo\src" "$stage\src"
foreach ($d in @("rtl", "pynq_z2", "sim")) { Copy-Item -Recurse "$Repo\fpga\$d" "$stage\fpga\$d" }
Copy-Item "$Repo\fpga\build\rvsoc_fw_nibbles.hex" $build
New-Item -ItemType Directory -Force $rep | Out-Null

# TinyQV first: project.v / timer.v set `default_nettype none, which Vivado carries
# into later files, and TinyQV declares ports without a net type.
$chip = @(Get-ChildItem "$stage\src\tinyQV\cpu\*.v" | Sort-Object Name | ForEach-Object { $_.FullName -replace '\\', '/' }) +
        @("$root/src/tinyQV/peri/uart/uart_tx.v", "$root/src/tinyQV/peri/uart/uart_rx.v") +
        @("$root/src/timer.v", "$root/src/project.v")
$harness = @("$root/fpga/rtl/qspi_pmod_emu.v", "$root/fpga/rtl/uart_watch.v", "$root/fpga/pynq_z2/top_pynq_z2.v")

# ------------------------------------------------------------- xsim helper
# -sv: the RTL uses a few SystemVerilog constructs (e.g. a function without inputs in
# uart_rx.v), as Icarus (-g2012) and Yosys accept them.
function Invoke-Xsim([string]$name, [string]$top, [string[]]$design, [string]$tb, [string[]]$defines, [string]$pass, [switch]$sv) {
    Step "xsim: $name"
    $dir = Join-Path $work "xsim_$name"
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item (Join-Path $build "rvsoc_fw_nibbles.hex") $dir
    Push-Location $dir
    $t0 = Get-Date
    $defArgs = @(); foreach ($d in $defines) { $defArgs += @("-d", $d) }
    $svArg = @()
    if ($sv) {
        # RTL: like Icarus' +timescale+1ns/1ps, give the TinyQV files (which have no
        # `timescale) the 1 ns default by compiling a timescale line ahead of them.
        $svArg = @("--sv")
        '`timescale 1ns / 1ps' | Set-Content -Encoding ascii "$dir\timescale.v"
        $design = @("$($dir -replace '\\', '/')/timescale.v") + $design
    }
    & $xvlog -log xvlog_glbl.log $glbl | Out-Null
    & $xvlog -log xvlog_design.log @svArg @defArgs @design | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    if ($ok) { & $xvlog -log xvlog_tb.log @defArgs $tb | Out-Null; $ok = ($LASTEXITCODE -eq 0) }
    if ($ok) { & $xelab -L unisims_ver -s snap -log xelab.log "work.$top" work.glbl | Out-Null; $ok = ($LASTEXITCODE -eq 0) }
    if ($ok) { & $xsim snap -R -log xsim.log | Out-Null; $ok = ($LASTEXITCODE -eq 0) }
    $mins = ((Get-Date) - $t0).TotalMinutes
    Pop-Location
    $log = Join-Path $dir "xsim.log"
    if (-not (Test-Path $log)) {
        foreach ($l in @("xvlog_design.log", "xvlog_tb.log", "xelab.log")) { if (Test-Path "$dir\$l") { $log = "$dir\$l" } }
    }
    Copy-Item $log (Join-Path $rep "xsim_$name.log") -Force
    Get-Content $log | Where-Object { $_ -match '\[tb_|UART>|^Hello|PASS|FAIL|ERROR' } | Write-Host
    $passed = $ok -and (Select-String -Path $log -Pattern $pass -SimpleMatch -Quiet)
    Note ("xsim {0,-14}: {1} ({2:N1} min)" -f $name, $(if ($passed) { "PASS" } else { "FAIL" }), $mins)
    if (-not $passed) { $script:failed = $true }
}

# ---------------------------------------------------------- 2, 3. RTL sims
if (-not $SkipSim) {
    Invoke-Xsim "rtl_fast"  "tb_fpga"       ($chip + $harness) "$root/fpga/sim/tb_fpga.v"       @("SIM") "[tb_fpga] PASS" -sv
    Invoke-Xsim "rtl_board" "tb_fpga_board" ($chip + $harness) "$root/fpga/sim/tb_fpga_board.v" @()      "[tb_board] PASS" -sv
}

# ----------------------------------------------------- 4. Vivado build
if (-not $SkipBuild) {
    Step "Vivado: synthesis, implementation, bitstream"
    $t0 = Get-Date
    Push-Location $work                          # Vivado writes .Xil/ scratch files here
    & $Vivado -mode batch -nojournal -log "$work\vivado_build.log" -source "$root/fpga/pynq_z2/build_vivado.tcl" `
        -tclargs $root "$root/fpga/build/rvsoc_fw_nibbles.hex" "$root/fpga/build" | Out-Null
    $rc = $LASTEXITCODE
    Pop-Location
    Copy-Item "$work\vivado_build.log" "$Repo\logs\vivado_build.log" -Force
    Select-String -Path "$work\vivado_build.log" -Pattern "^RVSOC_FPGA_RESULT" | ForEach-Object { Note $_.Line }
    Note ("vivado build        : exit {0} ({1:N1} min)" -f $rc, ((Get-Date) - $t0).TotalMinutes)
    if ($rc -ne 0 -or -not (Test-Path "$build\rvsoc_pynq_z2.bit")) { $failed = $true; Note "vivado build FAILED: see logs/vivado_build.log" }
    foreach ($f in Get-ChildItem "$build\*.rpt") { Copy-Item $f.FullName $rep -Force; Copy-Item $f.FullName "$Repo\fpga\build\" -Force }
    foreach ($f in @("rvsoc_pynq_z2.bit", "top_pynq_z2_routed.dcp", "top_pynq_z2_funcsim.v")) {
        if (Test-Path "$build\$f") { Copy-Item "$build\$f" "$Repo\fpga\build\$f" -Force }
    }
}

# ------------------------------------------------- 5. post-route netlist sim
if (-not $SkipSim -and (Test-Path "$build\top_pynq_z2_funcsim.v")) {
    Invoke-Xsim "netlist_board" "tb_fpga_board" @("$root/fpga/build/top_pynq_z2_funcsim.v") "$root/fpga/sim/tb_fpga_board.v" @() "[tb_board] PASS"
}

# ---------------------------------------------------------- 6. programming
if ($Program) {
    Step "Program the board over JTAG"
    # With -SkipBuild, program the bitstream already in the project's fpga/build
    if (-not (Test-Path "$build\rvsoc_pynq_z2.bit")) { Copy-Item "$Repo\fpga\build\rvsoc_pynq_z2.bit" $build }
    & $Vivado -mode batch -nojournal -log "$work\vivado_program.log" -source "$root/fpga/pynq_z2/program_vivado.tcl" `
        -tclargs "$root/fpga/build/rvsoc_pynq_z2.bit"
    Note ("program             : exit {0}" -f $LASTEXITCODE)
}

Step "Summary"
# Keep the recorded results when only programming (-SkipSim -SkipBuild)
if (-not ($SkipSim -and $SkipBuild)) { $summary | Set-Content -Encoding ascii (Join-Path $rep "vivado_summary.txt") }
$summary | ForEach-Object { Write-Host $_ }
if ($failed) { Write-Host "RESULT: FAIL" -ForegroundColor Red; exit 1 } else { Write-Host "RESULT: PASS" -ForegroundColor Green }
