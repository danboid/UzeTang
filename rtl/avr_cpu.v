// ============================================================================
//  avr_cpu.v - Cycle-exact ATmega644 compatible AVR CPU core for UzeTang
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  The instruction timing, and the exact cycle in which every instruction
//  reads or writes the I/O space and checks for interrupts, mirrors CUzeBox
//  (cu_avr.c / cu_avr_n.h by Sandor Zsuga), which is the reference Uzebox
//  emulator. One clock of 'clk' is one AVR cycle (28.63636 MHz on Uzebox).
//
//  Memory interfaces:
//   - Program memory delivers TWO consecutive words (pm_w0 = mem[pm_addr],
//     pm_w1 = mem[pm_addr+1]) one cycle after pm_addr is presented.
//   - Prefetch: when an instruction starts, its word and the following word
//     are already in registers (ir, ir1), so decoding starts straight from
//     flip-flops. The next instruction's two words are fetched in the
//     second-to-last cycle (all control flow takes >= 2 cycles; 1-cycle
//     instructions always continue at PC+1, whose words the previous
//     fetch already returned) and loaded in the last cycle.
//   - Data SRAM (4 KB) is synchronous: address in cycle N, data in cycle N+1.
//   - I/O reads (0x20-0xFF) are combinational, I/O writes take effect at the
//     clock edge ending the cycle in which io_we is asserted.
//
//  CUzeBox reference cycle model (per instruction):
//   - Every cycle ends with a "hardware tick" (timers etc. advance).
//   - Interrupts are checked at the start of the LAST cycle of an instruction
//     (UPDATE_HARDWARE_IT), and entered after the instruction completes
//     (3 extra cycles, then the vector instruction executes).
// ============================================================================

