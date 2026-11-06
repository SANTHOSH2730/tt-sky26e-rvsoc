# Source this file:  source scripts/env.sh
# Environment exactly as in https://www.tinytapeout.com/guides/local-hardening (SKY130 tab),
# plus the RISC-V toolchain used for the firmware.
export TTSETUP="${TTSETUP:-$HOME/ttsetup}"
export PDK_ROOT="$TTSETUP/pdk"
export PDK=sky130A
export LIBRELANE_TAG=3.0.14          # tt-gds-action@ttsky26d default
export RISCV_PREFIX="${RISCV_PREFIX:-riscv-none-elf-}"
export PATH="$TTSETUP/riscv/bin:$HOME/.local/bin:$PATH"
if [ -f "$TTSETUP/venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$TTSETUP/venv/bin/activate"
fi
