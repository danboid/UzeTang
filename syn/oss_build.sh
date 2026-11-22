#!/bin/sh
# Open-source build (yosys + nextpnr-himbaechel + apicula) for UzeTang.
# yosys cannot parse hdl-util's SystemVerilog HDMI encoder, so this flow uses
# the plain Verilog HDMI encoder rtl/hdmi/hdmi_lite.v (HDMI with InfoFrames
# and 48 kHz audio). The HDMI pins use true LVDS buffers (TLVDS_OBUF), as
# apicula does not allow emulated LVDS on them.
set -e
# CST=uzetang_board.cst syn/oss_build.sh builds for the UzeTang Board
# (board buttons and SD socket); the default is the bare Tang Nano 20K.
HERE=$(cd "$(dirname "$0")" && pwd)
R=$HERE/../rtl
OUT=$HERE/out
mkdir -p "$OUT"
NEXTPNR=${NEXTPNR:-nextpnr-himbaechel}
cd "$R"     # bootloader_init.vh is included from here
yosys -q -l "$OUT/yosys.log" -p "
  read_verilog -DUZETANG_OSS -DUZETANG_HDMI_LITE -I. \
    tang20k/uzetang_top.v uzebox_system.v uzebox_core.v avr_soc.v avr_cpu.v avr_io.v flash_bank.v \
    snes_pad.v spiram_emu.v sdram_ctl.v video_capture.v framelock.v uzebox_hdmi.v hdmi/hdmi_lite.v;
  synth_gowin -top uzetang_top -json $OUT/uzetang.json"
# nextpnr wants both pins of a differential pair constrained separately
sed -E 's/IO_LOC "([a-z_]+)_p(\[[0-9]\])?" ([0-9]+),([0-9]+);/IO_LOC "\1_p\2" \3;\nIO_LOC "\1_n\2" \4;/' \
    "$R/tang20k/${CST:-uzetang.cst}" > "$OUT/uzetang_oss.cst"
$NEXTPNR --json "$OUT/uzetang.json" --write "$OUT/uzetang_pnr.json" \
    --device GW2AR-LV18QN88C8/I7 --vopt family=GW2A-18C \
    --vopt cst="$OUT/uzetang_oss.cst" --freq 28.7 --threads 2 \
    --report "$OUT/report.json" 2>&1 | tee "$OUT/nextpnr.log" | grep -E "Info: Device utilisation|Info: \s+[A-Z_]+:|Max frequency|ERROR|Warning: .*timing" || true
if grep -q "^ERROR" "$OUT/nextpnr.log"; then echo "nextpnr failed, see $OUT/nextpnr.log"; exit 1; fi
# gowin_pack through a wrapper that keeps bank 5 (HDMI + SNES pads) at 3.3 V
# and sets the pad data inputs as the Gowin IDE does; see the script.
python3 "$HERE/../tools/gowin_pack_bank33.py" -d GW2A-18C -o "$OUT/uzetang_oss.fs" "$OUT/uzetang_pnr.json"
echo "bitstream: $OUT/uzetang_oss.fs"