`default_nettype none

module avr_cpu (
    input  wire        clk,
    input  wire        ce,           // clock enable (pauses the whole AVR)
    input  wire        rst,          // synchronous reset (power-on)
    input  wire [15:0] rst_vec,      // reset vector (word address)

    // Program memory, port A (instruction fetch, 2 words wide)
    output reg  [15:0] pm_addr,
    input  wire [15:0] pm_w0,
    input  wire [15:0] pm_w1,

    // Program memory, port B (LPM byte read; data valid next cycle)
    output reg         lpm_en,
    output reg  [15:0] lpm_addr,
    input  wire [7:0]  lpm_data,

    // SPM request (asserted in first cycle of SPM instruction)
    output reg         spm_req,
    output wire [15:0] spm_z,
    output wire [15:0] spm_data,     // {r1, r0}

    // Data SRAM (4 KB, synchronous read)
    output reg  [11:0] dm_addr,
    output reg         dm_we,
    output reg  [7:0]  dm_wdata,
    input  wire [7:0]  dm_rdata,

    // I/O bus (data addresses 0x20..0xFF, excluding SPL/SPH/SREG)
    output reg  [7:0]  io_addr,
    output reg         io_re,        // read strobe (for read side effects)
    output reg         io_we,
    output reg  [7:0]  io_wdata,
    input  wire [7:0]  io_rdata,

    // Interrupt handshake with the peripheral block
    output reg         it_chk,       // this is the interrupt check cycle
    output reg         it_iflag,     // I flag as seen by the check
    input  wire        it_take,      // an interrupt will be entered
    input  wire [15:0] it_vec,       // its vector (word address)
    output reg         ev_now,       // event_it set before check (SEI)
    output reg         ev_late,      // event_it set after check (RETI, SREG write)
    input  wire [2:0]  io_stall,     // extra stall cycles requested by current I/O write

    input  wire        wdt_rst,      // watchdog reset (at this clock edge)
    output reg         wdr,          // WDR instruction executed (cycle 0)

    // Debug / trace
    output wire        cpu_run,      // 0 while the reset fetch sequence runs
    output wire        dbg_istart,   // first cycle of an instruction
    output wire [15:0] dbg_pc,
    output wire [7:0]  dbg_sreg,
    output wire [15:0] dbg_sp,
    output wire [255:0] dbg_regs
);

    // ------------------------------------------------------------------
    // Architectural state
    // ------------------------------------------------------------------
    reg [7:0]  r [0:31];
    reg [7:0]  sreg;
    reg [15:0] sp;
    reg [15:0] pc;

    localparam S_RESET = 2'd0, S_EXEC = 2'd1, S_INT = 2'd2, S_STALL = 2'd3;
    reg [1:0]  state;
    reg [1:0]  cyc;
    reg [15:0] ir, ir1;
    reg [2:0]  ncyc_r;
    reg [15:0] npc_r;
    reg [15:0] ea_r;
    reg [7:0]  tmp8;
    reg [7:0]  rethi, retlo;
    reg [2:0]  stall_cnt;
    reg        int_pend;     // enter interrupt after stall
    reg [15:0] vec_r;
    reg        rs_ph;        // reset fetch sequence phase

    assign spm_z    = {r[31], r[30]};
    assign spm_data = {r[1], r[0]};

    genvar gi;
    generate for (gi = 0; gi < 32; gi = gi + 1) begin : g_dbg
        assign dbg_regs[gi*8 +: 8] = r[gi];
    end endgenerate
    assign dbg_istart = (state == S_EXEC) && (cyc == 2'd0);
    assign dbg_pc     = pc;
    assign dbg_sreg   = sreg;
    assign dbg_sp     = sp;

    // ------------------------------------------------------------------
    // Current instruction words
    // ------------------------------------------------------------------
    wire        c0    = (cyc == 2'd0);
    wire [15:0] inst  = ir;       // current instruction (registered)
    wire [15:0] inst1 = ir1;      // word after it (registered)
    assign cpu_run = (state != S_RESET);

    // Field extraction
    wire [4:0]  f_d5  = inst[8:4];
    wire [4:0]  f_r5  = {inst[9], inst[3:0]};
    wire [4:0]  f_d4  = {1'b1, inst[7:4]};
    wire [7:0]  f_k8  = {inst[11:8], inst[3:0]};
    wire [7:0]  f_a6  = {2'b00, inst[10:9], inst[3:0]} + 8'h20;
    wire [7:0]  f_a5  = {3'b000, inst[7:3]} + 8'h20;
    wire [2:0]  f_b3  = inst[2:0];
    wire [7:0]  f_bm  = 8'h01 << inst[2:0];
    wire [5:0]  f_q6  = {inst[13], inst[11:10], inst[2:0]};

    // Is a word the first word of a 2-word instruction (LDS/STS/JMP/CALL)?
    function is32;
        input [15:0] w;
        begin
            is32 = ((w & 16'hFC0F) == 16'h9000) ||   // LDS / STS
                   ((w & 16'hFE0C) == 16'h940C);     // JMP / CALL
        end
    endfunction

    // ------------------------------------------------------------------
    // Decoder
    // ------------------------------------------------------------------
    localparam
        OP_NOP=7'd0,   OP_MOVW=7'd1, OP_MULS=7'd2,  OP_MULSU=7'd3, OP_FMUL=7'd4,
        OP_FMULS=7'd5, OP_FMULSU=7'd6, OP_CPC=7'd7, OP_SBC=7'd8,   OP_ADD=7'd9,
        OP_CPSE=7'd10, OP_CP=7'd11,  OP_SUB=7'd12,  OP_ADC=7'd13,  OP_AND=7'd14,
        OP_EOR=7'd15,  OP_OR=7'd16,  OP_MOV=7'd17,  OP_CPI=7'd18,  OP_SBCI=7'd19,
        OP_SUBI=7'd20, OP_ORI=7'd21, OP_ANDI=7'd22, OP_SPM=7'd23,  OP_LPM=7'd24,
        OP_LPMP=7'd25, OP_PUSH=7'd26, OP_POP=7'd27, OP_STS=7'd28,  OP_ST=7'd29,
        OP_LDS=7'd32,  OP_LD=7'd33,  OP_COM=7'd36,  OP_NEG=7'd37,  OP_SWAP=7'd38,
        OP_INC=7'd39,  OP_ASR=7'd40, OP_LSR=7'd41,  OP_ROR=7'd42,  OP_DEC=7'd43,
        OP_JMP=7'd44,  OP_CALL=7'd45, OP_BSET=7'd46, OP_BCLR=7'd47, OP_IJMP=7'd48,
        OP_RET=7'd49,  OP_ICALL=7'd50, OP_RETI=7'd51, OP_SLEEP=7'd52, OP_BREAK=7'd53,
        OP_WDR=7'd54,  OP_MUL=7'd55, OP_IN=7'd56,   OP_OUT=7'd57,  OP_ADIW=7'd58,
        OP_SBIW=7'd59, OP_CBI=7'd60, OP_SBIC=7'd61, OP_SBI=7'd62,  OP_SBIS=7'd63,
        OP_RJMP=7'd64, OP_RCALL=7'd65, OP_BRBS=7'd66, OP_BRBC=7'd67, OP_BLD=7'd68,
        OP_BST=7'd69,  OP_SBRC=7'd70, OP_SBRS=7'd71, OP_LDI=7'd72;

    reg [6:0] op;
    reg [4:0] ptr;     // pointer register (26 X, 28 Y, 30 Z) for LD/ST
    reg [1:0] pmode;   // 0: plain(+disp), 1: post-increment, 2: pre-decrement
    reg [5:0] disp;

    always @* begin
        op    = OP_NOP;
        ptr   = 5'd30;
        pmode = 2'd0;
        disp  = 6'd0;
        case (inst[15:10])
        6'h00: begin
            case (inst[9:8])
            2'd0: op = OP_NOP;   // NOP (and undefined 0000 0000 xxxx xxxx)
            2'd1: op = OP_MOVW;
            2'd2: op = OP_MULS;
            2'd3: case ({inst[7], inst[3]})
                    2'b00: op = OP_MULSU;
                    2'b01: op = OP_FMUL;
                    2'b10: op = OP_FMULS;
                    2'b11: op = OP_FMULSU;
                  endcase
            endcase
        end
        6'h01: op = OP_CPC;
        6'h02: op = OP_SBC;
        6'h03: op = OP_ADD;
        6'h04: op = OP_CPSE;
        6'h05: op = OP_CP;
        6'h06: op = OP_SUB;
        6'h07: op = OP_ADC;
        6'h08: op = OP_AND;
        6'h09: op = OP_EOR;
        6'h0A: op = OP_OR;
        6'h0B: op = OP_MOV;
        6'h0C, 6'h0D, 6'h0E, 6'h0F: op = OP_CPI;
        6'h10, 6'h11, 6'h12, 6'h13: op = OP_SBCI;
        6'h14, 6'h15, 6'h16, 6'h17: op = OP_SUBI;
        6'h18, 6'h19, 6'h1A, 6'h1B: op = OP_ORI;
        6'h1C, 6'h1D, 6'h1E, 6'h1F: op = OP_ANDI;
        6'h20, 6'h21, 6'h22, 6'h23, 6'h28, 6'h29, 6'h2A, 6'h2B: begin
            op    = inst[9] ? OP_ST : OP_LD;      // LDD / STD (incl. LD Y/Z)
            ptr   = inst[3] ? 5'd28 : 5'd30;
            disp  = f_q6;
            pmode = 2'd0;
        end
        6'h24: begin
            if (!inst[9]) begin
                case (inst[3:0])
                4'h0: op = OP_LDS;
                4'h1: begin op = OP_LD; ptr = 5'd30; pmode = 2'd1; end
                4'h2: begin op = OP_LD; ptr = 5'd30; pmode = 2'd2; end
                4'h4: op = OP_LPM;
                4'h5: op = OP_LPMP;
                4'h9: begin op = OP_LD; ptr = 5'd28; pmode = 2'd1; end
                4'hA: begin op = OP_LD; ptr = 5'd28; pmode = 2'd2; end
                4'hC: begin op = OP_LD; ptr = 5'd26; pmode = 2'd0; end
                4'hD: begin op = OP_LD; ptr = 5'd26; pmode = 2'd1; end
                4'hE: begin op = OP_LD; ptr = 5'd26; pmode = 2'd2; end
                4'hF: op = OP_POP;
                default: op = OP_NOP;
                endcase
            end else begin
                case (inst[3:0])
                4'h0: op = OP_STS;
                4'h1: begin op = OP_ST; ptr = 5'd30; pmode = 2'd1; end
                4'h2: begin op = OP_ST; ptr = 5'd30; pmode = 2'd2; end
                4'h9: begin op = OP_ST; ptr = 5'd28; pmode = 2'd1; end
                4'hA: begin op = OP_ST; ptr = 5'd28; pmode = 2'd2; end
                4'hC: begin op = OP_ST; ptr = 5'd26; pmode = 2'd0; end
                4'hD: begin op = OP_ST; ptr = 5'd26; pmode = 2'd1; end
                4'hE: begin op = OP_ST; ptr = 5'd26; pmode = 2'd2; end
                4'hF: op = OP_PUSH;
                default: op = OP_NOP;
                endcase
            end
        end
        6'h25: begin
            if (!inst[9]) begin
                case (inst[3:0])
                4'h0: op = OP_COM;
                4'h1: op = OP_NEG;
                4'h2: op = OP_SWAP;
                4'h3: op = OP_INC;
                4'h5: op = OP_ASR;
                4'h6: op = OP_LSR;
                4'h7: op = OP_ROR;
                4'h8: begin
                    if (!inst[8]) op = inst[7] ? OP_BCLR : OP_BSET;
                    else case (inst[7:4])
                        4'h0: op = OP_RET;
                        4'h1: op = OP_RETI;
                        4'h8: op = OP_SLEEP;
                        4'h9: op = OP_BREAK;
                        4'hA: op = OP_WDR;
                        4'hC: begin op = OP_LPM; end   // LPM (r0 implied)
                        4'hE: op = OP_SPM;
                        default: op = OP_NOP;
                    endcase
                end
                4'h9: op = inst[8] ? OP_ICALL : OP_IJMP;
                4'hA: op = OP_DEC;
                4'hC, 4'hD: op = OP_JMP;
                4'hE, 4'hF: op = OP_CALL;
                default: op = OP_NOP;
                endcase
            end else begin
                op = inst[8] ? OP_SBIW : OP_ADIW;
            end
        end
        6'h26: case (inst[9:8])
                2'd0: op = OP_CBI;
                2'd1: op = OP_SBIC;
                2'd2: op = OP_SBI;
                2'd3: op = OP_SBIS;
               endcase
        6'h27: op = OP_MUL;
        6'h2C, 6'h2D: op = OP_IN;
        6'h2E, 6'h2F: op = OP_OUT;
        6'h30, 6'h31, 6'h32, 6'h33: op = OP_RJMP;
        6'h34, 6'h35, 6'h36, 6'h37: op = OP_RCALL;
        6'h38, 6'h39, 6'h3A, 6'h3B: op = OP_LDI;
        6'h3C: op = OP_BRBS;
        6'h3D: op = OP_BRBC;
        6'h3E: op = inst[9] ? OP_BST : OP_BLD;
        6'h3F: op = inst[9] ? OP_SBRS : OP_SBRC;
        default: op = OP_NOP;
        endcase
    end

    // LPM r0 form: destination r0, else Rd
    wire        lpm_r0 = (inst[15:9] == 7'b1001010);
    wire [4:0]  lpm_rd = lpm_r0 ? 5'd0 : f_d5;

    // ------------------------------------------------------------------
    // Operand fetch
    // ------------------------------------------------------------------
    // Destination and source register selection depends on instruction
    reg  [4:0] sel_d, sel_r;
    always @* begin
        sel_d = f_d5;
        sel_r = f_r5;
        case (op)
        OP_MULS:  begin sel_d = f_d4; sel_r = {1'b1, inst[3:0]}; end
        OP_MULSU, OP_FMUL, OP_FMULS, OP_FMULSU:
                  begin sel_d = {2'b10, inst[6:4]}; sel_r = {2'b10, inst[2:0]}; end
        OP_CPI, OP_SBCI, OP_SUBI, OP_ORI, OP_ANDI, OP_LDI:
                  sel_d = f_d4;
        OP_MOVW:  begin sel_d = {inst[7:4], 1'b0}; sel_r = {inst[3:0], 1'b0}; end
        OP_ADIW, OP_SBIW:
                  sel_d = {2'b11, inst[5:4], 1'b0};
        default: ;
        endcase
    end

    // Two 16 bit register pair read ports; byte operands are selected from
    // them (cheaper than four 8 bit 32:1 ports). In cycle 1 of LD/LDS the
    // second port reads the register-space load address.
    reg  [4:0]  sel_r2;
    always @* sel_r2 = ((op == OP_LD || op == OP_LDS) && !c0) ? ea_r[4:0] : sel_r;
    wire [15:0] Pd   = {r[{sel_d[4:1], 1'b1}],  r[{sel_d[4:1], 1'b0}]};
    wire [15:0] Pr   = {r[{sel_r2[4:1], 1'b1}], r[{sel_r2[4:1], 1'b0}]};
    wire [7:0]  Rd   = sel_d[0]  ? Pd[15:8] : Pd[7:0];
    wire [7:0]  Rr   = sel_r2[0] ? Pr[15:8] : Pr[7:0];
    wire [7:0]  Rd1  = Pd[15:8];
    wire [7:0]  Rr1  = Pr[15:8];
    wire [15:0] Xp   = {r[27], r[26]};
    wire [15:0] Yp   = {r[29], r[28]};
    wire [15:0] Zp   = {r[31], r[30]};
    reg  [15:0] Pv;
    always @* case (ptr)
        5'd26:   Pv = Xp;
        5'd28:   Pv = Yp;
        default: Pv = Zp;
    endcase

    wire cflag = sreg[0];

    // ------------------------------------------------------------------
    // 8-bit ALU (combinational, for 1-cycle arithmetic/logic ops)
    // ------------------------------------------------------------------
    reg [7:0] alu_a, alu_b;
    reg       alu_cin;
    wire [7:0] add_r = alu_a + alu_b + {7'd0, alu_cin};
    wire [7:0] sub_r = alu_a - alu_b - {7'd0, alu_cin};
    wire add_h = (alu_a[3] & alu_b[3]) | (alu_b[3] & ~add_r[3]) | (~add_r[3] & alu_a[3]);
    wire add_v = (alu_a[7] & alu_b[7] & ~add_r[7]) | (~alu_a[7] & ~alu_b[7] & add_r[7]);
    wire add_c = (alu_a[7] & alu_b[7]) | (alu_b[7] & ~add_r[7]) | (~add_r[7] & alu_a[7]);
    wire sub_h = (~alu_a[3] & alu_b[3]) | (alu_b[3] & sub_r[3]) | (sub_r[3] & ~alu_a[3]);
    wire sub_v = (alu_a[7] & ~alu_b[7] & ~sub_r[7]) | (~alu_a[7] & alu_b[7] & sub_r[7]);
    wire sub_c = (~alu_a[7] & alu_b[7]) | (alu_b[7] & sub_r[7]) | (sub_r[7] & ~alu_a[7]);

    // Multiplier (shared by MUL family)
    reg  signed [8:0] mul_a, mul_b;
    wire signed [17:0] mul_p = mul_a * mul_b;

    // ALU operand selection
    always @* begin
        alu_a = Rd; alu_b = Rr; alu_cin = 1'b0;
        case (op)
        OP_ADC:                      alu_cin = cflag;
        OP_SUBI, OP_CPI:             alu_b = f_k8;
        OP_SBCI:            begin    alu_b = f_k8; alu_cin = cflag; end
        OP_SBC, OP_CPC:              alu_cin = cflag;
        OP_NEG:             begin    alu_a = 8'd0; alu_b = Rd; end
        default: ;
        endcase
        case (op)
        OP_MULS, OP_FMULS:   begin mul_a = {Rd[7], Rd}; mul_b = {Rr[7], Rr}; end
        OP_MULSU, OP_FMULSU: begin mul_a = {Rd[7], Rd}; mul_b = {1'b0,  Rr}; end
        default:             begin mul_a = {1'b0,  Rd}; mul_b = {1'b0,  Rr}; end
        endcase
    end

    // 16-bit word add/sub for ADIW / SBIW
    wire [15:0] wdst  = {Rd1, Rd};
    wire [5:0]  wk    = {inst[7:6], inst[3:0]};
    wire [15:0] wadd  = wdst + {10'd0, wk};
    wire [15:0] wsub  = wdst - {10'd0, wk};

    // ------------------------------------------------------------------
    // Main combinational control
    // ------------------------------------------------------------------
    // Register file write ports: pair (16 bit, applied first) and single
    reg        rf_wep;  reg [4:0] rf_wap; reg [15:0] rf_wdp;
    reg        rf_we1;  reg [4:0] rf_wa1; reg [7:0]  rf_wd1;
    reg [7:0]  sreg_n;
    reg [15:0] sp_n;
    reg        last;          // last cycle of this instruction
    reg [2:0]  ncyc_c;        // cycle count (valid in cycle 0)
    reg [15:0] npc_c;         // next PC (valid in cycle 0, except RET)
    reg [15:0] ea_n;
    reg [7:0]  tmp8_n;
    reg [7:0]  rethi_n, retlo_n;
    reg [7:0]  ld_val;        // value loaded by LD/LDS in cycle 1
    reg        no_chk;        // instruction never takes an interrupt (SEI, RETI)

    // value read from the data space at ea_r (cycle 1 of LD/LDS)
    always @* begin
        if (ea_r < 16'h0020)        ld_val = Rr;      // register space via port 2
        else if (ea_r < 16'h0100) begin
            case (ea_r[7:0])
            8'h5D:   ld_val = sp[7:0];
            8'h5E:   ld_val = sp[15:8];
            8'h5F:   ld_val = sreg;
            default: ld_val = io_rdata;
            endcase
        end else                    ld_val = dm_rdata;
    end

    // I/O read value for IN instruction (CPU-internal registers muxed in)
    reg [7:0] in_val;
    always @* begin
        case (f_a6)
        8'h5D:   in_val = sp[7:0];
        8'h5E:   in_val = sp[15:8];
        8'h5F:   in_val = sreg;
        default: in_val = io_rdata;
        endcase
    end

    wire [15:0] pc1 = pc + 16'd1;
    wire [15:0] pc2 = pc + 16'd2;
    wire [15:0] pc3 = pc + 16'd3;

    // I/O address / read strobe (separate block: no dependency on io_rdata)
    always @* begin
        io_addr = 8'd0;
        io_re   = 1'b0;
        if (state == S_EXEC) begin
            case (op)
            OP_IN:  begin io_addr = f_a6; io_re = 1'b1; end
            OP_OUT:       io_addr = f_a6;
            OP_SBIC, OP_SBIS: begin io_addr = f_a5; io_re = c0; end
            OP_CBI, OP_SBI:   begin io_addr = f_a5; io_re = c0; end
            OP_LD, OP_LDS: if (!c0) begin
                io_addr = ea_r[7:0];
                io_re   = (ea_r >= 16'h0020) && (ea_r < 16'h0100);
            end
            OP_ST, OP_STS: if (!c0) io_addr = ea_r[7:0];
            default: ;
            endcase
        end
    end

    // BSET/BCLR bit mask (bits 6:4)
    wire [7:0] f_bm_s = 8'h01 << inst[6:4];

    // high byte of return address for calls (stable across cycles)
    reg [7:0] npc_ra_hi;
    always @* npc_ra_hi = (op == OP_CALL) ? pc2[15:8] : pc1[15:8];

    always @* begin
        // defaults
        rf_wep = 1'b0; rf_wap = 5'd0;  rf_wdp = 16'd0;
        rf_we1 = 1'b0; rf_wa1 = 5'd0;  rf_wd1 = 8'd0;
        sreg_n = sreg;
        sp_n   = sp;
        last   = 1'b1;
        ncyc_c = 3'd1;
        npc_c  = pc1;
        ea_n   = ea_r;
        tmp8_n = tmp8;
        rethi_n = rethi;
        retlo_n = retlo;
        dm_addr = 12'd0; dm_we = 1'b0; dm_wdata = 8'd0;
        io_we = 1'b0; io_wdata = 8'd0;
        lpm_en = 1'b0;   lpm_addr = Zp;
        spm_req = 1'b0;
        wdr = 1'b0;
        ev_now = 1'b0; ev_late = 1'b0;
        it_chk = 1'b0; it_iflag = sreg[7];
        no_chk = 1'b0;

        if (state == S_EXEC) begin
            case (op)
            // ---------------------------------------------- 1 cycle ops
            OP_NOP, OP_SLEEP, OP_BREAK: ;
            OP_WDR: if (c0) wdr = 1'b1;
            OP_MOVW: begin
                rf_wep = 1'b1; rf_wap = sel_d; rf_wdp = {Rr1, Rr};
            end
            OP_MOV: begin
                rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = Rr;
            end
            OP_LDI: begin
                rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = f_k8;
            end
            OP_ADD, OP_ADC: begin
                rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = add_r;
                sreg_n[5] = add_h; sreg_n[3] = add_v; sreg_n[2] = add_r[7];
                sreg_n[1] = (add_r == 8'd0); sreg_n[0] = add_c;
                sreg_n[4] = add_r[7] ^ add_v;
            end
            OP_SUB, OP_SUBI, OP_CP, OP_CPI, OP_SBC, OP_SBCI, OP_CPC, OP_NEG: begin
                if (op != OP_CP && op != OP_CPI && op != OP_CPC) begin
                    rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = sub_r;
                end
                sreg_n[5] = sub_h; sreg_n[3] = sub_v; sreg_n[2] = sub_r[7];
                sreg_n[0] = sub_c; sreg_n[4] = sub_r[7] ^ sub_v;
                if (op == OP_SBC || op == OP_SBCI || op == OP_CPC)
                    sreg_n[1] = sreg[1] & (sub_r == 8'd0);
                else
                    sreg_n[1] = (sub_r == 8'd0);
            end
            OP_AND, OP_ANDI, OP_OR, OP_ORI, OP_EOR: begin : logic_blk
                reg [7:0] lr;
                case (op)
                OP_AND:  lr = Rd & Rr;
                OP_ANDI: lr = Rd & f_k8;
                OP_OR:   lr = Rd | Rr;
                OP_ORI:  lr = Rd | f_k8;
                default: lr = Rd ^ Rr;
                endcase
                rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = lr;
                sreg_n[3] = 1'b0; sreg_n[2] = lr[7]; sreg_n[1] = (lr == 8'd0);
                sreg_n[4] = lr[7];
            end
            OP_COM: begin : com_blk
                reg [7:0] lr;
                lr = ~Rd;
                rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = lr;
                sreg_n[3] = 1'b0; sreg_n[2] = lr[7]; sreg_n[1] = (lr == 8'd0);
                sreg_n[4] = lr[7]; sreg_n[0] = 1'b1;
            end
            OP_SWAP: begin
                rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = {Rd[3:0], Rd[7:4]};
            end
            OP_INC, OP_DEC: begin : incdec_blk
                reg [7:0] lr; reg v;
                lr = (op == OP_INC) ? Rd + 8'd1 : Rd - 8'd1;
                v  = (op == OP_INC) ? (lr == 8'h80) : (lr == 8'h7F);
                rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = lr;
                sreg_n[3] = v; sreg_n[2] = lr[7]; sreg_n[1] = (lr == 8'd0);
                sreg_n[4] = lr[7] ^ v;
            end
            OP_ASR, OP_LSR, OP_ROR: begin : shr_blk
                reg [7:0] lr; reg n, c, v;
                case (op)
                OP_ASR:  lr = {Rd[7], Rd[7:1]};
                OP_LSR:  lr = {1'b0,  Rd[7:1]};
                default: lr = {cflag, Rd[7:1]};
                endcase
                c = Rd[0]; n = lr[7]; v = n ^ c;
                rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = lr;
                sreg_n[0] = c; sreg_n[2] = n; sreg_n[3] = v; sreg_n[4] = n ^ v;
                sreg_n[1] = (lr == 8'd0);
            end
            OP_BSET: begin
                sreg_n = sreg | f_bm_s;
                if (inst[6:4] == 3'd7) begin
                    // SEI: the following instruction always executes before
                    // an interrupt (real AVR, CUzeBox-ex): no check here
                    no_chk  = 1'b1;
                    ev_late = 1'b1;
                end
                it_iflag = sreg_n[7];
            end
            OP_BCLR: begin
                sreg_n = sreg & ~f_bm_s;
                it_iflag = sreg_n[7];
            end
            OP_BLD: begin
                rf_we1 = 1'b1; rf_wa1 = sel_d;
                rf_wd1 = (Rd & ~f_bm) | (sreg[6] ? f_bm : 8'd0);
            end
            OP_BST: begin
                sreg_n[6] = |(Rd & f_bm);
            end
            OP_IN: begin
                rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = in_val;
            end
            OP_OUT: begin
                case (f_a6)
                8'h5D: sp_n[7:0]  = Rd;
                8'h5E: sp_n[15:8] = Rd;
                8'h5F: begin
                    sreg_n = Rd;
                    if (Rd[7] && !sreg[7]) ev_late = 1'b1;
                end
                default: begin
                    io_we = 1'b1; io_wdata = Rd;
                end
                endcase
            end
            // ------------------------------------------- branches / skips
            OP_BRBS, OP_BRBC: begin : br_blk
                reg take;
                take = (op == OP_BRBS) ? |(sreg & f_bm) : ~|(sreg & f_bm);
                if (take) begin
                    ncyc_c = 3'd2;
                    npc_c  = pc1 + {{9{inst[9]}}, inst[9:3]};
                end
            end
            OP_CPSE, OP_SBRC, OP_SBRS, OP_SBIC, OP_SBIS: begin : skip_blk
                reg sk;
                case (op)
                OP_CPSE: sk = (Rd == Rr);
                OP_SBRC: sk = ~|(Rd & f_bm);
                OP_SBRS: sk =  |(Rd & f_bm);
                OP_SBIC: sk = ~|(io_rdata & f_bm);
                default: sk =  |(io_rdata & f_bm);
                endcase
                if (sk) begin
                    if (is32(inst1)) begin ncyc_c = 3'd3; npc_c = pc3; end
                    else             begin ncyc_c = 3'd2; npc_c = pc2; end
                end
            end
            OP_RJMP: begin
                ncyc_c = 3'd2;
                npc_c  = pc1 + {{4{inst[11]}}, inst[11:0]};
            end
            OP_IJMP: begin
                ncyc_c = 3'd2;
                npc_c  = Zp;
            end
            OP_JMP: begin
                ncyc_c = 3'd3;
                npc_c  = inst1;
            end
            // ------------------------------------------------ calls
            OP_RCALL, OP_ICALL, OP_CALL: begin : call_blk
                reg [15:0] ra;
                ra = (op == OP_CALL) ? pc2 : pc1;
                ncyc_c = (op == OP_CALL) ? 3'd4 : 3'd3;
                case (op)
                OP_RCALL: npc_c = pc1 + {{4{inst[11]}}, inst[11:0]};
                OP_ICALL: npc_c = Zp;
                default:  npc_c = inst1;
                endcase
                if (cyc == 2'd0) begin
                    dm_addr = sp[11:0]; dm_we = 1'b1; dm_wdata = ra[7:0];
                end else if (cyc == 2'd1) begin
                    dm_addr = sp[11:0] - 12'd1; dm_we = 1'b1; dm_wdata = npc_ra_hi;
                    sp_n = sp - 16'd2;
                end
            end
            OP_RET, OP_RETI: begin
                ncyc_c = 3'd4;
                if (op == OP_RETI) no_chk = 1'b1;   // one instruction runs after RETI
                case (cyc)
                2'd0: begin
                    dm_addr = sp[11:0] + 12'd1;
                    if (op == OP_RETI) begin
                        sreg_n[7] = 1'b1;
                        ev_late   = 1'b1;
                    end
                end
                2'd1: begin
                    rethi_n = dm_rdata;
                    dm_addr = sp[11:0] + 12'd2;
                    sp_n    = sp + 16'd2;
                end
                2'd2: retlo_n = dm_rdata;
                default: ;
                endcase
            end
            // ---------------------------------------------- 2 cycle ops
            OP_MUL, OP_MULS, OP_MULSU, OP_FMUL, OP_FMULS, OP_FMULSU: begin : mul_blk
                reg [15:0] p;
                ncyc_c = 3'd2;
                if (op == OP_FMUL || op == OP_FMULS || op == OP_FMULSU) begin
                    p = {mul_p[14:0], 1'b0};
                    sreg_n[0] = mul_p[15];
                end else begin
                    p = mul_p[15:0];
                    sreg_n[0] = mul_p[15];
                end
                sreg_n[1] = (p == 16'd0);
                if (c0) begin
                    rf_wep = 1'b1; rf_wap = 5'd0; rf_wdp = p;
                end else begin
                    sreg_n = sreg;   // flags written once (cycle 0)
                end
            end
            OP_ADIW, OP_SBIW: begin : adiw_blk
                reg [15:0] res; reg v, c;
                ncyc_c = 3'd2;
                if (op == OP_ADIW) begin
                    res = wadd; v = ~wdst[15] & res[15]; c = ~res[15] & wdst[15];
                end else begin
                    res = wsub; v = wdst[15] & ~res[15]; c = res[15] & ~wdst[15];
                end
                if (c0) begin
                    rf_wep = 1'b1; rf_wap = sel_d; rf_wdp = res;
                    sreg_n[0] = c; sreg_n[1] = (res == 16'd0); sreg_n[2] = res[15];
                    sreg_n[3] = v; sreg_n[4] = res[15] ^ v;
                end
            end
            OP_PUSH: begin
                ncyc_c = 3'd2;
                if (c0) begin
                    dm_addr = sp[11:0]; dm_we = 1'b1; dm_wdata = Rd;
                    sp_n = sp - 16'd1;
                end
            end
            OP_POP: begin
                ncyc_c = 3'd2;
                if (c0) begin
                    dm_addr = sp[11:0] + 12'd1;
                    sp_n = sp + 16'd1;
                end else begin
                    rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = dm_rdata;
                end
            end
            OP_LD, OP_LDS: begin
                ncyc_c = 3'd2;
                if (op == OP_LDS) npc_c = pc2;
                if (c0) begin
                    if (op == OP_LDS)        ea_n = inst1;
                    else if (pmode == 2'd2)  ea_n = Pv - 16'd1;
                    else                     ea_n = Pv + {10'd0, disp};
                    if (op == OP_LD && pmode == 2'd1) begin
                        rf_wep = 1'b1; rf_wap = ptr; rf_wdp = Pv + 16'd1;
                    end
                    if (op == OP_LD && pmode == 2'd2) begin
                        rf_wep = 1'b1; rf_wap = ptr; rf_wdp = Pv - 16'd1;
                    end
                    dm_addr = ea_n[11:0];
                end else begin
                    rf_we1 = 1'b1; rf_wa1 = sel_d; rf_wd1 = ld_val;
                end
            end
            OP_ST, OP_STS: begin
                ncyc_c = 3'd2;
                if (op == OP_STS) npc_c = pc2;
                if (c0) begin
                    if (op == OP_STS)        ea_n = inst1;
                    else if (pmode == 2'd2)  ea_n = Pv - 16'd1;
                    else                     ea_n = Pv + {10'd0, disp};
                    if (op == OP_ST && pmode == 2'd1) begin
                        rf_wep = 1'b1; rf_wap = ptr; rf_wdp = Pv + 16'd1;
                    end
                    if (op == OP_ST && pmode == 2'd2) begin
                        rf_wep = 1'b1; rf_wap = ptr; rf_wdp = Pv - 16'd1;
                    end
                end else begin
                    if (ea_r >= 16'h0100) begin
                        dm_addr = ea_r[11:0]; dm_we = 1'b1; dm_wdata = Rd;
                    end else if (ea_r < 16'h0020) begin
                        rf_we1 = 1'b1; rf_wa1 = ea_r[4:0]; rf_wd1 = Rd;
                    end else begin
                        case (ea_r[7:0])
                        8'h5D: sp_n[7:0]  = Rd;
                        8'h5E: sp_n[15:8] = Rd;
                        8'h5F: begin
                            sreg_n = Rd;
                            if (Rd[7] && !sreg[7]) ev_late = 1'b1;
                        end
                        default: begin
                            io_we = 1'b1; io_wdata = Rd;
                        end
                        endcase
                    end
                end
            end
            OP_CBI, OP_SBI: begin
                ncyc_c = 3'd2;
                if (c0) begin
                    // On PINx, SBI/CBI write only the selected bit (a one
                    // toggles PORTx); elsewhere read-modify-write.
                    if (f_a5 == 8'h20 || f_a5 == 8'h23 || f_a5 == 8'h26 || f_a5 == 8'h29)
                        tmp8_n = (op == OP_SBI) ? f_bm : 8'h00;
                    else
                        tmp8_n = (op == OP_SBI) ? (io_rdata | f_bm) : (io_rdata & ~f_bm);
                end else begin
                    io_we = 1'b1; io_wdata = tmp8;
                end
            end
            // ---------------------------------------------- 3/4 cycle ops
            OP_LPM, OP_LPMP: begin
                ncyc_c = 3'd3;
                if (c0) begin
                    lpm_en = 1'b1; lpm_addr = Zp;
                    if (op == OP_LPMP) begin
                        rf_wep = 1'b1; rf_wap = 5'd30; rf_wdp = Zp + 16'd1;
                    end
                end else if (cyc == 2'd1) begin
                    rf_we1 = 1'b1; rf_wa1 = lpm_rd; rf_wd1 = lpm_data;
                end
            end
            OP_SPM: begin
                ncyc_c = 3'd4;
                if (c0) spm_req = 1'b1;
            end
            default: ;
            endcase

            // cycle bookkeeping
            last = c0 ? (ncyc_c == 3'd1) : ({1'b0, cyc} == ncyc_r - 3'd1);
            if (last && !no_chk) it_chk = 1'b1;
        end else if (state == S_INT) begin
            last = (cyc == 2'd2);
            if (cyc == 2'd0) begin
                dm_addr = sp[11:0]; dm_we = 1'b1; dm_wdata = pc[7:0];
                sreg_n[7] = 1'b0;
            end else if (cyc == 2'd1) begin
                dm_addr = sp[11:0] - 12'd1; dm_we = 1'b1; dm_wdata = pc[15:8];
                sp_n = sp - 16'd2;
            end
        end
    end

    // Next PC when the instruction ends
    wire is_ret = (op == OP_RET) || (op == OP_RETI);
    wire [15:0] npc_final = is_ret ? {rethi, retlo} : (c0 ? npc_c : npc_r);

    // ------------------------------------------------------------------
    // Program memory address (see prefetch scheme in the header)
    // ------------------------------------------------------------------
    wire [15:0] npc_early = (is_ret && cyc == 2'd2) ? {rethi, dm_rdata} :
                            (c0 ? npc_c : npc_r);
    always @* begin
        case (state)
        S_RESET: pm_addr = rs_ph ? rst_vec + 16'd1 : rst_vec;
        S_EXEC:  pm_addr = last ? npc_final + 16'd1 : npc_early;
        S_INT:   pm_addr = (cyc == 2'd2) ? vec_r + 16'd1 : vec_r;
        default: pm_addr = pc + 16'd1;        // stall: keep words of pc+1
        endcase
    end

    // ------------------------------------------------------------------
    // Sequential
    // ------------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (rst || (ce && wdt_rst)) begin
            for (i = 0; i < 32; i = i + 1) r[i] <= 8'd0;
            sreg     <= 8'd0;
            sp       <= 16'h10FF;
            pc       <= rst_vec;
            state    <= S_RESET;
            rs_ph    <= 1'b0;
            cyc      <= 2'd0;
            ir       <= 16'd0;
            ir1      <= 16'd0;
            ncyc_r   <= 3'd1;
            npc_r    <= 16'd0;
            ea_r     <= 16'd0;
            tmp8     <= 8'd0;
            rethi    <= 8'd0;
            retlo    <= 8'd0;
            stall_cnt<= 3'd0;
            int_pend <= 1'b0;
            vec_r    <= 16'd0;
        end else if (ce) begin
            // register file writes
            if (rf_wep) begin
                r[{rf_wap[4:1], 1'b0}] <= rf_wdp[7:0];
                r[{rf_wap[4:1], 1'b1}] <= rf_wdp[15:8];
            end
            if (rf_we1) r[rf_wa1] <= rf_wd1;
            sreg   <= sreg_n;
            sp     <= sp_n;
            ea_r   <= ea_n;
            tmp8   <= tmp8_n;
            rethi  <= rethi_n;
            retlo  <= retlo_n;

            case (state)
            S_RESET: begin
                // phase 0: fetch rst_vec; phase 1: load it, fetch rst_vec+1
                rs_ph <= 1'b1;
                if (rs_ph) begin
                    ir    <= pm_w0;
                    ir1   <= pm_w1;
                    state <= S_EXEC;
                    cyc   <= 2'd0;
                    pc    <= rst_vec;
                end
            end
            S_EXEC: begin
                if (c0) begin
                    ncyc_r <= ncyc_c;
                    npc_r  <= npc_c;
                end
                if (last) begin
                    ir  <= pm_w0;            // next instruction's words
                    ir1 <= pm_w1;
                    pc  <= npc_final;
                    cyc <= 2'd0;
                    if (io_stall != 3'd0) begin
                        state     <= S_STALL;
                        stall_cnt <= io_stall;
                        int_pend  <= it_take;
                        vec_r     <= it_vec;
                    end else if (it_take) begin
                        state <= S_INT;
                        vec_r <= it_vec;
                    end
                end else begin
                    cyc <= cyc + 2'd1;
                end
            end
            S_INT: begin
                if (last) begin
                    ir    <= pm_w0;
                    ir1   <= pm_w1;
                    state <= S_EXEC;
                    cyc   <= 2'd0;
                    pc    <= vec_r;
                end else begin
                    cyc <= cyc + 2'd1;
                end
            end
            S_STALL: begin
                if (stall_cnt == 3'd1) begin
                    state <= int_pend ? S_INT : S_EXEC;
                    cyc   <= 2'd0;
                end
                stall_cnt <= stall_cnt - 3'd1;
            end
            endcase
        end
    end

endmodule

`default_nettype wire
