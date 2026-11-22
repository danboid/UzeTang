// Behavioural SDR SDRAM model (4 banks x 2K rows x 256 cols x 32 bit) for
// simulation. Commands are sampled on the rising edge of 'clk' (the SDRAM
// pin clock = inverted controller clock). CAS latency 2, burst length 1.
// Checks basic protocol rules (activate before read/write).
module sdram_model (
    input  wire        clk,
    input  wire        cke,
    input  wire        cs_n,
    input  wire        ras_n,
    input  wire        cas_n,
    input  wire        we_n,
    input  wire [10:0] addr,
    input  wire [1:0]  ba,
    input  wire [3:0]  dqm,
    input  wire [31:0] dq_in,      // from controller
    input  wire        dq_oe,      // controller drives the bus
    output reg  [31:0] dq_out,     // to controller
    output reg  [31:0] errors
);
    reg [31:0] mem [0:(1<<21)-1];   // 2M words = 8 MB
    reg [10:0] open_row [0:3];
    reg [3:0]  is_open;
    reg [1:0]  rd_ba [0:2];
    reg [7:0]  rd_col [0:2];
    reg [2:0]  rd_v;
    integer k;
    initial begin
        is_open = 0; rd_v = 0; errors = 0; dq_out = 32'hDEADBEEF;
        for (k = 0; k < (1<<21); k = k + 1) mem[k] = 32'h0;
    end
    wire [2:0] cmd = {ras_n, cas_n, we_n};
    always @(posedge clk) begin
        // read pipeline (CL2): data appears 2 edges after the READ
        rd_v <= {rd_v[1:0], 1'b0};
        if (rd_v[1])
            dq_out <= mem[{rd_ba[1], open_row[rd_ba[1]], rd_col[1]}];
        else
            dq_out <= 32'hDEADBEEF;
        rd_ba[1] <= rd_ba[0]; rd_col[1] <= rd_col[0];
        if (cke && !cs_n) begin
            case (cmd)
            3'b011: begin                        // ACTIVATE
                if (is_open[ba]) errors <= errors + 1;
                open_row[ba] <= addr;
                is_open[ba]  <= 1'b1;
            end
            3'b101: begin                        // READ
                if (!is_open[ba]) errors <= errors + 1;
                rd_v[0]   <= 1'b1;
                rd_ba[0]  <= ba;
                rd_col[0] <= addr[7:0];
                if (addr[10]) is_open[ba] <= 1'b0;   // auto precharge
            end
            3'b100: begin                        // WRITE
                if (!is_open[ba]) errors <= errors + 1;
                if (!dq_oe) errors <= errors + 1;
                for (k = 0; k < 4; k = k + 1)
                    if (!dqm[k]) mem[{ba, open_row[ba], addr[7:0]}][k*8 +: 8] <= dq_in[k*8 +: 8];
                if (addr[10]) is_open[ba] <= 1'b0;
            end
            3'b010: begin                        // PRECHARGE
                if (addr[10]) is_open <= 4'b0000; else is_open[ba] <= 1'b0;
            end
            3'b001: if (is_open != 0) errors <= errors + 1;   // REFRESH needs idle
            default: ;
            endcase
        end
    end
endmodule
