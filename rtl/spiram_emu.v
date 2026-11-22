// ============================================================================
//  spiram_emu.v - 23LC1024 compatible SPI RAM emulation (up to 4 MB)
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  Behaviour follows CUzeBox's cu_spir.c (READ 0x03, WRITE 0x02, RDMR 0x05,
//  WRMR 0x01; byte / page (32 bytes) / sequential modes). The address is 24
//  bits on the wire; ADDR_BITS of it are used (17 = 128 KB like the stock
//  23LC1024, 22 = 4 MB). Storage is external (SDRAM) through a simple
//  request interface.
//
//  The device works at byte level: the AVR's SPI master tells it when a
//  transfer starts and which byte it is sending. The byte the device sends
//  back during a transfer (rx) is the one computed after the previous
//  transfer, which is exactly how CUzeBox models it. Starting the memory
//  access at the beginning of a transfer leaves 16+ cycles for SDRAM latency.
// ============================================================================

`default_nettype none

module spiram_emu #(
    parameter ADDR_BITS = 22
)(
    input  wire        clk,
    input  wire        ce,
    input  wire        rst,
    input  wire        cs_n,          // chip select (PA4), active low
    input  wire        xfer_start,    // SPI transfer starts (with ce)
    input  wire [7:0]  xfer_tx,       // byte sent by the AVR
    output wire [7:0]  rx,            // byte the device sends in the next transfer

    // memory interface (byte wide)
    output reg         mem_req,       // one-cycle request
    output reg         mem_we,
    output reg  [ADDR_BITS-1:0] mem_addr,
    output reg  [7:0]  mem_wdata,
    input  wire        mem_rvalid,    // read data valid (one-cycle pulse)
    input  wire [7:0]  mem_rdata
);
    localparam ST_IDLE = 3'd0, ST_READ = 3'd1, ST_WRITE = 3'd2, ST_READB = 3'd3,
               ST_WRITEB = 3'd4, ST_RMODE = 3'd5, ST_WMODE = 3'd6, ST_SINK = 3'd7;

    reg [2:0]  st;
    reg [1:0]  ppos;
    reg [23:0] addr;
    reg [7:0]  mode;
    reg [7:0]  data;
    reg        cs_q;

    assign rx = data;

    // next address according to mode
    wire [23:0] addr_seq  = addr + 24'd1;
    wire [23:0] addr_page = {addr[23:5], addr[4:0] + 5'd1};
    wire [23:0] addr_nxt  = (mode == 8'h80) ? addr_page :
                            (mode == 8'h40) ? addr_seq  : addr;

    always @(posedge clk) begin
        mem_req <= 1'b0;
        if (rst) begin
            st <= ST_IDLE; ppos <= 2'd0; addr <= 24'd0; mode <= 8'h40;
            data <= 8'hFF; cs_q <= 1'b1;
            mem_we <= 1'b0; mem_addr <= {ADDR_BITS{1'b0}}; mem_wdata <= 8'd0;
        end else begin
            if (mem_rvalid) data <= mem_rdata;
            if (ce) begin
                cs_q <= cs_n;
                if (cs_n && !cs_q) st <= ST_IDLE;          // deselected: back to idle
                if (xfer_start) begin
                    if (st == ST_READB) begin
                        // fast path (as in CUzeBox): sequential data read
                        addr     <= addr_nxt;
                        mem_req  <= 1'b1;
                        mem_we   <= 1'b0;
                        mem_addr <= addr_nxt[ADDR_BITS-1:0];
                    end else begin
                        data <= 8'hFF;
                        if (!cs_n) begin
                            case (st)
                            ST_IDLE: begin
                                case (xfer_tx)
                                8'h01: st <= ST_WMODE;
                                8'h02: begin st <= ST_WRITE; addr <= 24'd0; ppos <= 2'd0; end
                                8'h03: begin st <= ST_READ;  addr <= 24'd0; ppos <= 2'd0; end
                                8'h05: begin st <= ST_RMODE; data <= mode; end
                                default: st <= ST_SINK;
                                endcase
                            end
                            ST_READ, ST_WRITE: begin : addr_phase
                                reg [23:0] a;
                                a = addr;
                                case (ppos)
                                2'd0: a[23:16] = xfer_tx;
                                2'd1: a[15:8]  = xfer_tx;
                                default: a[7:0] = xfer_tx;
                                endcase
                                addr <= a;
                                ppos <= ppos + 2'd1;
                                if (ppos == 2'd2) begin
                                    if (st == ST_READ) begin
                                        st       <= ST_READB;
                                        mem_req  <= 1'b1;
                                        mem_we   <= 1'b0;
                                        mem_addr <= a[ADDR_BITS-1:0];
                                    end else
                                        st <= ST_WRITEB;
                                end
                            end
                            ST_WRITEB: begin
                                mem_req   <= 1'b1;
                                mem_we    <= 1'b1;
                                mem_addr  <= addr[ADDR_BITS-1:0];
                                mem_wdata <= xfer_tx;
                                addr      <= addr_nxt;
                            end
                            ST_RMODE: st <= ST_SINK;
                            ST_WMODE: begin mode <= xfer_tx & 8'hC0; st <= ST_SINK; end
                            default: ;
                            endcase
                        end
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
