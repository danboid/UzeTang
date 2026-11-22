// ============================================================================
//  sdram_ctl.v - simple byte-access SDRAM controller for the Tang Nano 20K
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  Embedded GW2AR-18 SDRAM: 4 banks x 2K rows x 256 columns x 32 bit.
//  Runs at the AVR clock (~28.7 MHz). The SDRAM clock pin should be driven
//  with the inverted controller clock so commands and data are sampled in
//  the middle of the controller's cycle. One access at a time, CAS latency
//  2, auto-precharge, periodic auto-refresh. A request is serviced in at most
//  ~12 cycles (including a possible refresh in progress).
// ============================================================================

`default_nettype none

module sdram_ctl #(
    parameter FREQ = 28_687_500,
    parameter AW   = 23            // byte address bits (8 MB = 23, 4 MB = 22)
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        req,
    input  wire        we,
    input  wire [AW-1:0] addr,
    input  wire [7:0]  wdata,
    output reg         rvalid,
    output reg  [7:0]  rdata,
    output wire        ready,      // initialisation done

    // SDRAM pins
    output reg         sd_cke,
    output reg         sd_cs_n,
    output reg         sd_ras_n,
    output reg         sd_cas_n,
    output reg         sd_we_n,
    output reg  [10:0] sd_addr,
    output reg  [1:0]  sd_ba,
    output reg  [3:0]  sd_dqm,
    output reg  [31:0] sd_dq_out,  // data bus (tristate handled at top level)
    output reg         sd_dq_oe,
    input  wire [31:0] sd_dq_in
);
    // commands {ras, cas, we}
    localparam CMD_NOP = 3'b111, CMD_ACT = 3'b011, CMD_RD = 3'b101, CMD_WR = 3'b100,
               CMD_PRE = 3'b010, CMD_REF = 3'b001, CMD_MRS = 3'b000;

    localparam integer INIT_WAIT = FREQ / 5000;          // 200 us
    localparam integer REF_INT   = FREQ / 1000000 * 7;   // ~7 us (4096 / 64 ms needs 15.6)

    localparam S_INIT = 4'd0, S_PREA = 4'd1, S_REF1 = 4'd2, S_REF2 = 4'd3, S_MRS = 4'd4,
               S_IDLE = 4'd5, S_ACT = 4'd6, S_RW = 4'd7, S_WAIT = 4'd8, S_REF = 4'd9;

    reg [3:0]  st;
    reg [15:0] cnt;
    reg [15:0] ref_cnt;
    reg        ref_due;

    // latched request
    reg        p_pend, p_we;
    reg [AW-1:0] p_addr;
    reg [7:0]  p_wdata;
    reg [2:0]  rd_pipe;      // read data capture pipeline
    reg [1:0]  rd_byte;

    // address mapping: byte -> word (32 bit): col[7:0], row[10:0], bank[1:0]
    // (2M x 32 bit = 8 MB, 4 banks; smaller AW leaves the upper bank unused)
    wire [22:0] pa    = {{(23-AW){1'b0}}, p_addr};
    wire [22:0] ra    = {{(23-AW){1'b0}}, addr};
    wire [7:0]  col   = pa[9:2];
    wire [10:0] rowa  = pa[20:10];
    wire [1:0]  bank  = pa[22:21];

    assign ready = (st >= S_IDLE);

    task cmd;
        input [2:0] c;
        begin
            sd_cs_n <= 1'b0;
            {sd_ras_n, sd_cas_n, sd_we_n} <= c;
        end
    endtask

    always @(posedge clk) begin
        rvalid <= 1'b0;
        // capture requests at any time
        if (req) begin
            p_pend  <= 1'b1;
            p_we    <= we;
            p_addr  <= addr;
            p_wdata <= wdata;
        end
        // refresh timer
        if (ref_cnt == REF_INT[15:0]) begin
            ref_cnt <= 16'd0;
            ref_due <= 1'b1;
        end else
            ref_cnt <= ref_cnt + 16'd1;

        // read data capture (CAS latency 2, plus half cycle from inverted clock)
        rd_pipe <= {rd_pipe[1:0], 1'b0};
        if (rd_pipe[2]) begin
            rvalid <= 1'b1;
            case (rd_byte)
            2'd0: rdata <= sd_dq_in[7:0];
            2'd1: rdata <= sd_dq_in[15:8];
            2'd2: rdata <= sd_dq_in[23:16];
            default: rdata <= sd_dq_in[31:24];
            endcase
        end

        cmd(CMD_NOP);
        sd_dq_oe <= 1'b0;

        if (rst) begin
            st <= S_INIT; cnt <= 16'd0; sd_cke <= 1'b0; sd_cs_n <= 1'b1;
            {sd_ras_n, sd_cas_n, sd_we_n} <= CMD_NOP;
            sd_addr <= 11'd0; sd_ba <= 2'd0; sd_dqm <= 4'hF;
            p_pend <= 1'b0; ref_cnt <= 16'd0; ref_due <= 1'b0; rd_pipe <= 3'd0;
        end else begin
            case (st)
            S_INIT: begin
                sd_cke <= 1'b1;
                cnt <= cnt + 16'd1;
                if (cnt == INIT_WAIT[15:0]) begin st <= S_PREA; cnt <= 16'd0; end
            end
            S_PREA: begin
                cmd(CMD_PRE); sd_addr[10] <= 1'b1;       // precharge all
                st <= S_REF1; cnt <= 16'd0;
            end
            S_REF1, S_REF2: begin
                if (cnt == 16'd0) cmd(CMD_REF);
                cnt <= cnt + 16'd1;
                if (cnt == 16'd4) begin cnt <= 16'd0; st <= st + 4'd1; end
            end
            S_MRS: begin
                if (cnt == 16'd0) begin
                    cmd(CMD_MRS);
                    sd_ba   <= 2'b00;
                    // burst length 1, sequential, CAS latency 2, single write
                    sd_addr <= 11'b00_00_010_0_000;
                end
                cnt <= cnt + 16'd1;
                if (cnt == 16'd3) begin cnt <= 16'd0; st <= S_IDLE; end
            end
            S_IDLE: begin
                sd_dqm <= 4'hF;
                if (ref_due) begin
                    cmd(CMD_REF);
                    ref_due <= 1'b0;
                    st <= S_REF; cnt <= 16'd0;
                end else if (p_pend || req) begin
                    // use the incoming request directly if not yet latched
                    cmd(CMD_ACT);
                    sd_ba   <= req ? ra[22:21] : bank;
                    sd_addr <= req ? ra[20:10] : rowa;
                    st <= S_ACT;
                end
            end
            S_ACT: begin
                // tRCD = 15 ns < one cycle
                if (!req) p_pend <= 1'b0;
                sd_ba  <= bank;
                sd_addr <= {3'b100, col};               // A10 = auto precharge
                rd_byte <= p_addr[1:0];
                if (p_we) begin
                    cmd(CMD_WR);
                    sd_dq_oe  <= 1'b1;
                    sd_dq_out <= {4{p_wdata}};
                    sd_dqm <= ~(4'b0001 << p_addr[1:0]);
                end else begin
                    cmd(CMD_RD);
                    sd_dqm  <= 4'h0;
                    rd_pipe <= 3'b001;
                end
                st <= S_WAIT; cnt <= 16'd0;
            end
            S_WAIT: begin
                // write recovery + precharge / read completion
                cnt <= cnt + 16'd1;
                if (cnt == 16'd3) st <= S_IDLE;
            end
            S_REF: begin
                cnt <= cnt + 16'd1;
                if (cnt == 16'd3) st <= S_IDLE;
            end
            default: st <= S_INIT;
            endcase
        end
    end
endmodule

`default_nettype wire
