// Behavioural models of the Gowin primitives used by UzeTang, for Verilator.
// Only the configurations used here are modelled: DPB with 16 bit ports and
// SP with 8 bit port, bypass read mode, INIT_RAM honoured.
module DPB #(
    parameter READ_MODE0 = 1'b0, parameter READ_MODE1 = 1'b0,
    parameter WRITE_MODE0 = 2'b00, parameter WRITE_MODE1 = 2'b00,
    parameter BIT_WIDTH_0 = 16, parameter BIT_WIDTH_1 = 16,
    parameter BLK_SEL_0 = 3'b000, parameter BLK_SEL_1 = 3'b000,
    parameter [255:0] INIT_RAM_00 = 256'h0,
    parameter [255:0] INIT_RAM_01 = 256'h0,
    parameter [255:0] INIT_RAM_02 = 256'h0,
    parameter [255:0] INIT_RAM_03 = 256'h0,
    parameter [255:0] INIT_RAM_04 = 256'h0,
    parameter [255:0] INIT_RAM_05 = 256'h0,
    parameter [255:0] INIT_RAM_06 = 256'h0,
    parameter [255:0] INIT_RAM_07 = 256'h0,
    parameter [255:0] INIT_RAM_08 = 256'h0,
    parameter [255:0] INIT_RAM_09 = 256'h0,
    parameter [255:0] INIT_RAM_0A = 256'h0,
    parameter [255:0] INIT_RAM_0B = 256'h0,
    parameter [255:0] INIT_RAM_0C = 256'h0,
    parameter [255:0] INIT_RAM_0D = 256'h0,
    parameter [255:0] INIT_RAM_0E = 256'h0,
    parameter [255:0] INIT_RAM_0F = 256'h0,
    parameter [255:0] INIT_RAM_10 = 256'h0,
    parameter [255:0] INIT_RAM_11 = 256'h0,
    parameter [255:0] INIT_RAM_12 = 256'h0,
    parameter [255:0] INIT_RAM_13 = 256'h0,
    parameter [255:0] INIT_RAM_14 = 256'h0,
    parameter [255:0] INIT_RAM_15 = 256'h0,
    parameter [255:0] INIT_RAM_16 = 256'h0,
    parameter [255:0] INIT_RAM_17 = 256'h0,
    parameter [255:0] INIT_RAM_18 = 256'h0,
    parameter [255:0] INIT_RAM_19 = 256'h0,
    parameter [255:0] INIT_RAM_1A = 256'h0,
    parameter [255:0] INIT_RAM_1B = 256'h0,
    parameter [255:0] INIT_RAM_1C = 256'h0,
    parameter [255:0] INIT_RAM_1D = 256'h0,
    parameter [255:0] INIT_RAM_1E = 256'h0,
    parameter [255:0] INIT_RAM_1F = 256'h0,
    parameter [255:0] INIT_RAM_20 = 256'h0,
    parameter [255:0] INIT_RAM_21 = 256'h0,
    parameter [255:0] INIT_RAM_22 = 256'h0,
    parameter [255:0] INIT_RAM_23 = 256'h0,
    parameter [255:0] INIT_RAM_24 = 256'h0,
    parameter [255:0] INIT_RAM_25 = 256'h0,
    parameter [255:0] INIT_RAM_26 = 256'h0,
    parameter [255:0] INIT_RAM_27 = 256'h0,
    parameter [255:0] INIT_RAM_28 = 256'h0,
    parameter [255:0] INIT_RAM_29 = 256'h0,
    parameter [255:0] INIT_RAM_2A = 256'h0,
    parameter [255:0] INIT_RAM_2B = 256'h0,
    parameter [255:0] INIT_RAM_2C = 256'h0,
    parameter [255:0] INIT_RAM_2D = 256'h0,
    parameter [255:0] INIT_RAM_2E = 256'h0,
    parameter [255:0] INIT_RAM_2F = 256'h0,
    parameter [255:0] INIT_RAM_30 = 256'h0,
    parameter [255:0] INIT_RAM_31 = 256'h0,
    parameter [255:0] INIT_RAM_32 = 256'h0,
    parameter [255:0] INIT_RAM_33 = 256'h0,
    parameter [255:0] INIT_RAM_34 = 256'h0,
    parameter [255:0] INIT_RAM_35 = 256'h0,
    parameter [255:0] INIT_RAM_36 = 256'h0,
    parameter [255:0] INIT_RAM_37 = 256'h0,
    parameter [255:0] INIT_RAM_38 = 256'h0,
    parameter [255:0] INIT_RAM_39 = 256'h0,
    parameter [255:0] INIT_RAM_3A = 256'h0,
    parameter [255:0] INIT_RAM_3B = 256'h0,
    parameter [255:0] INIT_RAM_3C = 256'h0,
    parameter [255:0] INIT_RAM_3D = 256'h0,
    parameter [255:0] INIT_RAM_3E = 256'h0,
    parameter [255:0] INIT_RAM_3F = 256'h0,
    parameter RESET_MODE = "SYNC"
)(
    output reg  [15:0] DOA, DOB,
    input  wire CLKA, OCEA, CEA, RESETA, WREA,
    input  wire CLKB, OCEB, CEB, RESETB, WREB,
    input  wire [2:0]  BLKSELA, BLKSELB,
    input  wire [13:0] ADA, ADB,
    input  wire [15:0] DIA, DIB
);
    reg [15:0] mem [0:1023];
    integer r, k;
    reg [255:0] ir;
    initial for (r = 0; r < 64; r = r + 1) begin
        case (r[7:0])
        8'h00: ir = INIT_RAM_00;
        8'h01: ir = INIT_RAM_01;
        8'h02: ir = INIT_RAM_02;
        8'h03: ir = INIT_RAM_03;
        8'h04: ir = INIT_RAM_04;
        8'h05: ir = INIT_RAM_05;
        8'h06: ir = INIT_RAM_06;
        8'h07: ir = INIT_RAM_07;
        8'h08: ir = INIT_RAM_08;
        8'h09: ir = INIT_RAM_09;
        8'h0A: ir = INIT_RAM_0A;
        8'h0B: ir = INIT_RAM_0B;
        8'h0C: ir = INIT_RAM_0C;
        8'h0D: ir = INIT_RAM_0D;
        8'h0E: ir = INIT_RAM_0E;
        8'h0F: ir = INIT_RAM_0F;
        8'h10: ir = INIT_RAM_10;
        8'h11: ir = INIT_RAM_11;
        8'h12: ir = INIT_RAM_12;
        8'h13: ir = INIT_RAM_13;
        8'h14: ir = INIT_RAM_14;
        8'h15: ir = INIT_RAM_15;
        8'h16: ir = INIT_RAM_16;
        8'h17: ir = INIT_RAM_17;
        8'h18: ir = INIT_RAM_18;
        8'h19: ir = INIT_RAM_19;
        8'h1A: ir = INIT_RAM_1A;
        8'h1B: ir = INIT_RAM_1B;
        8'h1C: ir = INIT_RAM_1C;
        8'h1D: ir = INIT_RAM_1D;
        8'h1E: ir = INIT_RAM_1E;
        8'h1F: ir = INIT_RAM_1F;
        8'h20: ir = INIT_RAM_20;
        8'h21: ir = INIT_RAM_21;
        8'h22: ir = INIT_RAM_22;
        8'h23: ir = INIT_RAM_23;
        8'h24: ir = INIT_RAM_24;
        8'h25: ir = INIT_RAM_25;
        8'h26: ir = INIT_RAM_26;
        8'h27: ir = INIT_RAM_27;
        8'h28: ir = INIT_RAM_28;
        8'h29: ir = INIT_RAM_29;
        8'h2A: ir = INIT_RAM_2A;
        8'h2B: ir = INIT_RAM_2B;
        8'h2C: ir = INIT_RAM_2C;
        8'h2D: ir = INIT_RAM_2D;
        8'h2E: ir = INIT_RAM_2E;
        8'h2F: ir = INIT_RAM_2F;
        8'h30: ir = INIT_RAM_30;
        8'h31: ir = INIT_RAM_31;
        8'h32: ir = INIT_RAM_32;
        8'h33: ir = INIT_RAM_33;
        8'h34: ir = INIT_RAM_34;
        8'h35: ir = INIT_RAM_35;
        8'h36: ir = INIT_RAM_36;
        8'h37: ir = INIT_RAM_37;
        8'h38: ir = INIT_RAM_38;
        8'h39: ir = INIT_RAM_39;
        8'h3A: ir = INIT_RAM_3A;
        8'h3B: ir = INIT_RAM_3B;
        8'h3C: ir = INIT_RAM_3C;
        8'h3D: ir = INIT_RAM_3D;
        8'h3E: ir = INIT_RAM_3E;
        8'h3F: ir = INIT_RAM_3F;
        default: ir = 256'h0;
        endcase
        for (k = 0; k < 16; k = k + 1) mem[r * 16 + k] = ir[k * 16 +: 16];
    end
    always @(posedge CLKA) if (CEA) begin
        if (WREA) mem[ADA[13:4]] <= DIA;
        DOA <= mem[ADA[13:4]];
    end
    always @(posedge CLKB) if (CEB) begin
        if (WREB) mem[ADB[13:4]] <= DIB;
        DOB <= mem[ADB[13:4]];
    end
