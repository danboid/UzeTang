// ============================================================================
//  uzebox_core.v - Uzebox (Omega) console core, board independent
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  Everything that runs in the AVR clock domain:
//   - the ATmega644 (avr_soc), booting into the bootloader at 0xF000
//   - two emulated SNES controllers on PA0..PA3
//   - SD card on the SPI bus (CS = PD6)
//   - SPI RAM emulation (CS = PA4) backed by external memory (SDRAM)
//   - video capture of PORTC / sync (PB0) into a line buffer
//   - audio sample (OCR2A) handed to the output stage
//
//  The 'ce' input pauses everything except the SDRAM interface.
// ============================================================================

`default_nettype none

module uzebox_core #(
    parameter SPIRAM_BITS  = 23,      // 23 = 8 MB, 17 = 128 KB (23LC1024)
    parameter HSTART       = 296
)(
    input  wire        clk,
    input  wire        ce,
    input  wire        rst,
    input  wire [31:0] wd_seed,

    // external flash loader (test benches)
    input  wire        ld_we,
    input  wire [14:0] ld_addr,
    input  wire [15:0] ld_data,

    // controllers (already scanned; 1 = pressed)
    input  wire [15:0] pad1_buttons,
    input  wire        pad1_connected,
    input  wire [15:0] pad2_buttons,
    input  wire        pad2_connected,

    // SD card (SPI mode)
    output wire        sd_sck,
    output wire        sd_mosi,
    output wire        sd_cs_n,
    input  wire        sd_miso,

    // SPI RAM backing store
    output wire        mem_req,
    output wire        mem_we,
    output wire [SPIRAM_BITS-1:0] mem_addr,
    output wire [7:0]  mem_wdata,
    input  wire        mem_rvalid,
    input  wire [7:0]  mem_rdata,

    // video line buffer write port
    output wire        lb_we,
    output wire [13:0] lb_addr,
    output wire [7:0]  lb_data,
    output wire        frame_start,
    output wire        video_locked,

    // audio
    output reg  [7:0]  snd_val,
    output reg         snd_tog,

    // status
    output wire        led_sd,        // SD card selected
    output wire        led_ram,       // SPI RAM selected

    // debug
    output wire        dbg_istart,
    output wire [15:0] dbg_pc
);
    wire [7:0] porta, ddra, portb, ddrb, portc, ddrc, portd, ddrd;
    wire       spi_sck, spi_mosi, spi_miso;
    wire       spi_xfer_start;
    wire [7:0] spi_xfer_tx;
    wire [7:0] spiram_rx;
    wire       pad1_data, pad2_data;
    wire       snd_we;
    wire       wdt_reset;
    wire [7:0] snd_raw;

    // output pin levels: PORT & DDR (an input pin reads as low here, as in CUzeBox)
    wire pa_latch  = porta[2] & ddra[2];
    wire pa_clock  = porta[3] & ddra[3];
    wire ram_cs_n  = porta[4] & ddra[4];
    wire sdc_cs_n  = ~(ddrd[6] & ~portd[6]);     // SD CS: released when not driven low
    wire vsync_pin = portb[0] & ddrb[0];

    avr_soc soc (
        .clk(clk), .ce(ce), .rst(rst), .rst_vec(16'h7800), .wd_seed(wd_seed),
        .ld_we(ld_we), .ld_addr(ld_addr), .ld_data(ld_data),
        .ee_ext_we(1'b0), .ee_ext_addr(11'd0), .ee_ext_wdata(8'd0), .ee_ext_rdata(),
        .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .spi_int_rx(ram_cs_n ? 8'hFF : spiram_rx),
        .spi_xfer_start(spi_xfer_start), .spi_xfer_tx(spi_xfer_tx),
        .pad1_data(pad1_data), .pad2_data(pad2_data),
        .porta(porta), .ddra(ddra), .portb(portb), .ddrb(ddrb),
        .portc(portc), .ddrc(ddrc), .portd(portd), .ddrd(ddrd),
        .snd_we(snd_we), .snd_val(snd_raw), .wdt_reset(wdt_reset),
        .dbg_istart(dbg_istart), .dbg_pc(dbg_pc), .dbg_sreg(), .dbg_sp(), .dbg_regs()
    );

    // ---------------- controllers ----------------
    snes_pad_emu pad1 (
        .clk(clk), .ce(ce), .rst(rst), .latch_pin(pa_latch), .clock_pin(pa_clock),
        .buttons(pad1_buttons), .connected(pad1_connected), .data(pad1_data)
    );
    snes_pad_emu pad2 (
        .clk(clk), .ce(ce), .rst(rst), .latch_pin(pa_latch), .clock_pin(pa_clock),
        .buttons(pad2_buttons), .connected(pad2_connected), .data(pad2_data)
    );

    // ---------------- SPI bus ----------------
    assign sd_sck   = spi_sck;
    assign sd_mosi  = spi_mosi;
    assign sd_cs_n  = sdc_cs_n;
    assign spi_miso = sdc_cs_n ? 1'b1 : sd_miso;

    spiram_emu #(.ADDR_BITS(SPIRAM_BITS)) spiram (
        .clk(clk), .ce(ce), .rst(rst | wdt_reset), .cs_n(ram_cs_n),
        .xfer_start(spi_xfer_start), .xfer_tx(spi_xfer_tx), .rx(spiram_rx),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata)
    );

    // ---------------- video ----------------
    wire [8:0] row;
    video_capture #(.HSTART(HSTART)) vcap (
        .clk(clk), .ce(ce), .rst(rst), .sync(vsync_pin), .pix(portc),
        .lb_we(lb_we), .lb_addr(lb_addr), .lb_data(lb_data),
        .row(row), .frame_start(frame_start), .locked(video_locked)
    );

    // ---------------- audio ----------------
    always @(posedge clk) begin
        if (rst) begin
            snd_val <= 8'h80;
            snd_tog <= 1'b0;
        end else if (ce && snd_we) begin
            snd_val <= snd_raw;
            snd_tog <= ~snd_tog;
        end
    end

    assign led_sd  = ~sdc_cs_n;
    assign led_ram = ~ram_cs_n;

endmodule

`default_nettype wire
