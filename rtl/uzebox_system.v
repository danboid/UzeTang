// ============================================================================
//  uzebox_system.v - UzeTang system: core + HDMI output + SDRAM
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  Clock domains:
//    clk      AVR clock (28.6875 MHz on the Tang Nano 20K), also SDRAM
//    clk_pix  HDMI pixel clock (27 MHz), clk_pix5 = 5 x clk_pix (TMDS)
// ============================================================================

`default_nettype none

module uzebox_system #(
    parameter SPIRAM_BITS  = 23,
    parameter SDRAM_FREQ   = 28_687_500
)(
    input  wire        clk,
    input  wire        clk_pix,
    input  wire        clk_pix5,
    input  wire        rst,          // AVR domain reset (power-on / reset button)
    input  wire        rst_pix,      // pixel domain reset
    input  wire        lock_en,      // frame lock enable
    input  wire [31:0] wd_seed,

    // flash loader (simulation)
    input  wire        ld_we,
    input  wire [14:0] ld_addr,
    input  wire [15:0] ld_data,

    // controllers
    input  wire [15:0] pad1_buttons,
    input  wire        pad1_connected,
    input  wire [15:0] pad2_buttons,
    input  wire        pad2_connected,

    // SD card
    output wire        sd_sck,
    output wire        sd_mosi,
    output wire        sd_cs_n,
    input  wire        sd_miso,

    // SDRAM
    output wire        sdram_cke,
    output wire        sdram_cs_n,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output wire [10:0] sdram_addr,
    output wire [1:0]  sdram_ba,
    output wire [3:0]  sdram_dqm,
    output wire [31:0] sdram_dq_out,
    output wire        sdram_dq_oe,
    input  wire [31:0] sdram_dq_in,

    // HDMI
    output wire [2:0]  tmds,
    output wire        tmds_clock,
    output wire        audio_dac,    // 1-bit audio DAC (pixel clock domain)

    // status
    output wire        led_sd,
    output wire        led_ram,
    output wire        video_locked,
    output wire        waiting,

    output wire        dbg_istart,
    output wire [15:0] dbg_pc,
    output wire        cpu_ce
);
    wire        ce;
    wire        lb_we;
    wire [13:0] lb_waddr, lb_raddr;
    wire [7:0]  lb_wdata, lb_rdata;
    wire        frame_start;
    wire        frame_tog;
    wire [7:0]  snd_val;
    wire        snd_tog;
    wire        mem_req, mem_we, mem_rvalid;
    wire [SPIRAM_BITS-1:0] mem_addr;
    wire [7:0]  mem_wdata, mem_rdata;
    wire        sdram_ready;

    assign cpu_ce = ce;

    // hold the AVR in reset until the SDRAM is initialised
    wire core_rst = rst | ~sdram_ready;

    uzebox_core #(
        .SPIRAM_BITS(SPIRAM_BITS)
    ) core (
        .clk(clk), .ce(ce), .rst(core_rst), .wd_seed(wd_seed),
        .ld_we(ld_we), .ld_addr(ld_addr), .ld_data(ld_data),
        .pad1_buttons(pad1_buttons), .pad1_connected(pad1_connected),
        .pad2_buttons(pad2_buttons), .pad2_connected(pad2_connected),
        .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_cs_n(sd_cs_n), .sd_miso(sd_miso),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rvalid(mem_rvalid), .mem_rdata(mem_rdata),
        .lb_we(lb_we), .lb_addr(lb_waddr), .lb_data(lb_wdata),
        .frame_start(frame_start), .video_locked(video_locked),
        .snd_val(snd_val), .snd_tog(snd_tog),
        .led_sd(led_sd), .led_ram(led_ram),
        .dbg_istart(dbg_istart), .dbg_pc(dbg_pc)
    );

    framelock flock (
        .clk(clk), .rst(core_rst), .enable(lock_en),
        .frame_start(frame_start), .frame_tog(frame_tog),
        .ce(ce), .waiting(waiting)
    );

    linebuf lbuf (
        .wclk(clk), .we(lb_we), .waddr(lb_waddr), .wdata(lb_wdata),
        .rclk(clk_pix), .raddr(lb_raddr), .rdata(lb_rdata)
    );

    uzebox_hdmi hdmi_out (
        .clk_pixel(clk_pix), .clk_pixel_x5(clk_pix5), .rst(rst_pix),
        .lb_addr(lb_raddr), .lb_data(lb_rdata),
        .snd_val(snd_val), .snd_tog(snd_tog),
        .frame_tog(frame_tog),
        .tmds(tmds), .tmds_clock(tmds_clock), .audio_dac(audio_dac)
    );

    sdram_ctl #(.FREQ(SDRAM_FREQ), .AW(SPIRAM_BITS)) sdram (
        .clk(clk), .rst(rst),
        .req(mem_req), .we(mem_we), .addr(mem_addr), .wdata(mem_wdata),
        .rvalid(mem_rvalid), .rdata(mem_rdata), .ready(sdram_ready),
        .sd_cke(sdram_cke), .sd_cs_n(sdram_cs_n), .sd_ras_n(sdram_ras_n),
        .sd_cas_n(sdram_cas_n), .sd_we_n(sdram_we_n), .sd_addr(sdram_addr),
        .sd_ba(sdram_ba), .sd_dqm(sdram_dqm),
        .sd_dq_out(sdram_dq_out), .sd_dq_oe(sdram_dq_oe), .sd_dq_in(sdram_dq_in)
    );

endmodule

`default_nettype wire