endmodule

module SP #(
    parameter READ_MODE = 1'b0, parameter WRITE_MODE = 2'b00,
    parameter BIT_WIDTH = 8, parameter BLK_SEL = 3'b000,
    parameter [255:0] INIT_RAM_00 = 256'h0,
    parameter [255:0] INIT_RAM_01 = 256'h0,
    parameter [255:0] INIT_RAM_02 = 256'h0,
    parameter [255:0] INIT_RAM_03 = 256'h0,
    parameter [255:0] INIT_RAM_04 = 256'h0,
    parameter [255:0] INIT_RAM_05 = 256'h0,
    parameter [255:0] INIT_RAM_06 = 256'h0,
    parameter [255:0] INIT_RAM_07 = 256'h0,
    parameter [255:0] INIT_RAM_08 = 256'h0,
    parameter [255:0] INIT_RAM_09 = 256'h0,
    parameter [255:0] INIT_RAM_0A = 256'h0,
    parameter [255:0] INIT_RAM_0B = 256'h0,
    parameter [255:0] INIT_RAM_0C = 256'h0,
    parameter [255:0] INIT_RAM_0D = 256'h0,
    parameter [255:0] INIT_RAM_0E = 256'h0,
    parameter [255:0] INIT_RAM_0F = 256'h0,
    parameter [255:0] INIT_RAM_10 = 256'h0,
    parameter [255:0] INIT_RAM_11 = 256'h0,
    parameter [255:0] INIT_RAM_12 = 256'h0,
    parameter [255:0] INIT_RAM_13 = 256'h0,
    parameter [255:0] INIT_RAM_14 = 256'h0,
    parameter [255:0] INIT_RAM_15 = 256'h0,
    parameter [255:0] INIT_RAM_16 = 256'h0,
    parameter [255:0] INIT_RAM_17 = 256'h0,
    parameter [255:0] INIT_RAM_18 = 256'h0,
    parameter [255:0] INIT_RAM_19 = 256'h0,
    parameter [255:0] INIT_RAM_1A = 256'h0,
    parameter [255:0] INIT_RAM_1B = 256'h0,
    parameter [255:0] INIT_RAM_1C = 256'h0,
    parameter [255:0] INIT_RAM_1D = 256'h0,
    parameter [255:0] INIT_RAM_1E = 256'h0,
    parameter [255:0] INIT_RAM_1F = 256'h0,
    parameter [255:0] INIT_RAM_20 = 256'h0,
    parameter [255:0] INIT_RAM_21 = 256'h0,
    parameter [255:0] INIT_RAM_22 = 256'h0,
    parameter [255:0] INIT_RAM_23 = 256'h0,
    parameter [255:0] INIT_RAM_24 = 256'h0,
    parameter [255:0] INIT_RAM_25 = 256'h0,
    parameter [255:0] INIT_RAM_26 = 256'h0,
    parameter [255:0] INIT_RAM_27 = 256'h0,
    parameter [255:0] INIT_RAM_28 = 256'h0,
    parameter [255:0] INIT_RAM_29 = 256'h0,
    parameter [255:0] INIT_RAM_2A = 256'h0,
    parameter [255:0] INIT_RAM_2B = 256'h0,
    parameter [255:0] INIT_RAM_2C = 256'h0,
    parameter [255:0] INIT_RAM_2D = 256'h0,
    parameter [255:0] INIT_RAM_2E = 256'h0,
    parameter [255:0] INIT_RAM_2F = 256'h0,
    parameter [255:0] INIT_RAM_30 = 256'h0,
    parameter [255:0] INIT_RAM_31 = 256'h0,
    parameter [255:0] INIT_RAM_32 = 256'h0,
    parameter [255:0] INIT_RAM_33 = 256'h0,
    parameter [255:0] INIT_RAM_34 = 256'h0,
    parameter [255:0] INIT_RAM_35 = 256'h0,
    parameter [255:0] INIT_RAM_36 = 256'h0,
    parameter [255:0] INIT_RAM_37 = 256'h0,
    parameter [255:0] INIT_RAM_38 = 256'h0,
    parameter [255:0] INIT_RAM_39 = 256'h0,
    parameter [255:0] INIT_RAM_3A = 256'h0,
    parameter [255:0] INIT_RAM_3B = 256'h0,
    parameter [255:0] INIT_RAM_3C = 256'h0,
    parameter [255:0] INIT_RAM_3D = 256'h0,
    parameter [255:0] INIT_RAM_3E = 256'h0,
    parameter [255:0] INIT_RAM_3F = 256'h0,
    parameter RESET_MODE = "SYNC"
)(
    output reg  [31:0] DO,
    input  wire [31:0] DI,
    input  wire [2:0]  BLKSEL,
    input  wire [13:0] AD,
    input  wire WRE, CLK, CE, OCE, RESET
);
    reg [7:0] mem [0:2047];
    integer r, k;
    reg [255:0] ir;
    initial for (r = 0; r < 64; r = r + 1) begin
        case (r[7:0])
        8'h00: ir = INIT_RAM_00;
        8'h01: ir = INIT_RAM_01;
        8'h02: ir = INIT_RAM_02;
        8'h03: ir = INIT_RAM_03;
        8'h04: ir = INIT_RAM_04;
        8'h05: ir = INIT_RAM_05;
        8'h06: ir = INIT_RAM_06;
        8'h07: ir = INIT_RAM_07;
        8'h08: ir = INIT_RAM_08;
        8'h09: ir = INIT_RAM_09;
        8'h0A: ir = INIT_RAM_0A;
        8'h0B: ir = INIT_RAM_0B;
        8'h0C: ir = INIT_RAM_0C;
        8'h0D: ir = INIT_RAM_0D;
        8'h0E: ir = INIT_RAM_0E;
        8'h0F: ir = INIT_RAM_0F;
        8'h10: ir = INIT_RAM_10;
        8'h11: ir = INIT_RAM_11;
        8'h12: ir = INIT_RAM_12;
        8'h13: ir = INIT_RAM_13;
        8'h14: ir = INIT_RAM_14;
        8'h15: ir = INIT_RAM_15;
        8'h16: ir = INIT_RAM_16;
        8'h17: ir = INIT_RAM_17;
        8'h18: ir = INIT_RAM_18;
        8'h19: ir = INIT_RAM_19;
        8'h1A: ir = INIT_RAM_1A;
        8'h1B: ir = INIT_RAM_1B;
        8'h1C: ir = INIT_RAM_1C;
        8'h1D: ir = INIT_RAM_1D;
        8'h1E: ir = INIT_RAM_1E;
        8'h1F: ir = INIT_RAM_1F;
        8'h20: ir = INIT_RAM_20;
        8'h21: ir = INIT_RAM_21;
        8'h22: ir = INIT_RAM_22;
        8'h23: ir = INIT_RAM_23;
        8'h24: ir = INIT_RAM_24;
        8'h25: ir = INIT_RAM_25;
        8'h26: ir = INIT_RAM_26;
        8'h27: ir = INIT_RAM_27;
        8'h28: ir = INIT_RAM_28;
        8'h29: ir = INIT_RAM_29;
        8'h2A: ir = INIT_RAM_2A;
        8'h2B: ir = INIT_RAM_2B;
        8'h2C: ir = INIT_RAM_2C;
        8'h2D: ir = INIT_RAM_2D;
        8'h2E: ir = INIT_RAM_2E;
        8'h2F: ir = INIT_RAM_2F;
        8'h30: ir = INIT_RAM_30;
        8'h31: ir = INIT_RAM_31;
        8'h32: ir = INIT_RAM_32;
        8'h33: ir = INIT_RAM_33;
        8'h34: ir = INIT_RAM_34;
        8'h35: ir = INIT_RAM_35;
        8'h36: ir = INIT_RAM_36;
        8'h37: ir = INIT_RAM_37;
        8'h38: ir = INIT_RAM_38;
        8'h39: ir = INIT_RAM_39;
        8'h3A: ir = INIT_RAM_3A;
        8'h3B: ir = INIT_RAM_3B;
        8'h3C: ir = INIT_RAM_3C;
        8'h3D: ir = INIT_RAM_3D;
        8'h3E: ir = INIT_RAM_3E;
        8'h3F: ir = INIT_RAM_3F;
        default: ir = 256'h0;
        endcase
        for (k = 0; k < 32; k = k + 1) mem[r * 32 + k] = ir[k * 8 +: 8];
    end
    always @(posedge CLK) if (CE) begin
        if (WRE) mem[AD[13:3]] <= DI[7:0];
        DO <= {24'd0, mem[AD[13:3]]};
    end
endmodule

module SDPB #(
    parameter READ_MODE = 1'b0, parameter BIT_WIDTH_0 = 8, parameter BIT_WIDTH_1 = 8,
    parameter BLK_SEL_0 = 3'b000, parameter BLK_SEL_1 = 3'b000, parameter RESET_MODE = "SYNC"
)(
    output reg  [31:0] DO,
    input  wire [31:0] DI,
    input  wire [13:0] ADA, ADB,
    input  wire CLKA, CEA, CLKB, CEB, OCE, RESETA, RESETB,
    input  wire [2:0] BLKSELA, BLKSELB
);
    reg [7:0] mem [0:2047];
    always @(posedge CLKA) if (CEA) mem[ADA[13:3]] <= DI[7:0];
    always @(posedge CLKB) if (CEB) DO <= {24'd0, mem[ADB[13:3]]};
endmodule
