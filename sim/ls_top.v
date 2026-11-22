`ifndef LS_SPIRAM_BITS
`define LS_SPIRAM_BITS 17
`endif
// Lock-step top with SPI RAM: avr_soc + spiram_emu + sdram_ctl + SDRAM model.
// Same ports as avr_soc so tb_lockstep.cpp can drive it (built with -DTOP_LS).
module ls_top (
    input  wire        clk,
    input  wire        ce,
    input  wire        rst,
    input  wire [15:0] rst_vec,
    input  wire [31:0] wd_seed,
    input  wire        ld_we,
    input  wire [14:0] ld_addr,
    input  wire [15:0] ld_data,
    input  wire        ee_ext_we,
    input  wire [10:0] ee_ext_addr,
    input  wire [7:0]  ee_ext_wdata,
    input  wire        spi_miso,
    input  wire [7:0]  spi_int_rx,     // unused here
    input  wire        pad1_data,
    input  wire        pad2_data,
    output wire [7:0]  portb, ddrb, portc,
    output wire        dbg_istart,
    output wire [15:0] dbg_pc,
    output wire [7:0]  dbg_sreg,
    output wire [15:0] dbg_sp,
    output wire [255:0] dbg_regs,
    output wire        sdram_ready,
    output wire [31:0] sdram_errors
);
    wire [7:0] porta, ddra;
    wire       wdtr;
    wire       xs;
    wire [7:0] xtx, ram_rx;
    wire       ram_cs_n = porta[4] & ddra[4];
    wire       req, we, rv;
    wire [`LS_SPIRAM_BITS-1:0] addr;
    wire [7:0] wd, rd;
    wire        cke, cs_n, ras_n, cas_n, we_n, dq_oe;
    wire [10:0] a;
    wire [1:0]  ba;
    wire [3:0]  dqm;
    wire [31:0] dq_o, dq_i;

    avr_soc soc (
        .clk(clk), .ce(ce), .rst(rst | ~sdram_ready), .rst_vec(rst_vec), .wd_seed(wd_seed),
        .ld_we(ld_we), .ld_addr(ld_addr), .ld_data(ld_data),
        .ee_ext_we(ee_ext_we), .ee_ext_addr(ee_ext_addr), .ee_ext_wdata(ee_ext_wdata), .ee_ext_rdata(),
        .spi_sck(), .spi_mosi(), .spi_miso(spi_miso),
        .spi_int_rx(ram_cs_n ? 8'hFF : ram_rx), .spi_xfer_start(xs), .spi_xfer_tx(xtx),
        .pad1_data(pad1_data), .pad2_data(pad2_data),
        .porta(porta), .ddra(ddra), .portb(portb), .ddrb(ddrb), .portc(portc), .ddrc(),
        .portd(), .ddrd(), .snd_we(), .snd_val(), .wdt_reset(wdtr),
        .dbg_istart(dbg_istart), .dbg_pc(dbg_pc), .dbg_sreg(dbg_sreg), .dbg_sp(dbg_sp),
        .dbg_regs(dbg_regs)
    );
    // default 17 address bits = 128 KB, like the 23LC1024 that CUzeBox models
    // by default; build with -DLS_SPIRAM_BITS=23 (8 MB) and run with -r 128
    spiram_emu #(.ADDR_BITS(`LS_SPIRAM_BITS)) ram (
        .clk(clk), .ce(ce), .rst(rst | wdtr), .cs_n(ram_cs_n), .xfer_start(xs), .xfer_tx(xtx),
        .rx(ram_rx), .mem_req(req), .mem_we(we), .mem_addr(addr), .mem_wdata(wd),
        .mem_rvalid(rv), .mem_rdata(rd)
    );
    reg [3:0] por = 4'hF;
    always @(posedge clk) if (por != 0) por <= por - 4'd1;
    sdram_ctl #(.FREQ(28_687_500), .AW(`LS_SPIRAM_BITS)) sdc (
        .clk(clk), .rst(por != 0), .req(req), .we(we), .addr(addr), .wdata(wd),
        .rvalid(rv), .rdata(rd), .ready(sdram_ready),
        .sd_cke(cke), .sd_cs_n(cs_n), .sd_ras_n(ras_n), .sd_cas_n(cas_n), .sd_we_n(we_n),
        .sd_addr(a), .sd_ba(ba), .sd_dqm(dqm), .sd_dq_out(dq_o), .sd_dq_oe(dq_oe), .sd_dq_in(dq_i)
    );
    sdram_model sdm (
        .clk(~clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .addr(a), .ba(ba), .dqm(dqm), .dq_in(dq_o), .dq_oe(dq_oe), .dq_out(dq_i),
        .errors(sdram_errors)
    );
endmodule
