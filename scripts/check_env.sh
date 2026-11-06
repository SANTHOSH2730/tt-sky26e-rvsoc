#!/usr/bin/env bash
# Preflight: verify every tool the flow needs and install missing pieces
# non-interactively (no sudo). Safe to re-run; it only adds things.
#   - Python >= 3.11 venv in ~/ttsetup/venv (via uv, system python is left alone)
#   - tt-support-tools in ./tt, its requirements, LibreLane $LIBRELANE_TAG, cocotb
#   - RISC-V GCC with RV32E/ilp32e support (xPack riscv-none-elf-gcc) in ~/ttsetup/riscv
#   - sky130A PDK version pinned by LibreLane, in ~/ttsetup/pdk (via ciel)
#   - LibreLane Docker image
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source scripts/env.sh

TT_TOOLS_REPO=https://github.com/TinyTapeout/tt-support-tools
TT_TOOLS_REF="${TT_TOOLS_REF:-main}"
XPACK_VER="${XPACK_VER:-14.3.0-1}"
FAILS=0
pass() { printf '\033[32mPASS\033[0m %-22s %s\n' "$1" "$2"; }
fix()  { printf '\033[33mFIX \033[0m %-22s %s\n' "$1" "$2"; }
fail() { printf '\033[31mFAIL\033[0m %-22s %s\n' "$1" "$2"; FAILS=$((FAILS+1)); }

# --- basic host tools -------------------------------------------------------
for t in git make curl tar python3; do
  if command -v $t >/dev/null; then pass "$t" "$(command -v $t)"; else fail "$t" "missing (install with apt)"; fi
done
if docker info >/dev/null 2>&1; then pass docker "$(docker info --format '{{.ServerVersion}}')"
else fail docker "daemon not reachable (sudo service docker start / add user to docker group)"; fi
if command -v iverilog >/dev/null; then pass iverilog "$(iverilog -V 2>&1 | head -1)"; else fail iverilog "missing (sudo apt install iverilog)"; fi

# --- uv + python 3.12 venv --------------------------------------------------
if ! command -v uv >/dev/null; then
  fix uv "installing with pip --user"; python3 -m pip install --user -q uv || fail uv "pip install failed"
fi
command -v uv >/dev/null && pass uv "$(uv --version)"
if [ ! -x "$TTSETUP/venv/bin/python" ]; then
  fix venv "creating $TTSETUP/venv (python 3.12)"
  mkdir -p "$TTSETUP" && uv venv -q --python 3.12 "$TTSETUP/venv" || fail venv "uv venv failed"
fi
source "$TTSETUP/venv/bin/activate"
PYV=$(python -c 'import sys;print("%d.%d"%sys.version_info[:2])')
python -c 'import sys;sys.exit(sys.version_info<(3,11))' && pass python "venv python $PYV" || fail python "venv python $PYV < 3.11"
python -m pip --version >/dev/null 2>&1 || uv pip install -q --python "$TTSETUP/venv/bin/python" pip

# --- tt-support-tools --------------------------------------------------------
if [ ! -d tt/.git ]; then
  fix tt-support-tools "cloning $TT_TOOLS_REPO ($TT_TOOLS_REF) into ./tt"
  git clone -q "$TT_TOOLS_REPO" tt && git -C tt checkout -q "$TT_TOOLS_REF" || fail tt-support-tools "clone failed"
fi
[ -f tt/tt_tool.py ] && pass tt-support-tools "$(git -C tt log -1 --format='%h %cs')"

# --- python packages -----------------------------------------------------------
need_pip=0
python -c "import librelane, importlib.metadata as m; assert m.version('librelane')=='$LIBRELANE_TAG'" 2>/dev/null || need_pip=1
python -c "import cocotb" 2>/dev/null || need_pip=1
if [ $need_pip = 1 ]; then
  fix pip "installing tt/requirements.txt, librelane==$LIBRELANE_TAG, test/requirements.txt"
  uv pip install -q --python "$TTSETUP/venv/bin/python" -r tt/requirements.txt "librelane==$LIBRELANE_TAG" -r test/requirements.txt \
    || fail pip "install failed"
fi
python -c "import importlib.metadata as m; print(m.version('librelane'))" >/dev/null 2>&1 \
  && pass librelane "$(python -c "import importlib.metadata as m; print(m.version('librelane'))")" || fail librelane "not importable"
command -v cocotb-config >/dev/null && pass cocotb "$(cocotb-config --version)" || fail cocotb "missing"

# --- RISC-V toolchain (needs ilp32e) -----------------------------------------
if ! command -v ${RISCV_PREFIX}gcc >/dev/null; then
  fix riscv-gcc "downloading xPack riscv-none-elf-gcc $XPACK_VER"
  base="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$XPACK_VER"
  tgz="xpack-riscv-none-elf-gcc-$XPACK_VER-linux-x64.tar.gz"
  dl="$TTSETUP/download"; mkdir -p "$dl"
  ( cd "$dl" && curl -fsSLO "$base/$tgz" && curl -fsSLO "$base/$tgz.sha" && sha256sum -c "$tgz.sha" ) \
    && tar -C "$TTSETUP" -xzf "$dl/$tgz" && ln -sfn "$TTSETUP/xpack-riscv-none-elf-gcc-$XPACK_VER" "$TTSETUP/riscv" \
    || fail riscv-gcc "download/verify failed"
fi
if echo 'int main(void){return 0;}' | ${RISCV_PREFIX}gcc -march=rv32ec_zicsr -mabi=ilp32e -nostdlib -x c -c -o /dev/null - 2>/dev/null; then
  pass riscv-gcc "$(${RISCV_PREFIX}gcc --version | head -1) (rv32ec_zicsr/ilp32e OK)"
else fail riscv-gcc "cannot build rv32ec/ilp32e"; fi

# --- PDK ---------------------------------------------------------------------
PDK_REV=$(python - <<'EOF' 2>/dev/null
import os, librelane, yaml
p = os.path.join(os.path.dirname(librelane.__file__), "pdk_hashes.yaml")
print(yaml.safe_load(open(p)).get("sky130", "") if os.path.exists(p) else "")
EOF
)
if [ -n "$PDK_REV" ]; then
  if [ ! -d "$PDK_ROOT/$PDK/libs.ref/sky130_fd_sc_hd" ] || ! ciel ls --pdk-root "$PDK_ROOT" --pdk-family sky130 2>/dev/null | grep -q "$PDK_REV.*enabled"; then
    fix pdk "ciel enable sky130 $PDK_REV"
    ciel enable --pdk-root "$PDK_ROOT" --pdk-family sky130 "$PDK_REV" >/dev/null || fail pdk "ciel enable failed"
  fi
fi
[ -d "$PDK_ROOT/$PDK/libs.ref/sky130_fd_sc_hd/verilog" ] && pass pdk "$PDK_ROOT/$PDK (${PDK_REV:0:10})" || fail pdk "missing $PDK_ROOT/$PDK"

# --- LibreLane docker image -------------------------------------------------
IMG="ghcr.io/librelane/librelane:$LIBRELANE_TAG"
if ! docker image inspect "$IMG" >/dev/null 2>&1; then
  fix docker-image "pulling $IMG"; docker pull -q "$IMG" >/dev/null || fail docker-image "pull failed"
fi
docker image inspect "$IMG" >/dev/null 2>&1 && pass docker-image "$IMG"

echo
if [ $FAILS = 0 ]; then echo "check_env: all PASS"; else echo "check_env: $FAILS FAIL(s)"; fi
exit $FAILS
