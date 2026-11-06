# Build the PYNQ-Z2 bitstream with Vivado on Windows from the project inside WSL.
# Run from PowerShell:
#   powershell -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu-22.04\home\santhosh\tt-sky26d-rvsoc\fpga\pynq_z2\build_on_windows.ps1
# Options: -Vivado <path to vivado.bat>  -Program (also program the board over JTAG)
#          -SkipFirmware (use the existing fpga/build/rvsoc_fw_nibbles.hex)
# The sources are copied to a local folder first: Vivado is faster on a local disk
# and the WSL VM can then be stopped to free memory on small-RAM machines.
param(
    [string]$Vivado = "C:\Xilinx\2025.1\Vivado\bin\vivado.bat",
    [string]$Repo = "\\wsl.localhost\Ubuntu-22.04\home\santhosh\tt-sky26d-rvsoc",
    [switch]$Program,
    [switch]$SkipFirmware
)
$ErrorActionPreference = "Stop"
$work = Join-Path $env:TEMP "rvsoc_vivado"
$stage = Join-Path $work "repo"

if (-not $SkipFirmware) {
    wsl -d Ubuntu-22.04 --exec bash -lc "cd ~/tt-sky26d-rvsoc && source scripts/env.sh && make -s -C firmware && make -s -C fpga build/rvsoc_fw_nibbles.hex"
}

# Stage src/ and fpga/ locally
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force "$stage\fpga\build" | Out-Null
Copy-Item -Recurse "$Repo\src" "$stage\src"
foreach ($d in @("rtl", "pynq_z2")) { Copy-Item -Recurse "$Repo\fpga\$d" "$stage\fpga\$d" }
Copy-Item "$Repo\fpga\build\rvsoc_fw_nibbles.hex" "$stage\fpga\build\"

Set-Location $work                       # Vivado writes .Xil/ scratch files here
$root = $stage -replace '\\', '/'
& $Vivado -mode batch -nojournal -log "$work\vivado_build.log" -source "$root/fpga/pynq_z2/build_vivado.tcl" `
    -tclargs $root "$root/fpga/build/rvsoc_fw_nibbles.hex" "$root/fpga/build"

# Copy results back into the project
foreach ($f in @("rvsoc_pynq_z2.bit", "utilization.rpt", "timing_summary.rpt", "drc.rpt")) {
    if (Test-Path "$stage\fpga\build\$f") { Copy-Item "$stage\fpga\build\$f" "$Repo\fpga\build\$f" -Force }
}
Copy-Item "$work\vivado_build.log" "$Repo\logs\vivado_build.log" -Force

if ($Program) {
    & $Vivado -mode batch -nojournal -log "$work\vivado_program.log" -source "$root/fpga/pynq_z2/program_vivado.tcl" `
        -tclargs "$root/fpga/build/rvsoc_pynq_z2.bit"
}
