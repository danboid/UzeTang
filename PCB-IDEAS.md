## Building a UzeTang PCB

Notes and ideas for a carrier PCB that could turn a Tang Nano 20K into a complete Uzebox,
with two SNES ports, a full-size SD socket and an ESP8266, in a 3D-printed Uzebox case.

### Fitting the case

The [Uzebox 3D-printed case](https://github.com/Uzebox/uzebox/tree/master/cad/Enclosures/Uzebox/V2.0)
(V2.0, 3MF and Fusion 360 files) is built around the Uzebox V5.0 PCB
(`schematics/Uzebox/V5.0/Uzebox-V5.0.brd` in the same repository). The easiest
way to make a UzeTang board fit is to start from that board's outline, holes
and connector positions. The figures below come from those files.
Coordinates are in mm, with the origin at the board's front-left corner
(the SNES connector edge) and y towards the back.

| Item | Uzebox V5.0 position | Notes |
|---|---|---|
| Board outline | 100 × 81 | |
| Mounting holes | (3, 3), (97, 3), (55.14, 71.15) | 3.3 mm drill (M3); the case's standoffs sit under the two front holes |
| SNES player 1 / 2 | x = 21.59 / 76.20, at the front edge | SMD footprint, 7 pads 4 mm apart, except 6.5 mm between pins 4 and 5 |
| Reset / user buttons | (20.86, 13.97) / (77.47, 13.97) | 6 mm through-hole tact switches, pressed by the case's button caps |
| LED | (50.80, 2.54) | 3 mm LED under the case's light pipe |
| SD card socket | (83.82, 52.07), rotated 90° | full-size socket; the card goes in from the back |
| Rear connectors | DC jack x = 7.62, S-video 20.32, video RCA 34.29, audio RCA 46.99, ISP 58.42 | openings in the case's back wall |
| Rubber feet | (5.79, 59.86), (6.05, 5.92), (95.95, 4.79), (93.83, 73.83) | |

Case details measured from the V2.0 3MF files:

- **Outside:** 120 × 102.5 mm. The bottom shell is 15 mm high and the top
  shell 18 mm.
- **Board position:** the PCB sits centred left to right, with its front edge
  about 19 mm behind the front face, which leaves room for the SNES sockets.
- **Headroom:** about 22 mm from the top of the PCB to the inside of the top
  shell. That is enough for a Tang Nano 20K (5 mm thick with its parts) on
  standard 8.5 mm female headers.

Points to plan for:

- **Rear panel: HDMI and USB-C.** A UzeTang board has no DC jack, S-video
  (mini-DIN) or RCA jacks, which frees the rear area they used (x = 0 to about
  53 on the V5.0 layout) for the HDMI and USB-C sockets. The SD card socket
  stays where it is. Either place the Tang Nano so that its own HDMI socket
  sits at the rear edge, or use short extension cables:
  - **USB-C:** a short USB-C extension cable (panel-mount female end) brings
    the Tang Nano's USB-C to the back of the case, for power and for flashing
    with openFPGALoader.
  - **HDMI:** if the Tang Nano's HDMI socket can't reach the rear edge, a short
    panel-mount HDMI extension does the same job.

  Shape the openings in the rear wall to suit the sockets or panel-mount ends
  (the Fusion 360 project makes this easy), and check them against a test
  print. Use Sipeed's 3D model of the Tang Nano 20K to see where its HDMI and
  USB-C sockets are before placing the module.
- **Power.** Everything is powered through the USB-C extension. The SNES pads
  and the SD card can run from the Tang Nano's 3.3 V pin. Give the ESP8266 its
  own 3.3 V regulator fed from the Tang Nano's 5 V pin (see below).
- **Buttons.** Wire the reset and user button positions to spare header pins
  and map them in `rtl/tang20k/uzetang.cst` (reset in place of S1, and the user
  button in place of S2 or for a future function). Then the case's buttons
  work without reaching the Tang Nano's own S1/S2.
- **LED.** Drive the light-pipe LED from a spare pin (for example the
  SD-access LED) through a resistor.
- **Module mounting.** Mount the Tang Nano on female headers so it can be
  swapped.

### SNES controller ports

- Use the standard SNES port pinout: 1 = +5 V/VCC, 2 = clock, 3 = latch,
  4 = data, 7 = GND. Power the pads from **3.3 V**, not 5 V: the FPGA pins are
  3.3 V only and must never see 5 V on the data line.
- Fit a **4.7 kΩ pull-up from each data line to 3.3 V**. Pads only pull the data
  line low firmly; on its own the FPGA's internal pull-up can leave it rising
  slowly, which makes every pressed button also light the next one.
- Optional: 100 Ω series resistors on clock and latch near the FPGA, and a
  100 nF capacitor across VCC/GND at each port.
- Keep the SNESTang pin assignment (pad 1: latch 28, clock 27, data 25;
  pad 2: latch 29, clock 26, data 30). The same board then also works with
  SNESTang and NESTang.

### Full-size SD card socket

- UzeTang talks to the card in SPI mode only, so it needs four signals: SCK,
  MOSI (CMD), MISO (DAT0) and CS (DAT3). Wire them to four free 3.3 V header
  pins and change the `sd_*` lines in `rtl/tang20k/uzetang.cst` to match. No
  other change is needed. The on-board micro SD slot's pins are not on the
  headers, so it is simply left empty.
- Fit 10–47 kΩ pull-ups to 3.3 V on DAT0, DAT3, DAT1 and DAT2. Floating DAT1
  and DAT2 upset some cards in SPI mode.
- Power the socket from 3.3 V with 10 µF + 100 nF close to it.
- Optional: wire the socket's card-detect and write-protect switches to spare
  pins for future use. Bootloader5 does not use them.

### ESP8266 (Uzenet)

- On a Uzebox the ESP8266 is connected to the ATmega644's USART0
  (PD0 = RXD0, PD1 = TXD0). UzeTang already emulates the USART (verified
  against CUzeBox-ex) but does not route it to pins yet, and the ESP8266 is not
  emulated. Reserve two pins for TX/RX now; routing them is a small change.
- Also reserve pins for the ESP8266's RST/EN (lets a game reset it) and GPIO0
  (lets you reflash it in place), with the usual pull-ups (10 kΩ on EN, RST
  and GPIO0; GPIO15 pulled down).
- An ESP-01/ESP-01S module on a 2×4 header is the easiest option. The ESP8266
  draws current peaks of about 300 mA when it transmits, so give it its own
  3.3 V regulator (for example an AMS1117-3.3 from the 5 V USB supply) with
  a large capacitor (100–470 µF), rather than the Tang Nano's 3.3 V pin.

### Pin budget

The Tang Nano 20K's headers have about 34 usable GPIOs. UzeTang uses six for
the two pads; the SD socket needs four (five with card-detect), and the
ESP8266 two to four. Pins 17–20 are SNESTang's DualShock 2 adapter pins; keep
them free if you want that option later.

## Design notes

- **Clocks.** The AVR runs at 28.6875 MHz (27 × 17 / 16). A real Uzebox runs at
  28.63636 MHz. HDMI uses 27 MHz (pixel) and 135 MHz (TMDS) from a second PLL.
- **Frame lock.** The AVR runs about 0.18% fast, so the whole chip is paused for
  about 1,700 cycles at the start of each Uzebox frame. This keeps it locked to
  the HDMI frame, a few scanlines ahead of the output. Software cannot notice
  the pauses; the lock-step tests confirm this with random pauses of 30–40% of
  cycles.
- **CPU.** A multi-cycle core with CUzeBox-ex's exact instruction timing and
  its exact cycles for I/O access and interrupt checks. It prefetches, so the
  current instruction always comes from a register, which keeps the critical
  path short.
- **Memories.** Explicit Gowin primitives keep the mapping identical in every
  toolchain:
  - flash: 2 × 16 DPB blocks, two words fetched per cycle;
  - SRAM: 2 SP blocks;
  - EEPROM: 1 SP block, erased (0xFF) at power-up;
  - video line buffer: 6 SDPB blocks.
- **Video.** Each line, 1,440 AVR cycles are captured, starting 296 cycles after
  the hsync fall, over 240 rows. Two AVR cycles make one HDMI pixel, so the
  usual 6-cycle Uzebox pixels are exactly 3 HDMI pixels wide. Rows are shown
  twice.
- **Audio.** The Timer2 OCR2A sample is taken once per scanline, low-pass
  filtered, and sent as 48 kHz HDMI audio.
- **Controllers.** The physical pads are scanned every 4 ms with slow
  timing: each bit is sampled 60 µs after the clock edge that puts it on the
  line (a SNES waits 6 µs). With pads or wiring that only pull the data line
  high weakly, short timing makes every pressed bit leak into the next one
  (B reads as always held, START reads as START+UP). A new button state is
  accepted only when two scans in a row agree. `sim/pad/tb_pad.v` (Icarus)
  checks the scanner against a 4021 model with an adjustable rise time
  (`-P tb.RISE=50000` for 50 µs). The AVR sees an
  emulated 4021 shift register on PA0–PA3. Like a genuine pad, the data line
  goes low after 16 bits, which is how the kernel detects a connected pad.
- **SPI RAM.** Each byte is handed to the emulated chip when its SPI transfer
  starts. That leaves 16 or more AVR cycles to fetch the next byte from SDRAM,
  so back-to-back reads at fosc/2 work.
