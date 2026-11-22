// Top level for the full UzeTang system simulation (Verilator)
module sim_system (
    input  wire        clk,
    input  wire        clk_pix,
    input  wire        rst,
    input  wire        rst_pix,
    input  wire        lock_en,
    input  wire        ld_we,
    input  wire [14:0] ld_addr,
    input  wire [15:0] ld_data,
    input  wire [15:0] pad1_buttons,
    input  wire        pad1_connected,
    output wire        sd_sck,
    output wire        sd_mosi,
    output wire        sd_cs_n,
    input  wire        sd_miso,
    output wire        led_sd,
    output wire        led_ram,
    output wire        video_locked,
    output wire        waiting,
    output wire        dbg_istart,
    output wire [15:0] dbg_pc,
    output wire        cpu_ce,
    output wire [31:0] sdram_errors
);
    wire        cke, cs_n, ras_n, cas_n, we_n, dq_oe;
    wire [10:0] a;
    wire [1:0]  ba;
    wire [3:0]  dqm;
    wire [31:0] dq_o, dq_i;

    uzebox_system sys (
        .clk(clk), .clk_pix(clk_pix), .clk_pix5(clk_pix), .rst(rst), .rst_pix(rst_pix),
        .lock_en(lock_en), .wd_seed(32'd0),
        .ld_we(ld_we), .ld_addr(ld_addr), .ld_data(ld_data),
        .pad1_buttons(pad1_buttons), .pad1_connected(pad1_connected),
        .pad2_buttons(16'd0), .pad2_connected(1'b0),
        .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_cs_n(sd_cs_n), .sd_miso(sd_miso),
        .sdram_cke(cke), .sdram_cs_n(cs_n), .sdram_ras_n(ras_n), .sdram_cas_n(cas_n),
        .sdram_we_n(we_n), .sdram_addr(a), .sdram_ba(ba), .sdram_dqm(dqm),
        .sdram_dq_out(dq_o), .sdram_dq_oe(dq_oe), .sdram_dq_in(dq_i),
        .tmds(), .tmds_clock(),
        .led_sd(led_sd), .led_ram(led_ram), .video_locked(video_locked), .waiting(waiting),
        .dbg_istart(dbg_istart), .dbg_pc(dbg_pc), .cpu_ce(cpu_ce)
    );

    // SDRAM pin clock is the inverted controller clock
    sdram_model sdm (
        .clk(~clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .addr(a), .ba(ba), .dqm(dqm), .dq_in(dq_o), .dq_oe(dq_oe), .dq_out(dq_i),
        .errors(sdram_errors)
    );
endmodule
