// ============================================================================
//  avr_soc.v - ATmega644 "chip": CPU + I/O + flash + SRAM + EEPROM
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  Flash (64 KB) is split into two banks of 16K words (even / odd word
//  addresses) so one fetch returns two consecutive words. Port B of each
//  bank serves LPM reads, SPM page erase / write and an external loader.
// ============================================================================

`default_nettype none

// Flash initial contents: the Uzebox bootloader in the boot section (see
// flash_bank.v / bootloader_init.vh); the game area starts empty.
module avr_soc (
    input  wire        clk,
    input  wire        ce,           // clock enable: 0 pauses the whole chip
    input  wire        rst,
    input  wire [15:0] rst_vec,      // 0x0000 (game) or 0x7800 (bootloader)
    input  wire [31:0] wd_seed,

    // external flash loader (use while rst is held)
    input  wire        ld_we,
    input  wire [14:0] ld_addr,      // word address
    input  wire [15:0] ld_data,

    // EEPROM external access port (save / restore, use while rst is held)
    input  wire        ee_ext_we,
    input  wire [10:0] ee_ext_addr,
    input  wire [7:0]  ee_ext_wdata,
    output wire [7:0]  ee_ext_rdata,

    // SPI bus
    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    input  wire [7:0]  spi_int_rx,
    output wire        spi_xfer_start,
    output wire [7:0]  spi_xfer_tx,

    // controllers
    input  wire        pad1_data,
    input  wire        pad2_data,

    // ports
    output wire [7:0]  porta, ddra, portb, ddrb, portc, ddrc, portd, ddrd,

    // audio
    output wire        snd_we,
    output wire [7:0]  snd_val,

    output wire        wdt_reset,    // watchdog system reset (SPI devices reset too)

    // debug / trace
    output wire        dbg_istart,
    output wire [15:0] dbg_pc,
    output wire [7:0]  dbg_sreg,
    output wire [15:0] dbg_sp,
    output wire [255:0] dbg_regs
);

    // ------------------------------------------------------------------
    // CPU <-> peripherals
    // ------------------------------------------------------------------
    wire [15:0] pm_addr;
    wire [15:0] pm_w0, pm_w1;
    wire        lpm_en;
    wire [15:0] lpm_addr;
    wire [7:0]  lpm_data;
    wire        spm_req;
    wire [15:0] spm_z, spm_data;
    wire [11:0] dm_addr;
    wire        dm_we;
    wire [7:0]  dm_wdata;
    wire [7:0]  dm_rdata;
    wire [7:0]  io_addr, io_wdata, io_rdata;
    wire        io_re, io_we;
    wire        it_chk, it_iflag, it_take, ev_now, ev_late;
    wire [15:0] it_vec;
    wire [2:0]  io_stall;
    wire        wdt_rst, wdr;
    assign wdt_reset = wdt_rst;
    wire        fl_erase, fl_write;
    wire [7:0]  fl_page;
    wire        sb_we;
    wire [6:0]  sb_idx;
    wire [15:0] sb_data;
    wire [10:0] ee_addr;
    wire [7:0]  ee_dout;
    wire        ee_we;
    wire [7:0]  ee_wdata;

    wire        cpu_run;
    avr_cpu cpu (
        .clk(clk), .ce(ce), .rst(rst), .cpu_run(cpu_run), .rst_vec(rst_vec),
        .pm_addr(pm_addr), .pm_w0(pm_w0), .pm_w1(pm_w1),
        .lpm_en(lpm_en), .lpm_addr(lpm_addr), .lpm_data(lpm_data),
        .spm_req(spm_req), .spm_z(spm_z), .spm_data(spm_data),
        .dm_addr(dm_addr), .dm_we(dm_we), .dm_wdata(dm_wdata), .dm_rdata(dm_rdata),
        .io_addr(io_addr), .io_re(io_re), .io_we(io_we), .io_wdata(io_wdata),
        .io_rdata(io_rdata),
        .it_chk(it_chk), .it_iflag(it_iflag), .it_take(it_take), .it_vec(it_vec),
        .ev_now(ev_now), .ev_late(ev_late), .io_stall(io_stall),
        .wdt_rst(wdt_rst), .wdr(wdr),
        .dbg_istart(dbg_istart), .dbg_pc(dbg_pc), .dbg_sreg(dbg_sreg),
        .dbg_sp(dbg_sp), .dbg_regs(dbg_regs)
    );

    avr_io io (
        .clk(clk), .ce(ce), .rst(rst | ~cpu_run),
        .io_addr(io_addr), .io_re(io_re), .io_we(io_we), .io_wdata(io_wdata),
        .io_rdata(io_rdata),
        .it_chk(it_chk), .it_iflag(it_iflag), .it_take(it_take), .it_vec(it_vec),
        .ev_now(ev_now), .ev_late(ev_late), .io_stall(io_stall),
        .wdr(wdr), .wd_seed(wd_seed), .wdt_rst(wdt_rst),
        .spm_req(spm_req), .spm_z(spm_z), .spm_data(spm_data),
        .fl_erase(fl_erase), .fl_write(fl_write), .fl_page(fl_page),
        .sb_we(sb_we), .sb_idx(sb_idx), .sb_data(sb_data),
        .ee_addr(ee_addr), .ee_dout(ee_dout), .ee_we(ee_we), .ee_wdata(ee_wdata),
        .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .spi_int_rx(spi_int_rx), .spi_xfer_start(spi_xfer_start), .spi_xfer_tx(spi_xfer_tx),
        .pad1_data(pad1_data), .pad2_data(pad2_data),
        .porta(porta), .ddra(ddra), .portb(portb), .ddrb(ddrb),
        .portc(portc), .ddrc(ddrc), .portd(portd), .ddrd(ddrd),
        .snd_we(snd_we), .snd_val(snd_val)
    );

    // ------------------------------------------------------------------
    // Flash: two banks of 16K x 16
    // ------------------------------------------------------------------
    // Port A: dual word fetch
    wire [14:0] fa     = pm_addr[14:0];
    wire [14:0] fa1    = fa + 15'd1;
    wire [13:0] fa_e   = fa[0] ? fa1[14:1] : fa[14:1];   // even bank word
    wire [13:0] fa_o   = fa[14:1];                       // odd bank word
    reg         fa_odd;
    wire [15:0] fe_qa, fo_qa;
    always @(posedge clk) if (ce) fa_odd <= fa[0];
    assign pm_w0 = fa_odd ? fo_qa : fe_qa;
    assign pm_w1 = fa_odd ? fe_qa : fo_qa;

    // Port B: LPM / SPM sequencer / loader
    localparam Q_IDLE = 3'd0, Q_ERASE = 3'd1, Q_RD = 3'd2, Q_CAP = 3'd3, Q_WR = 3'd4;
    reg  [2:0]  q_st;
    reg  [5:0]  q_j;          // word pair index within page (0..63)
    reg  [7:0]  q_pg;
    reg  [15:0] q_e, q_o;     // captured old contents
    reg  [15:0] sbuf [0:127];

    always @(posedge clk) if (ce && sb_we) sbuf[sb_idx] <= sb_data;

    reg  [13:0] fb_addr;
    reg         fe_web, fo_web;
    reg  [15:0] fe_db, fo_db;
    wire [15:0] fe_qb, fo_qb;
    wire [13:0] q_addr  = {q_pg, q_j};

    always @* begin
        fb_addr = lpm_addr[15:2];
        fe_web = 1'b0; fo_web = 1'b0;
        fe_db  = 16'hFFFF; fo_db = 16'hFFFF;
        if (ld_we) begin
            fb_addr = ld_addr[14:1];
            fe_web  = ~ld_addr[0];
            fo_web  =  ld_addr[0];
            fe_db   = ld_data;
            fo_db   = ld_data;
        end else if (!lpm_en) begin
            case (q_st)
            Q_ERASE: begin
                fb_addr = q_addr; fe_web = 1'b1; fo_web = 1'b1;
            end
            Q_RD:    fb_addr = q_addr;
            Q_WR: begin
                fb_addr = q_addr; fe_web = 1'b1; fo_web = 1'b1;
                fe_db   = q_e & sbuf[{q_j, 1'b0}];
                fo_db   = q_o & sbuf[{q_j, 1'b1}];
            end
            default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            q_st <= Q_IDLE;
            q_j  <= 6'd0;
            q_pg <= 8'd0;
        end else if (ce) begin
            if (fl_erase) begin q_st <= Q_ERASE; q_j <= 6'd0; q_pg <= fl_page; end
            else if (fl_write) begin q_st <= Q_RD; q_j <= 6'd0; q_pg <= fl_page; end
            else case (q_st)
            Q_ERASE: if (!lpm_en) begin
                q_j <= q_j + 6'd1;
                if (q_j == 6'd63) q_st <= Q_IDLE;
            end
            Q_RD:  if (!lpm_en) q_st <= Q_CAP;
            Q_CAP: begin q_e <= fe_qb; q_o <= fo_qb; q_st <= Q_WR; end
            Q_WR:  if (!lpm_en) begin
                q_j <= q_j + 6'd1;
                q_st <= (q_j == 6'd63) ? Q_IDLE : Q_RD;
            end
            default: q_st <= Q_IDLE;
            endcase
        end
    end

    // LPM byte select (registered alongside RAM output)
    reg [1:0] lpm_sel;
    always @(posedge clk) if (ce) lpm_sel <= lpm_addr[1:0];
    wire [15:0] lpm_w = lpm_sel[1] ? fo_qb : fe_qb;
    assign lpm_data = lpm_sel[0] ? lpm_w[15:8] : lpm_w[7:0];

    flash_bank #(.BANK(0)) flash_e (
        .clk(clk), .cea(ce), .addra(fa_e), .qa(fe_qa),
        .ceb(ce | ld_we), .addrb(fb_addr), .web(fe_web), .db(fe_db), .qb(fe_qb)
    );
    flash_bank #(.BANK(1)) flash_o (
        .clk(clk), .cea(ce), .addra(fa_o), .qa(fo_qa),
        .ceb(ce | ld_we), .addrb(fb_addr), .web(fo_web), .db(fo_db), .qb(fo_qb)
    );

    // ------------------------------------------------------------------
    // Data SRAM 4 KB
    // ------------------------------------------------------------------
    sram_4k sram (
        .clk(clk), .ce(ce), .addr(dm_addr), .we(dm_we), .d(dm_wdata), .q(dm_rdata)
    );

    // ------------------------------------------------------------------
    // EEPROM 2 KB (port A: AVR, port B: external save/restore)
    // ------------------------------------------------------------------
    eeprom_ram eeprom (
        .clk(clk), .ce(ce), .addr(ee_addr), .we(ee_we), .d(ee_wdata), .q(ee_dout)
    );
    assign ee_ext_rdata = 8'hFF;      // external save / restore: not implemented yet

endmodule

`default_nettype wire
