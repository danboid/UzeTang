// ============================================================================
//  uzetang_top.v - UzeTang (Uzebox for the Sipeed Tang Nano 20K) top level
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  Clocks (27 MHz crystal):
//    PLL A: 135 MHz TMDS clock, /5 = 27 MHz HDMI pixel clock (720x480p)
//    PLL B: 459 MHz / 16 = 28.6875 MHz AVR clock (Uzebox: 28.63636 MHz;
//           the frame lock pauses the AVR ~0.4% of the time so its average
//           speed matches the 59.94 Hz HDMI output)
//
//  Buttons: S1 = reset (hold a pad button while releasing it to enter the
//  Bootloader5 game selector), S2 = hold for free-running (unlocked) mode.
//  Controllers: SNES pads wired as for SNESTang (latch / clock / data).
//  SD card: on-board micro SD slot in SPI mode.
// ============================================================================

`default_nettype none

module uzetang_top (
    input  wire        sys_clk,        // 27 MHz
    input  wire        s1,             // button S1 (high when pressed)
    input  wire        s2,             // button S2 (high when pressed)

    // HDMI
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n,

    // micro SD card (SPI mode)
    output wire        sd_clk,
    output wire        sd_cmd,         // MOSI
    input  wire        sd_dat0,        // MISO
    output wire        sd_dat3,        // CS
    output wire        sd_dat1,
    output wire        sd_dat2,

    // SNES controllers
    output wire        joy1_strb,
    output wire        joy1_clk,
    input  wire        joy1_data,
    output wire        joy2_strb,
    output wire        joy2_clk,
    input  wire        joy2_data,

    // LEDs (active low). Only LED0/LED1 (pins 15/16) are used: pins 17-20
    // carry SNESTang's DualShock 2 adapter lines (reserved for later).
    output wire [1:0]  led,

    // UART (unused, reserved for debugging / Uzenet)
    output wire        uart_txd,

    // embedded SDRAM (GW2AR-18 "magic" port names)
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_wen_n,
    inout  wire [31:0] IO_sdram_dq,
    output wire [10:0] O_sdram_addr,
    output wire [1:0]  O_sdram_ba,
    output wire [3:0]  O_sdram_dqm
);
    // ------------------------------------------------------------------
    // Clocks
    // ------------------------------------------------------------------
    wire clk_tmds, clk_pix, clk_cpu, lock_a, lock_b;

    rPLL #(
        .FCLKIN("27"), .DEVICE("GW2AR-18C"),
        .DYN_IDIV_SEL("false"), .IDIV_SEL(0),
        .DYN_FBDIV_SEL("false"), .FBDIV_SEL(4),          // 27 * 5 = 135 MHz
        .DYN_ODIV_SEL("false"), .ODIV_SEL(4),            // VCO 540 MHz
        .PSDA_SEL("0000"), .DYN_DA_EN("false"), .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"), .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"),
        .CLKOUTD_BYPASS("false"), .DYN_SDIV_SEL(2),
        .CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT")
    ) pll_a (
        .CLKOUT(clk_tmds), .LOCK(lock_a), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
        .RESET(1'b0), .RESET_P(1'b0), .CLKIN(sys_clk), .CLKFB(1'b0),
        .FBDSEL(6'd0), .IDSEL(6'd0), .ODSEL(6'd0), .PSDA(4'd0), .DUTYDA(4'd0), .FDLY(4'd0)
    );

    CLKDIV #(.DIV_MODE("5"), .GSREN("false")) pix_div (
        .CLKOUT(clk_pix), .HCLKIN(clk_tmds), .RESETN(lock_a), .CALIB(1'b0)
    );

    rPLL #(
        .FCLKIN("27"), .DEVICE("GW2AR-18C"),
        .DYN_IDIV_SEL("false"), .IDIV_SEL(0),
        .DYN_FBDIV_SEL("false"), .FBDIV_SEL(16),         // 27 * 17 = 459 MHz
        .DYN_ODIV_SEL("false"), .ODIV_SEL(2),            // VCO 918 MHz
        .PSDA_SEL("0000"), .DYN_DA_EN("false"), .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"), .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"),
        .CLKOUTD_BYPASS("false"), .DYN_SDIV_SEL(16),     // 459 / 16 = 28.6875 MHz
        .CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT")
    ) pll_b (
        .CLKOUT(), .LOCK(lock_b), .CLKOUTP(), .CLKOUTD(clk_cpu), .CLKOUTD3(),
        .RESET(1'b0), .RESET_P(1'b0), .CLKIN(sys_clk), .CLKFB(1'b0),
        .FBDSEL(6'd0), .IDSEL(6'd0), .ODSEL(6'd0), .PSDA(4'd0), .DUTYDA(4'd0), .FDLY(4'd0)
    );

    // ------------------------------------------------------------------
    // Resets
    // ------------------------------------------------------------------
    reg [2:0]  s1_s, s2_s;
    reg [19:0] rst_cnt = 20'd0;
    reg        rst_cpu = 1'b1;
    always @(posedge clk_cpu) begin
        s1_s <= {s1_s[1:0], s1};
        s2_s <= {s2_s[1:0], s2};
        if (!lock_a || !lock_b || s1_s[2]) begin
            rst_cnt <= 20'd0;
            rst_cpu <= 1'b1;
        end else if (rst_cnt != 20'hFFFFF) begin
            rst_cnt <= rst_cnt + 20'd1;
        end else
            rst_cpu <= 1'b0;
    end
    reg [3:0] rst_pix_s = 4'hF;
    always @(posedge clk_pix) rst_pix_s <= {rst_pix_s[2:0], ~lock_a};
    wire rst_pix = rst_pix_s[3];

    // free-running seed for the watchdog timer (randomises WDT periods,
    // which the Uzebox kernel uses to seed random numbers)
    reg [31:0] lfsr = 32'h1;
    always @(posedge clk_cpu) lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    reg [31:0] wd_seed;
    always @(posedge clk_cpu) if (rst_cpu) wd_seed <= lfsr;

    // ------------------------------------------------------------------
    // Controllers
    // ------------------------------------------------------------------
    wire [15:0] p1_btn, p2_btn;
    wire        p1_conn, p2_conn;
    snes_pad_scan #(.FREQ(28_687_500)) scan1 (
        .clk(clk_cpu), .rst(rst_cpu), .pad_latch(joy1_strb), .pad_clk(joy1_clk),
        .pad_data(joy1_data), .buttons(p1_btn), .connected(p1_conn)
    );
    snes_pad_scan #(.FREQ(28_687_500)) scan2 (
        .clk(clk_cpu), .rst(rst_cpu), .pad_latch(joy2_strb), .pad_clk(joy2_clk),
        .pad_data(joy2_data), .buttons(p2_btn), .connected(p2_conn)
    );

    // ------------------------------------------------------------------
    // SDRAM data bus
    // ------------------------------------------------------------------
    wire [31:0] dq_out;
    wire        dq_oe;
    assign IO_sdram_dq = dq_oe ? dq_out : 32'hzzzzzzzz;
    assign O_sdram_clk = ~clk_cpu;

    // ------------------------------------------------------------------
    // System
    // ------------------------------------------------------------------
    wire [2:0] tmds;
    wire       tmds_clock;
    wire       led_sd, led_ram, vlocked, waiting;
    wire       sd_cs_n;

    uzebox_system #(
        .SPIRAM_BITS(23),         // 8 MB (the whole SDRAM)
        .SDRAM_FREQ(28_687_500)
    ) sys (
        .clk(clk_cpu), .clk_pix(clk_pix), .clk_pix5(clk_tmds),
        .rst(rst_cpu), .rst_pix(rst_pix), .lock_en(~s2_s[2]), .wd_seed(wd_seed),
        .ld_we(1'b0), .ld_addr(15'd0), .ld_data(16'd0),
        .pad1_buttons(p1_btn), .pad1_connected(p1_conn),
        .pad2_buttons(p2_btn), .pad2_connected(p2_conn),
        .sd_sck(sd_clk), .sd_mosi(sd_cmd), .sd_cs_n(sd_cs_n), .sd_miso(sd_dat0),
        .sdram_cke(O_sdram_cke), .sdram_cs_n(O_sdram_cs_n), .sdram_ras_n(O_sdram_ras_n),
        .sdram_cas_n(O_sdram_cas_n), .sdram_we_n(O_sdram_wen_n), .sdram_addr(O_sdram_addr),
        .sdram_ba(O_sdram_ba), .sdram_dqm(O_sdram_dqm),
        .sdram_dq_out(dq_out), .sdram_dq_oe(dq_oe), .sdram_dq_in(IO_sdram_dq),
        .tmds(tmds), .tmds_clock(tmds_clock),
        .led_sd(led_sd), .led_ram(led_ram), .video_locked(vlocked), .waiting(waiting),
        .dbg_istart(), .dbg_pc(), .cpu_ce()
    );

    assign sd_dat3 = sd_cs_n;
    assign sd_dat1 = 1'b1;
    assign sd_dat2 = 1'b1;
    assign uart_txd = 1'b1;

    // ------------------------------------------------------------------
    // HDMI differential outputs
    // ------------------------------------------------------------------
`ifdef UZETANG_OSS
    // open-source flow (apicula requires true LVDS buffers on these pins)
    TLVDS_OBUF tmds_bufd [2:0] (.I(tmds), .O(tmds_d_p), .OB(tmds_d_n));
    TLVDS_OBUF tmds_bufc (.I(tmds_clock), .O(tmds_clk_p), .OB(tmds_clk_n));
`else
    // Gowin IDE: emulated LVDS, as SNESTang (proven on the Tang Nano 20K)
    ELVDS_OBUF tmds_bufd [2:0] (.I(tmds), .O(tmds_d_p), .OB(tmds_d_n));
    ELVDS_OBUF tmds_bufc (.I(tmds_clock), .O(tmds_clk_p), .OB(tmds_clk_n));
`endif

    // ------------------------------------------------------------------
    // LEDs (active low): LED0 SD card access, LED1 video OK (blinks slowly
    // when the AVR produces a valid sync, fast when it does not)
    // ------------------------------------------------------------------
    reg [24:0] hb;
    always @(posedge clk_cpu) hb <= hb + 25'd1;
    assign led = ~{vlocked ? hb[24] : hb[21], led_sd};

endmodule

`default_nettype wire
