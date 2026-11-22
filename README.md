# UzeTang

A [Uzebox](https://uzebox.org) console core for the **Sipeed Tang Nano 20K**
FPGA, based on the Uzebox Omega design.

- **CPU:** a new, cycle-exact ATmega644 core. It is verified in lock-step,
  cycle by cycle, against the
  [CUzeBox-ex](https://github.com/weber21w/cuzebox-ex) emulator.
- **Video and audio:** HDMI at 720×480p, 59.94 Hz, with 48 kHz audio. There is
  no composite output and no AD725.
- **Games:** loaded from the micro SD card by the standard Uzebox
  **Bootloader5** game loader, which ships in the bitstream.
- **Controllers:** two SNES pads on the same pins and adapters as
  [SNESTang](https://github.com/nand2mario/snestang/blob/main/doc/installation.md).
- **SPI RAM:** 8 MB, emulated in the board's built-in SDRAM (all of it)
  (23LC1024-compatible: READ, WRITE, RDMR and WRMR, with byte, page and
  sequential modes; 24-bit addresses). The kernel's `SpiRamInitGetSize()`
  reports 128 banks of 64 KB, as CUzeBox-ex does with 8 MB.

Not included yet: the ESP8266 / Uzenet, DualShock 2 adapters (their pins are
kept free), EEPROM saving across power cycles, and SNES mouse or keyboard
support.

> **Status:** everything has been verified in simulation, and the open-source
> flow places, routes and meets timing. **Nothing has been tested on a real
> board yet.** Please report what you see.

## Hardware

| Function | Tang Nano 20K pins | Notes |
|---|---|---|
| HDMI | on-board connector | 720×480p, 4:3, HDMI with 48 kHz audio |
| micro SD | on-board slot | SPI mode, FAT16/FAT32, SD and SDHC |
| SNES pad 1 | latch 28, clock 27, data 25 | as SNESTang |
| SNES pad 2 | latch 29, clock 26, data 30 | as SNESTang |
| S1 button | 88 | reset (see below) |
| S2 button | 87 | hold for free-running video (no frame lock), for diagnosis |
| LED0 / LED1 | 15 / 16 | SD access / slow blink = video OK, fast blink = no video sync |

Pins 17–20 (SNESTang's DualShock 2 adapter) are left unused.

## Using it

1. Format a micro SD card as FAT32 (or FAT16) and copy `.uze` games onto it.
2. Flash the bitstream to the Tang Nano 20K (see [Flashing](#flashing)).
3. Power up. As on a real Uzebox, Bootloader5 first watches the controller for
   about ¾ s:
   - If the card holds exactly one `.uze`, it is flashed and started.
   - Otherwise the **game selector** opens.
   - At power-up the AVR's flash and EEPROM are blank, so you always start in
     the selector.
4. Choose a game with **Up/Down** and press **Start** (or Select). The game is
   written into the AVR's flash, which takes a second or two, and then starts.
5. **S1** resets the console. Hold any pad button while pressing S1 to return to
   the selector. **B** in the selector switches between "reset starts the game"
   and "reset opens the menu"; this setting is kept until power-off. In game,
   Start+Select+Y+B is the usual Uzebox soft reset.

## Flashing

UzeTang is flashed like any other Tang Nano 20K core, with openFPGALoader or
the Gowin programmer.

### Installing openFPGALoader on Debian and Ubuntu

openFPGALoader is in the standard Debian and Ubuntu repositories:

```
sudo apt update
sudo apt install openfpgaloader
```

Older releases ship an old version that does not know the Tang Nano 20K
(`openFPGALoader --list-boards | grep tangnano20k` prints nothing). In that
case build it from source, as described in the
[openFPGALoader install guide](https://trabucayre.github.io/openFPGALoader/guide/install.html)
and Sipeed's [Flashing on Linux](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-Doc/flash-in-linux.html)
page:

```
sudo apt install git gzip libftdi1-2 libftdi1-dev libhidapi-hidraw0 libhidapi-dev \
    libudev-dev zlib1g-dev cmake pkg-config make g++
git clone https://github.com/trabucayre/openFPGALoader.git
cd openFPGALoader && mkdir build && cd build
cmake .. && make -j$(nproc) && sudo make install
```

To use it without `sudo`, install the udev rules (see the install guide) and
add yourself to the `plugdev` group.

### Writing the bitstream

Connect the Tang Nano 20K by USB, then:

```
openFPGALoader -f uzetang.fs
```

`-f` writes to the board's flash, so UzeTang starts every time the board is
powered on. Add `-b tangnano20k` if openFPGALoader does not detect the board
on its own. Without `-f`, the bitstream is only loaded into the FPGA and is
lost at power-off, which is handy for a quick test.

## Building

### Installing the Gowin IDE

Follow Sipeed's [Install the IDE](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-Doc/install-the-ide.html)
guide. In short:

- Download the **Education Edition** from Gowin's website. It needs no licence;
  the Standard Edition needs a licence file from Gowin.
- On Linux, unpack the archive. The tools are in its `IDE/bin` folder (`gw_ide`
  for the IDE, `gw_sh` for scripted builds such as UzeTang's).
- On Windows, run the installer with all components selected, then install the
  two drivers it offers.
- Sipeed suggests openFPGALoader (above) for flashing on Linux, as the Gowin
  programmer does not always work with the Tang boards' USB-JTAG.

### Gowin EDA

From the UzeTang folder (adjust the path to where you unpacked Gowin):

```
env -u DISPLAY -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen LIBGL_ALWAYS_SOFTWARE=1 \
    ~/Gowin_V1.9.11.03_Education_Linux/IDE/bin/gw_sh build.tcl
```

This produces `impl/pnr/uzetang.fs`. Use the Gowin Education Edition 1.9.9 or
newer, the same as SNESTang (tested with V1.9.11.03 on Debian 12). This build
uses Gowin's own I/O settings for the pad pins (pull-ups) and emulated LVDS
for HDMI, exactly as SNESTang does.

`gw_sh` has no window, but it still loads Qt and OpenGL. The `env` settings
above hide the desktop from it and ask for software rendering. Without them,
`gw_sh` can abort with "Could not load the Qt platform plugin "xcb"" and a
core dump, or with `libGL error` / `X Error ... GLX`. If it still fails,
install Mesa's OpenGL drivers (`sudo apt install libgl1-mesa-dri`), or run it
in a virtual X server (`sudo apt install xvfb`, then
`xvfb-run -a .../gw_sh build.tcl`).

The timing report (`impl/pnr/uzetang.tr.html`) lists setup and hold
violations for a clock called `sys/hdmi_out/aud_acc[0]`. They are false: that
is the 48 kHz audio clock, which is made from the pixel clock and only feeds
the HDMI audio sample handover. Gowin assumes it runs at 100 MHz with no
relationship to the pixel clock. Check `clk_cpu` (28.688 MHz needed) and
`clk_pix` (27 MHz needed) in the Max Frequency Summary instead.

### Open source (yosys + nextpnr-himbaechel + apicula)

```
NEXTPNR=nextpnr-himbaechel syn/oss_build.sh
```

This produces `syn/out/uzetang_oss.fs`. yosys cannot read hdl-util's
SystemVerilog HDMI encoder, so this flow uses `rtl/hdmi/hdmi_lite.v`, a plain
Verilog HDMI encoder written for UzeTang. It sends real HDMI with:

- data islands on every line (two packets each);
- an AVI InfoFrame (RGB, 4:3, full range, IT content / graphics);
- an Audio InfoFrame, Audio Clock Regeneration (N 6144, CTS 27000) and 48 kHz
  L-PCM audio sample packets;
- vsync edges aligned with the hsync leading edge, as CEA-861 requires, and at
  least 12 control characters before every preamble, as the HDMI compliance
  test requires.

apicula only allows true LVDS buffers on the HDMI pins, so this flow uses
`TLVDS_OBUF`. The Gowin flow uses emulated LVDS (`ELVDS_OBUF`), as SNESTang
does.

**SNES pads and I/O bank 5.** The SNES pad pins (25–30) share I/O bank 5 with
the HDMI pins. With true LVDS outputs in the bank, apicula's `gowin_pack`
(0.35) configures the whole bank for a low voltage, and it also sets two
configuration bits on the pad data inputs differently from the Gowin IDE: it
leaves `CLAMP=PCI` off and sets an input-standard bit that belongs to the
differential / reference-voltage standards. With that bitstream the pad data
line reads wrongly. Every pressed button also shows up as the next one in the
SNES bit order, B reads as held, and START reads as START+UP, so Bootloader5
loads the game above the highlighted one.

`syn/oss_build.sh` therefore packs through `tools/gowin_pack_bank33.py`, a
small wrapper around apicula's `gowin_pack`. It keeps banks with LVDS outputs
at the board's real 3.3 V and sets those pad-input bits as the Gowin IDE sets
them. The pad pins' I/O configuration then decodes identically to the Gowin
build's, and the pads work in both builds. To check that against a Gowin
bitstream, `tools/gowin_pack_bank33.py --iob-from uzetang.fs ...` copies the
pad tiles' I/O fuses from it instead.

The results below are from yosys 0.33 and nextpnr-himbaechel master
(Nov 2026), for the GW2AR-LV18QN88C8/I7:

| Resource | Used | Available |
|---|---|---|
| LUT4 (after packing, nextpnr) | 15,610 | 20,736 (75%) |
| Flip-flops | 2,544 | 15,552 (16%) |
| Block RAM | 41 | 46 (89%) |
| AVR clock Fmax | 31.7 MHz | needs 28.69 MHz |
| Pixel clock Fmax | 66 MHz | needs 27 MHz |

### Bootloader

The AVR flash's boot section (0xF000) holds Bootloader5 as the block RAM's
initial contents, generated from `firmware/bootloader5.hex`:

```
python3 tools/hex2mem.py --gowin-init firmware/bootloader5.hex rtl/bootloader_init.vh
```

## Verification

All test benches are in `sim/` (Verilator):

- **`tb_lockstep`** (`Vavr_soc`, or `Vls_top` with the SPI RAM emulation, the
  SDRAM controller and an SDRAM model) compiles the CUzeBox-ex AVR core in as a
  reference.
  - At every instruction it compares PC, cycle count, r0–r31, SREG and SP.
  - Every *N* instructions it also compares all of SRAM and the I/O registers.
  - `tests/run_fuzz.sh` generates random instruction streams, with Timer1,
    SPI and USART interrupts, PINx toggles, 16-bit timer writes and EEPROM
    strobes.
  - `tests/run_demos.sh` runs the Uzebox repository's games and demos, which
    are built with `tools/build_demo.py`.
- **`sim/hdmi`** checks the open-source HDMI encoder. `tb_hdmi.v` (Icarus
  Verilog) writes three frames of TMDS symbols, and `check_hdmi.py` decodes
  them the way a display does. It checks the period structure and guard
  bands, every video pixel, sync timing, the BCH ECC of every packet,
  InfoFrame checksums, ACR values, and the audio samples (values, order,
  parity, channel status). The checker also decodes hdl-util's output with
  no packet errors (`sim/hdmi/ref`).
- **`tests/demos_src/SpiRam8M`** detects the SPI RAM size and writes and reads
  patterns in all 128 banks, including blocks that cross bank boundaries. It
  passes in lock-step with CUzeBox-ex set to 8 MB (`Vls_top` built with
  `-DLS_SPIRAM_BITS=23`, run with `-r 128`).
- **`tb_system`** (`Vsim_system`, or `Vsim_system` in `sysobj_lite` with the
  open-source HDMI encoder) simulates the whole board design with real
  clock ratios: frame lock, HDMI encoder input, SDRAM, a bit-level SD card
  model with CRC serving a FAT32 image, and scripted pad presses. It writes
  the HDMI frames as images. It covers the whole path: power-up, Bootloader5's
  menu, flashing a game from SD, booting it, and pad detection and buttons.

**Known deliberate difference from CUzeBox-ex:** PINA returns the *live* pad
data lines, as a real AVR does. The emulator latches them on PORTA writes. This
only shows if PINA is read before PORTA is first written, or if a program
clocks a missing pad more than 32 times.

## Licence

GPL v3 or later. `rtl/hdmi/` contains hdl-util/hdmi (MIT OR Apache-2.0),
used by the Gowin flow; `rtl/hdmi/hdmi_lite.v` is UzeTang's own (GPL v3). The
test benches include CUzeBox and CUzeBox-ex sources (GPL v3). Bootloader5 and
the Uzebox kernel are from the Uzebox project (GPL v3).
