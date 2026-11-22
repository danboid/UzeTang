#!/bin/sh
# Lock-step test all built demos; dumps one late frame of each for inspection.
# usage: run_demos.sh [instructions] [frame]
HERE=$(cd "$(dirname "$0")" && pwd)
SIM=$HERE/../sim/lsobj/Vls_top
N=${1:-40000000}; F=${2:-130}
for d in "$HERE"/build/demos/*/; do
  name=$(basename "$d")
  [ "$name" = Bootloader5 ] && continue
  hex=$(ls "$d"*.hex 2>/dev/null | head -1)
  [ -z "$hex" ] && continue
  ( cd "$d" && "$SIM" "$hex" -n "$N" -m 50021 -f "$F" -q 2>&1 | tail -2 | tr '\n' ' '; echo )
done
