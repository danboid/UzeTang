// ============================================================================
//  avr_io.v - ATmega644 I/O space and peripherals for UzeTang
//
//  Copyright (C) 2026 UzeTang contributors
//  Licensed under the GNU General Public License v3 or later.
//
//  Peripheral behaviour mirrors CUzeBox (cu_avr.c, Sandor Zsuga), evaluated
//  once per clock (= AVR cycle). Within a clock edge the update order is the
//  same as CUzeBox: (1) interrupt check / acknowledge, (2) hardware tick
//  (Timer1, watchdog, USART, SPI, EEPROM, SPM), (3) the CPU's I/O write.
//
//  Implemented: GPIO ports A-D, Timer1 (normal / CTC, clk/1), watchdog
//  (interrupt + system reset), SPI master (mode 0, real SCK/MOSI/MISO),
//  EEPROM (2 KB, external RAM), SPM self programming control, USART0 TX
//  completion timing (used by some video modes), Timer2 OCR2A audio capture.
// ============================================================================

`default_nettype none

module avr_io (
    input  wire        clk,
    input  wire        ce,
    input  wire        rst,

    // CPU I/O bus
    input  wire [7:0]  io_addr,
    input  wire        io_re,
    input  wire        io_we,
    input  wire [7:0]  io_wdata,
    output reg  [7:0]  io_rdata,

    // interrupts
    input  wire        it_chk,
    input  wire        it_iflag,
    output reg         it_take,
    output reg  [15:0] it_vec,
    input  wire        ev_now,
    input  wire        ev_late,
    output reg  [2:0]  io_stall,

    // watchdog
    input  wire        wdr,
    input  wire [31:0] wd_seed,
    output wire        wdt_rst,

    // SPM
    input  wire        spm_req,
    input  wire [15:0] spm_z,
    input  wire [15:0] spm_data,
    output reg         fl_erase,     // page erase request (pulse)
    output reg         fl_write,     // page write request (pulse)
    output reg  [7:0]  fl_page,      // page number (Z[15:8])
    output reg         sb_we,        // temporary page buffer write
    output reg  [6:0]  sb_idx,
    output reg  [15:0] sb_data,

    // EEPROM storage (synchronous RAM, read data valid one cycle after addr)
    output wire [10:0] ee_addr,
    input  wire [7:0]  ee_dout,
    output reg         ee_we,
    output reg  [7:0]  ee_wdata,

    // SPI bus (mode 0, MSB first)
    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    input  wire [7:0]  spi_int_rx,   // byte an internal device sends this transfer
    output wire        spi_xfer_start, // a transfer starts at this clock edge
    output wire [7:0]  spi_xfer_tx,

    // SNES controller data inputs (already synchronised), active low data
    input  wire        pad1_data,
    input  wire        pad2_data,

    // Port outputs
    output wire [7:0]  porta, ddra,
    output wire [7:0]  portb, ddrb,
    output wire [7:0]  portc, ddrc,
    output wire [7:0]  portd, ddrd,

    // Audio: OCR2A writes (one per scanline in the Uzebox kernel)
    output reg         snd_we,
    output wire [7:0]  snd_val
);

    // ------------------------------------------------------------------
    // Register addresses (data space)
    // ------------------------------------------------------------------
    localparam A_PINA   = 8'h20, A_DDRA  = 8'h21, A_PORTA = 8'h22,
               A_PINB   = 8'h23, A_DDRB  = 8'h24, A_PORTB = 8'h25,
               A_PINC   = 8'h26, A_DDRC  = 8'h27, A_PORTC = 8'h28,
               A_PIND   = 8'h29, A_DDRD  = 8'h2A, A_PORTD = 8'h2B,
               A_TIFR1  = 8'h36, A_EECR  = 8'h3F, A_EEDR  = 8'h40,
               A_EEARL  = 8'h41, A_EEARH = 8'h42, A_SPCR  = 8'h4C,
               A_SPSR   = 8'h4D, A_SPDR  = 8'h4E, A_MCUCR = 8'h55,
               A_SPMCSR = 8'h57, A_WDTCSR= 8'h60, A_TIMSK1= 8'h6F,
               A_TCCR1B = 8'h81, A_TCNT1L= 8'h84, A_TCNT1H= 8'h85,
               A_OCR1AL = 8'h88, A_OCR1AH= 8'h89, A_OCR1BL= 8'h8A,
               A_OCR1BH = 8'h8B, A_TCCR2B= 8'hB1, A_OCR2A = 8'hB3,
               A_UCSR0A = 8'hC0, A_UDR0  = 8'hC6, A_TCCR1A= 8'h80,
               A_UCSR0B = 8'hC1, A_UCSR0C= 8'hC2, A_UBRR0L= 8'hC4,
               A_UBRR0H = 8'hC5;

    // Writes to PINx toggle PORTx (ATmega644 "toggling the pin"); they are
    // turned into the equivalent PORTx write here so all PORTx side effects
    // apply. PINx itself is never stored.
    wire        is_pin = (io_addr == A_PINA) || (io_addr == 8'h23) ||
                         (io_addr == 8'h26) || (io_addr == 8'h29);
    wire [7:0]  wa;        // effective write address
    wire [7:0]  wd;        // effective write data

    // Registers the hardware uses are flip-flops (reset to 0). Every other
    // I/O location is plain read-back storage in distributed RAM (one write
    // port, asynchronous read), e.g. GPIOR0-2 and unemulated peripherals.
    reg [7:0]  gmem [0:255];
    integer    gi;
    initial for (gi = 0; gi < 256; gi = gi + 1) gmem[gi] = 8'd0;
    reg        mem_we;
    reg [7:0]  mem_wd;
    always @(posedge clk) if (ce && mem_we) gmem[wa] <= mem_wd;
    wire [7:0] g_rd = gmem[io_addr];

    reg [7:0]  r_ddra, r_porta, r_ddrb, r_portb, r_ddrc, r_portc, r_ddrd, r_portd,
               r_spcr, r_mcucr, r_timsk1, r_tccr1a, r_tccr1b, r_tccr2b, r_ocr2a,
               r_eearl, r_eearh, r_ucsr0b, r_ubrr0l, r_ubrr0h;

    // Hardware-modified registers
    reg [7:0]  pina, tifr1, eecr, eedr, spsr, spdr, spmcsr, wdtcsr, ucsr0a, ucsr0c;
    reg [15:0] tcnt1;
    reg [15:0] ocr1a, ocr1b;     // written through the 16 bit TEMP latch
    reg [7:0]  t1_latch;         // TEMP register (shared by 16 bit accesses)
    reg        t1_blk;           // compare blocked for one timer clock after TCNT1 write
    reg [1:0]  spi_clr;          // SPSR flags armed for clearing by next SPDR access
    reg        event_it;

    wire [15:0] r_ocr1a  = ocr1a;
    wire [15:0] r_ocr1b  = ocr1b;
    wire [11:0] r_ubrr   = {r_ubrr0h[3:0], r_ubrr0l};

    assign porta = r_porta;  assign ddra = r_ddra;
    assign portb = r_portb;  assign ddrb = r_ddrb;
    assign portc = r_portc;  assign ddrc = r_ddrc;
    assign portd = r_portd;  assign ddrd = r_ddrd;
    assign snd_val = r_ocr2a;
    reg [7:0] pin_port;
    always @* case (io_addr[3:0])
        4'h0:    pin_port = r_porta;
        4'h3:    pin_port = r_portb;
        4'h6:    pin_port = r_portc;
        default: pin_port = r_portd;
    endcase
    assign wa = is_pin ? io_addr + 8'd2 : io_addr;
    assign wd = is_pin ? (pin_port ^ io_wdata) : io_wdata;
    assign ee_addr = {r_eearh[2:0], r_eearl};

    // ------------------------------------------------------------------
    // Read mux (combinational)
    // ------------------------------------------------------------------
    always @* begin
        case (io_addr)
        // live pin levels, as on the real AVR (the kernel detects a pad by
        // the data line being low after the 16th clock edge)
        A_PINA:   io_rdata = {6'd0, pad2_data, pad1_data};
        A_TIFR1:  io_rdata = tifr1;
        A_EECR:   io_rdata = eecr;
        A_EEDR:   io_rdata = eedr;
        A_SPSR:   io_rdata = spsr;
        A_SPDR:   io_rdata = spdr;
        A_SPMCSR: io_rdata = spmcsr;
        A_WDTCSR: io_rdata = wdtcsr;
        A_UCSR0A: io_rdata = ucsr0a;
        A_UCSR0C: io_rdata = ucsr0c;
        A_UDR0:   io_rdata = 8'hFF;          // no receiver attached
        A_TCNT1L: io_rdata = tcnt1[7:0];
        A_TCNT1H: io_rdata = t1_latch;
        A_OCR1AL: io_rdata = ocr1a[7:0];
        A_OCR1AH: io_rdata = ocr1a[15:8];
        A_OCR1BL: io_rdata = ocr1b[7:0];
        A_OCR1BH: io_rdata = ocr1b[15:8];
        8'h23, 8'h26, 8'h29: io_rdata = 8'd0;   // PINB/C/D: outputs only here
        A_DDRA:   io_rdata = r_ddra;    A_PORTA:  io_rdata = r_porta;
        A_DDRB:   io_rdata = r_ddrb;    A_PORTB:  io_rdata = r_portb;
        A_DDRC:   io_rdata = r_ddrc;    A_PORTC:  io_rdata = r_portc;
        A_DDRD:   io_rdata = r_ddrd;    A_PORTD:  io_rdata = r_portd;
        A_SPCR:   io_rdata = r_spcr;    A_MCUCR:  io_rdata = r_mcucr;
        A_TIMSK1: io_rdata = r_timsk1;  A_TCCR1A: io_rdata = r_tccr1a;
        A_TCCR1B: io_rdata = r_tccr1b;  A_TCCR2B: io_rdata = r_tccr2b;
        A_OCR2A:  io_rdata = r_ocr2a;   A_EEARL:  io_rdata = r_eearl;
        A_EEARH:  io_rdata = r_eearh;   A_UCSR0B: io_rdata = r_ucsr0b;
        A_UBRR0L: io_rdata = r_ubrr0l;  A_UBRR0H: io_rdata = r_ubrr0h;
        default:  io_rdata = g_rd;
        endcase
    end

    // ------------------------------------------------------------------
    // Interrupt check (combinational part)
    // ------------------------------------------------------------------
    wire p_spi  = r_spcr[7] & spsr[7];
    wire p_wdt  = wdtcsr[7] & wdtcsr[6];
    wire p_t1a  = tifr1[1] & r_timsk1[1];
    wire p_t1b  = tifr1[2] & r_timsk1[2];
    wire p_t1o  = tifr1[0] & r_timsk1[0];
    wire p_usr  = ucsr0a[6] & r_ucsr0b[6];     // TXC & TXCIE
    wire p_any  = p_spi | p_wdt | p_t1a | p_t1b | p_t1o | p_usr;
    wire ev_eff = event_it | ev_now;
    wire chk    = it_chk & ev_eff;
    wire [15:0] vbase = r_mcucr[1] ? 16'h7800 : 16'h0000;

    always @* begin
        it_take = chk & it_iflag & p_any;
        // ATmega644 priority: lower vector address first
        if      (p_wdt) it_vec = vbase + 16'h0010;
        else if (p_t1a) it_vec = vbase + 16'h001A;
        else if (p_t1b) it_vec = vbase + 16'h001C;
        else if (p_t1o) it_vec = vbase + 16'h001E;
        else if (p_spi) it_vec = vbase + 16'h0026;
        else            it_vec = vbase + 16'h002C;
    end

    // ------------------------------------------------------------------
    // Timer 1 tick
    // ------------------------------------------------------------------
    wire        t1_run  = (r_tccr1b[2:0] != 3'd0);
    wire        t1_ctc  = r_tccr1b[3];
    wire [15:0] t1_next = tcnt1 + 16'd1;
    // compare matches in CTC mode and in normal mode (WGM = 0); none during
    // the timer clock right after a TCNT1 write
    wire        t1_norm = (r_tccr1a[1:0] == 2'b00) && (r_tccr1b[4:3] == 2'b00);
    wire        t1_cmp  = t1_run & ~t1_blk & (t1_ctc | t1_norm);
    wire        t1_tov  = t1_run & (t1_next == 16'd0);
    wire        t1_ocfa = t1_cmp & (t1_next == r_ocr1a + 16'd1);
    wire        t1_ocfb = t1_cmp & (t1_next == r_ocr1b + 16'd1);

    // ------------------------------------------------------------------
    // Watchdog
    // ------------------------------------------------------------------
    reg  [25:0] wd_cnt;
    reg         wd_act;
    function [25:0] wd_timeout;
        input [2:0]  presc;
        input [31:0] seed;
        reg   [25:0] base, mask;
        begin
            base = 26'd457152 << presc;
            mask = (26'd2048  << presc) - 26'd1;
            wd_timeout = base + (seed[25:0] & mask);
        end
    endfunction
    wire wd_en   = (wdtcsr & 8'h48) != 8'h00;
    wire wd_fire = wd_act & (wd_cnt == 26'd1) & ~wdr & wd_en;
    assign wdt_rst = ce & wd_fire & ((wdtcsr & 8'h48) == 8'h08);

    // ------------------------------------------------------------------
    // USART0 transmit timing
    // ------------------------------------------------------------------
    // frame time = (UBRR+1) * scale * bits (CUzeBox-ex cu_avr_uart_frame_cycles)
    reg [19:0] us_cnt;
    reg        us_act;
    wire       us_fire = us_act & (us_cnt == 20'd1);
    reg  [3:0] us_bits;
    reg  [4:0] us_scale;
    always @* begin : us_frame
        reg [2:0] sz;
        sz = {r_ucsr0b[2], ucsr0c[2:1]};
        us_bits = 4'd1 + ((sz == 3'd7) ? 4'd9 : (4'd5 + {2'd0, sz[1:0]})) +
                  (ucsr0c[3] ? 4'd2 : 4'd1) + ((ucsr0c[5:4] != 2'd0) ? 4'd1 : 4'd0);
        us_scale = (ucsr0c[7:6] != 2'd0) ? 5'd2 : (ucsr0a[1] ? 5'd8 : 5'd16);
        if (ucsr0c[7:6] == 2'd3) us_bits = 4'd8;
    end
    wire [19:0] us_frame_cyc = ({8'd0, r_ubrr} + 20'd1) * {15'd0, us_scale} * {16'd0, us_bits};

    // ------------------------------------------------------------------
    // SPI master
    // ------------------------------------------------------------------
    reg        spi_busy;
    reg [11:0] spi_el;       // elapsed cycles in transfer
    reg [2:0]  spi_idx;      // duration = 16 << idx, half bit = 1 << idx
    reg [7:0]  spi_sh;       // shift register (tx out / rx in)
    reg        spi_mosi_r;
    reg [7:0]  spi_ish;      // internal device byte being shifted out
    wire [11:0] spi_el_n  = spi_el + 12'd1;
    wire [11:0] spi_dur   = 12'd16 << spi_idx;
    wire [11:0] spi_hmask = (12'd2 << spi_idx) - 12'd1;   // full bit period mask
    wire        spi_bit_end = spi_busy & ((spi_el_n & spi_hmask) == 12'd0);
    wire        spi_done  = spi_busy & (spi_el_n == spi_dur);
    wire [7:0]  spi_rx    = {spi_sh[6:0], spi_miso & spi_ish[7]};
    assign spi_xfer_start = ce & io_we & (io_addr == A_SPDR) & r_spcr[6] &
                            ~(spi_busy & ~spi_done);
    assign spi_xfer_tx    = io_wdata;
    assign spi_sck  = spi_busy & spi_el[{1'b0, spi_idx}];
    assign spi_mosi = spi_mosi_r;

    // ------------------------------------------------------------------
    // EEPROM
    // ------------------------------------------------------------------
    reg [16:0] ee_cnt;
    reg        ee_act;
    reg        ee_wrte;      // programming in progress
    reg        ee_rdpend;    // EEDR load pending (sync RAM latency)
    reg [1:0]  ee_mode;
    wire       ee_fire = ee_act & (ee_cnt == 17'd1);

    // ------------------------------------------------------------------
    // SPM
    // ------------------------------------------------------------------
    reg [16:0] spm_cnt;
    reg        spm_act;
    reg        spm_prge;
    reg [4:0]  spm_mode;
    wire       spm_go   = spm_req & spmcsr[0] & ~spm_prge;
    wire       spm_pgm  = spm_go & ((spm_mode == 5'h02) || (spm_mode == 5'h04));
    wire       spm_fire = spm_act & (spm_cnt == 17'd1) & ~spm_pgm;

    // ------------------------------------------------------------------
    // Next-state computation for hardware-modified registers
    // (order: interrupt acknowledge -> SPM instruction -> tick -> CPU write)
    // ------------------------------------------------------------------
    reg [7:0]  tifr1_t, spsr_t, spdr_t, wdtcsr_t, ucsr0a_t, eecr_t, spmcsr_t;
    reg        ev_n;
    reg [2:0]  stall_c;
    reg [7:0]  st_cv;
    reg        st_wr;

    always @* begin
        tifr1_t  = tifr1;
        spsr_t   = spsr;
        wdtcsr_t = wdtcsr;
        ucsr0a_t = ucsr0a;
        spdr_t   = spdr;
        eecr_t   = eecr;
        spmcsr_t = spmcsr;

        // (0) read side effects (reads happen before the check in CUzeBox-ex):
        // reading SPDR clears the SPSR flags seen by an earlier SPSR read
        if (io_re && io_addr == A_SPDR) spsr_t = spsr_t & ~{spi_clr, 6'd0};

        // (1) interrupt check & acknowledge
        ev_n = ev_eff;
        if (chk) begin
            if (!it_iflag)   ev_n = 1'b0;
            else if (!p_any) ev_n = 1'b0;
            else begin
                if (p_wdt) begin
                    wdtcsr_t[7] = 1'b0;
                    if (wdtcsr[3]) wdtcsr_t[6] = 1'b0;
                end
                else if (p_t1a) tifr1_t[1] = 1'b0;
                else if (p_t1b) tifr1_t[2] = 1'b0;
                else if (p_t1o) tifr1_t[0] = 1'b0;
                else if (p_spi) spsr_t[7] = 1'b0;
                else            ucsr0a_t[6] = 1'b0;
            end
        end

        // SPM instruction (executes before the tick of its first cycle)
        if (spm_go && !spm_pgm) begin
            if      (spm_mode == 5'h08) spmcsr_t = spmcsr_t & 8'hE0;
            else                        spmcsr_t = spmcsr_t & 8'hA0;
        end
        if (spm_pgm) spmcsr_t = spmcsr_t | 8'h40;

        // (2) hardware tick
        if (t1_tov)  begin tifr1_t[0] = 1'b1; ev_n = 1'b1; end
        if (t1_ocfb) begin tifr1_t[2] = 1'b1; ev_n = 1'b1; end
        if (t1_ocfa) begin tifr1_t[1] = 1'b1; ev_n = 1'b1; end
        if (wd_fire) begin wdtcsr_t[7] = 1'b1; ev_n = 1'b1; end
        if (us_fire) begin
            if (!ucsr0a[5]) ucsr0a_t[5] = 1'b1;                     // buffered byte moves on
            else begin ucsr0a_t[6] = 1'b1; ev_n = 1'b1; end         // transmission complete
        end
        if (spi_done) begin spsr_t[7] = 1'b1; ev_n = 1'b1; spdr_t = spi_rx; end
        if (ee_fire) begin
            if (ee_wrte) eecr_t = eecr_t & ~8'h02;
            else         eecr_t = eecr_t & ~8'h04;
        end
        if (spm_fire) begin
            if (spm_prge || spm_pgm) spmcsr_t = spmcsr_t & ~8'h1F;
            else                     spmcsr_t = spmcsr_t & ~8'h01;
        end

        // (3) CPU write side effects on event_it
        if (ev_late) ev_n = 1'b1;

        // EEPROM write stall computation
        stall_c = 3'd0;
        st_cv   = io_wdata;
        st_wr   = ee_wrte & ~ee_fire;
        if (!st_wr) begin
            if (!eecr_t[2]) st_cv = st_cv & ~8'h02;
            if (!eecr_t[1] && st_cv[1]) stall_c = 3'd2;
            else if (st_cv[0])          stall_c = 3'd4;
        end
        if (!(io_we && io_addr == A_EECR)) stall_c = 3'd0;
        io_stall = stall_c;
    end

    // Generic storage write decode
    always @* begin
        mem_wd = (wa == A_PORTC) ? (wd & r_ddrc) : wd;
        case (wa)
        A_TIFR1, A_SPSR, A_SPDR, A_EECR, A_EEDR, A_WDTCSR, A_SPMCSR, A_UCSR0A,
        A_UCSR0C, A_TCNT1H, A_TCNT1L, A_OCR1AH, A_OCR1AL, A_OCR1BH, A_OCR1BL:
                              mem_we = 1'b0;
        A_EEARL, A_EEARH:     mem_we = io_we & ~(ee_wrte & ~ee_fire);
        default:              mem_we = io_we;
        endcase
        if (rst || wdt_rst) mem_we = 1'b0;
    end

    // ------------------------------------------------------------------
    // Sequential
    // ------------------------------------------------------------------
        always @(posedge clk) begin
        if (ce) begin
            fl_erase <= 1'b0;
            fl_write <= 1'b0;
            sb_we    <= 1'b0;
            ee_we    <= 1'b0;
            snd_we   <= 1'b0;
        end

        if (rst || wdt_rst) begin
            r_ddra <= 8'd0; r_porta <= 8'd0; r_ddrb <= 8'd0; r_portb <= 8'd0;
            r_ddrc <= 8'd0; r_portc <= 8'd0; r_ddrd <= 8'd0; r_portd <= 8'd0;
            r_spcr <= 8'd0; r_mcucr <= 8'd0; r_timsk1 <= 8'd0; r_tccr1a <= 8'd0;
            r_tccr1b <= 8'd0; r_tccr2b <= 8'd0; r_ocr2a <= 8'd0; r_eearl <= 8'd0;
            r_eearh <= 8'd0; r_ucsr0b <= 8'd0; r_ubrr0l <= 8'd0; r_ubrr0h <= 8'd0;
            pina <= 8'd0; tifr1 <= 8'd0; eecr <= 8'd0; eedr <= 8'd0;
            spsr <= 8'd0; spdr <= 8'd0; spmcsr <= 8'd0; wdtcsr <= 8'd0;
            ucsr0a <= 8'h20; ucsr0c <= 8'h06; us_act <= 1'b0;
            tcnt1 <= 16'd0; t1_latch <= 8'd0; t1_blk <= 1'b0; spi_clr <= 2'b00;
            ocr1a <= 16'd0; ocr1b <= 16'd0;
            event_it <= 1'b1;
            spi_busy <= 1'b0; spi_el <= 12'd0; spi_idx <= 3'd0;
            spi_sh <= 8'hFF; spi_ish <= 8'hFF; spi_mosi_r <= 1'b1;
            ee_act <= 1'b0; ee_cnt <= 17'd0; ee_wrte <= 1'b0; ee_rdpend <= 1'b0;
            spm_act <= 1'b0; spm_cnt <= 17'd0; spm_prge <= 1'b0;
            wd_act <= 1'b1;
            wd_cnt <= wd_timeout(3'd0, wd_seed);
            if (rst) begin
                spm_mode <= 5'd0;
                us_cnt <= 20'd0;
            end
        end else if (ce) begin
            // defaults: post-tick values
            tifr1  <= tifr1_t;
            spsr   <= spsr_t;
            spdr   <= spdr_t;
            wdtcsr <= wdtcsr_t;
            ucsr0a <= ucsr0a_t;
            eecr   <= eecr_t;
            spmcsr <= spmcsr_t;
            event_it <= ev_n;

            // ---- Timer 1
            tcnt1 <= (t1_ctc & t1_ocfa) ? 16'd0 : t1_next;
            if (t1_run) t1_blk <= 1'b0;
            if (io_re && io_addr == A_TCNT1L) t1_latch <= tcnt1[15:8];
            if (io_re && io_addr == A_SPSR)   spi_clr  <= spsr[7:6];
            if (io_re && io_addr == A_SPDR)   spi_clr  <= 2'b00;

            // ---- Watchdog
            if (wdr) begin
                wd_cnt <= wd_timeout(wdtcsr[2:0], wd_seed) - 26'd1;
                wd_act <= 1'b1;
            end else if (wd_act) begin
                if (wd_cnt == 26'd1) begin
                    if (wd_en) wd_cnt <= wd_timeout(wdtcsr[2:0], wd_seed);
                    else       wd_act <= 1'b0;
                end else
                    wd_cnt <= wd_cnt - 26'd1;
            end

            // ---- USART
            if (us_act) begin
                if (us_cnt == 20'd1) begin
                    if (!ucsr0a[5]) us_cnt <= us_frame_cyc;
                    else            us_act <= 1'b0;
                end else us_cnt <= us_cnt - 20'd1;
            end

            // ---- SPI
            if (spi_busy) begin
                spi_el <= spi_el_n;
                if (spi_bit_end) begin
                    spi_sh     <= spi_rx;
                    spi_ish    <= {spi_ish[6:0], 1'b1};
                    spi_mosi_r <= spi_sh[6];
                end
                if (spi_done) begin
                    spi_busy   <= 1'b0;
                    spi_mosi_r <= 1'b1;
                end
            end

            // ---- EEPROM
            if (ee_rdpend) begin
                eedr      <= ee_dout;
                ee_rdpend <= 1'b0;
            end
            if (ee_act) begin
                if (ee_cnt == 17'd1) begin
                    ee_act <= 1'b0;
                    if (ee_wrte) begin
                        ee_wrte <= 1'b0;
                        ee_we   <= 1'b1;
                        case (eecr[5:4])
                        2'b00:   ee_wdata <= eedr;
                        2'b01:   ee_wdata <= 8'hFF;
                        2'b10:   ee_wdata <= ee_dout & eedr;   // write only: bits can only clear
                        default: begin ee_we <= 1'b0; ee_wdata <= ee_dout; end
                        endcase
                    end
                end else
                    ee_cnt <= ee_cnt - 17'd1;
            end

            // ---- SPM
            if (spm_pgm) begin
                fl_erase <= (spm_mode == 5'h02);
                fl_write <= (spm_mode == 5'h04);
                fl_page  <= spm_z[15:8];
                spm_prge <= 1'b1;
                spm_act  <= 1'b1;
                spm_cnt  <= 17'd99999;
            end else begin
                if (spm_go && spm_mode != 5'h08 && spm_mode != 5'h10) begin
                    sb_we   <= 1'b1;
                    sb_idx  <= spm_z[7:1];
                    sb_data <= spm_data;
                end
                if (spm_act) begin
                    if (spm_cnt == 17'd1) begin
                        spm_act  <= 1'b0;
                        spm_prge <= 1'b0;
                    end else
                        spm_cnt <= spm_cnt - 17'd1;
                end
            end

            // ---- CPU write (step 3)
            if (mem_we) case (wa)
                A_DDRA:   r_ddra   <= mem_wd;  A_PORTA:  r_porta  <= mem_wd;
                A_DDRB:   r_ddrb   <= mem_wd;  A_PORTB:  r_portb  <= mem_wd;
                A_DDRC:   r_ddrc   <= mem_wd;  A_PORTC:  r_portc  <= mem_wd;
                A_DDRD:   r_ddrd   <= mem_wd;  A_PORTD:  r_portd  <= mem_wd;
                A_SPCR:   r_spcr   <= mem_wd;  A_MCUCR:  r_mcucr  <= mem_wd;
                A_TIMSK1: r_timsk1 <= mem_wd;  A_TCCR1A: r_tccr1a <= mem_wd;
                A_TCCR1B: r_tccr1b <= mem_wd;  A_TCCR2B: r_tccr2b <= mem_wd;
                A_OCR2A:  r_ocr2a  <= mem_wd;  A_EEARL:  r_eearl  <= mem_wd;
                A_EEARH:  r_eearh  <= mem_wd;  A_UCSR0B: r_ucsr0b <= mem_wd;
                A_UBRR0L: r_ubrr0l <= mem_wd;  A_UBRR0H: r_ubrr0h <= mem_wd;
                default: ;
            endcase
            if (io_we) begin
                case (wa)
                A_PORTA, A_DDRA: begin
                    pina <= {6'd0, pad2_data, pad1_data};
                end
                A_TIFR1: tifr1 <= tifr1_t & ~io_wdata;
                A_TCNT1H, A_OCR1AH, A_OCR1BH: t1_latch <= io_wdata;   // TEMP only
                A_TCNT1L: begin
                    tcnt1  <= {t1_latch, io_wdata};
                    t1_blk <= 1'b1;
                end
                A_OCR1AL: ocr1a <= {t1_latch, io_wdata};
                A_OCR1BL: ocr1b <= {t1_latch, io_wdata};
                A_SPSR:  spsr <= (spsr_t & 8'hC0) | (io_wdata & 8'h01);
                A_SPCR:  if (!io_wdata[6]) begin               // SPI disabled: abort
                    spi_busy   <= 1'b0;
                    spi_mosi_r <= 1'b1;
                end
                A_SPDR: begin
                    // SPDR keeps the received byte; a write starts a transfer.
                    // Writing (like reading) SPDR clears the flags seen in SPSR.
                    spsr    <= spsr_t & ~{spi_clr, 6'd0};
                    spi_clr <= 2'b00;
                    if (r_spcr[6]) begin
                        if (spi_busy && !spi_done)
                            spsr <= (spsr_t & ~{spi_clr, 6'd0}) | 8'h40;
                        else begin
                            spi_busy   <= 1'b1;
                            spi_el     <= 12'd0;
                            case (r_spcr[1:0])
                            2'd0: spi_idx <= spsr_t[0] ? 3'd0 : 3'd1;   // fosc/2, /4
                            2'd1: spi_idx <= spsr_t[0] ? 3'd2 : 3'd3;   // fosc/8, /16
                            2'd2: spi_idx <= spsr_t[0] ? 3'd4 : 3'd5;   // fosc/32, /64
                            default: spi_idx <= spsr_t[0] ? 3'd5 : 3'd6; // fosc/64, /128
                            endcase
                            spi_sh     <= io_wdata;
                            spi_ish    <= spi_int_rx;
                            spi_mosi_r <= io_wdata[7];
                        end
                    end
                end
                A_EECR: begin : eecr_wr
                    reg [7:0] cv;
                    cv = io_wdata;
                    if (ee_wrte & ~ee_fire) begin
                        // programming in progress: EEPE and mode locked
                        cv = (cv & ~8'h37) | (eecr_t & 8'h32);
                    end else begin
                        if (!eecr_t[2]) cv = cv & ~8'h02;   // EEPE needs EEMPE
                        if (cv[2]) begin                    // EEMPE opens a 4 cycle window
                            ee_act <= 1'b1;
                            ee_cnt <= 17'd4;
                        end
                        if (!eecr_t[1] && cv[1]) begin       // programming starts
                            ee_wrte <= 1'b1;
                            ee_act  <= 1'b1;
                            ee_mode <= cv[5:4];
                            ee_cnt  <= (cv[5:4] == 2'b00) ? 17'd100000 : 17'd50000;
                            cv = cv & ~8'h04;
                        end else if (cv[0])
                            ee_rdpend <= 1'b1;
                        cv = cv & ~8'h01;
                    end
                    eecr <= cv;
                end
                A_EEDR:  if (!(ee_wrte & ~ee_fire)) eedr <= io_wdata;
                A_WDTCSR: begin
                    wdtcsr <= io_wdata;
                    if (((wdtcsr_t & 8'h48) == 8'h00) && ((io_wdata & 8'h48) != 8'h00)) begin
                        wd_cnt <= wd_timeout(wdtcsr_t[2:0], wd_seed);
                        wd_act <= 1'b1;
                    end
                end
                A_SPMCSR: begin : spmcsr_wr
                    reg [7:0] cv;
                    cv = (io_wdata & ~8'h40) | (spmcsr_t & 8'h40);
                    spmcsr <= cv;
                    if (!spmcsr_t[0] && cv[0] && !(spm_prge || spm_pgm)) begin
                        if (cv[4:1] == 4'h0 || cv[4:1] == 4'h1 || cv[4:1] == 4'h2 ||
                            cv[4:1] == 4'h4 || cv[4:1] == 4'h8) begin
                            spm_mode <= cv[4:0] & 5'h1E;
                            spm_act  <= 1'b1;
                            spm_cnt  <= 17'd4;
                        end
                    end
                end
                A_UCSR0A: ucsr0a <= ((ucsr0a_t & ~8'h03) | (io_wdata & 8'h03)) &
                                    ~(io_wdata[6] ? 8'h40 : 8'h00);
                A_UCSR0C: ucsr0c <= io_wdata;
                A_UDR0: if (r_ucsr0b[3] && ucsr0a_t[5]) begin
                    if (us_act && !(us_fire && ucsr0a[5]))
                        ucsr0a <= ucsr0a_t & ~8'h20;               // goes to the buffer
                    else begin
                        us_act <= 1'b1;
                        us_cnt <= us_frame_cyc;
                    end
                end
                A_TIMSK1, A_UCSR0B: event_it <= 1'b1;   // a latched flag may become unmasked
                A_OCR2A: begin
                    if (r_tccr2b != 8'd0) snd_we <= 1'b1;
                end
                default: ;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
