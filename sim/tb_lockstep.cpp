// ============================================================================
//  tb_lockstep.cpp - UzeTang AVR core vs. CUzeBox lock-step comparison
//
//  Runs the Verilated avr_soc and the CUzeBox AVR emulator side by side and
//  compares PC, cycle count, r0-r31, SREG and SP at every instruction start.
//  Optionally compares the whole SRAM and the I/O registers periodically and
//  dumps video frames captured from PORTC / sync (PORTB.0) as PPM images.
//
//  usage: tb_lockstep prog.hex [options]
//    -n N        stop after N instructions (default 2,000,000)
//    -m N        compare SRAM + I/O registers every N instructions (0 = off)
//    -f a,b,c    dump frames a,b,c (frame numbers) to frame_NNN.ppm
//    -b          prioritise bootloader (like CUzeBox -b)
//    -e file     preload EEPROM image (2048 bytes)
//    -q          quiet
// ============================================================================
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <set>
#include <algorithm>
#ifdef TOP_LS
#include "Vls_top.h"
#include "Vls_top___024root.h"
typedef Vls_top Vtop;
#define RP(x) R->ls_top__DOT__soc__DOT__##x
#else
#include "Vavr_soc.h"
#include "Vavr_soc___024root.h"
typedef Vavr_soc Vtop;
#define RP(x) R->avr_soc__DOT__##x
#endif
#include "verilated.h"
#include "cuzref/ref.h"
#ifndef REF_NAME
#define REF_NAME "CUzeBox-ex"
#endif

static uint8_t crom[65536];

static bool load_hex(const char* fn)
{
    FILE* f = fopen(fn, "r");
    if (!f) { perror(fn); return false; }
    memset(crom, 0xFF, sizeof(crom));
    char line[600];
    uint32_t base = 0;
    while (fgets(line, sizeof line, f)) {
        if (line[0] != ':') continue;
        unsigned cnt, addr, type;
        sscanf(line + 1, "%2x%4x%2x", &cnt, &addr, &type);
        if (type == 0) {
            for (unsigned i = 0; i < cnt; i++) {
                unsigned b; sscanf(line + 9 + i * 2, "%2x", &b);
                uint32_t a = base + addr + i;
                if (a < 65536) crom[a] = (uint8_t)b;
            }
        } else if (type == 2) {
            unsigned seg; sscanf(line + 9, "%4x", &seg); base = seg << 4;
        } else if (type == 4) {
            unsigned up; sscanf(line + 9, "%4x", &up); base = up << 16;
        } else if (type == 1) break;
    }
    fclose(f);
    return true;
}

// ---------------------------------------------------------------------------
// Simple frame grabber working on RTL pins
// ---------------------------------------------------------------------------
struct FrameGrab {
    std::vector<uint8_t> line;      // samples of the current line
    std::vector<std::vector<uint8_t>> frame;
    int  sync_prev = 1;
    uint64_t low_start = 0, last_fall = 0;
    bool in_vsync = false;
    int  frame_no = 0;
    std::set<int> want;
    void cycle(uint64_t cyc, int sync, uint8_t pix) {
        if (sync_prev && !sync) {           // falling edge: line boundary
            if (cyc - last_fall > 1500) {   // normal line
                if (!line.empty()) frame.push_back(line);
                line.clear();
            }
            last_fall = cyc;
            low_start = cyc;
        }
        if (!sync_prev && sync) {           // rising edge
            uint64_t lw = cyc - low_start;
            if (lw > 500) in_vsync = true;  // long (vsync) pulse
            else if (in_vsync && cyc - last_fall < 200) {
                // first normal pulse after vsync: frame boundary
                in_vsync = false;
                emit();
            }
        }
        sync_prev = sync;
        if (line.size() < 1820) line.push_back(pix);
    }
    void emit() {
        if (want.count(frame_no) && frame.size() > 10) {
            char fn[64]; snprintf(fn, sizeof fn, "frame_%03d.ppm", frame_no);
            FILE* f = fopen(fn, "wb");
            int w = 1820, h = (int)frame.size();
            fprintf(f, "P6\n%d %d\n255\n", w, h);
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    uint8_t p = x < (int)frame[y].size() ? frame[y][x] : 0;
                    uint8_t rgb[3] = {
                        (uint8_t)(((p >> 0) & 7) * 255 / 7),
                        (uint8_t)(((p >> 3) & 7) * 255 / 7),
                        (uint8_t)(((p >> 6) & 3) * 255 / 3) };
                    fwrite(rgb, 1, 3, f);
                }
            fclose(f);
            printf("  [frame %d dumped: %dx%d]\n", frame_no, w, h);
        }
        frame.clear();
        frame_no++;
    }
};

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    if (argc < 2) { fprintf(stderr, "usage: %s prog.hex [opts]\n", argv[0]); return 2; }
    const char* hexfn = argv[1];
    uint64_t max_ins = 2000000, memchk = 0;
    int pause_pct = 0;   // -p N: pause the AVR (ce=0) randomly N% of cycles
    bool bootpri = false, quiet = false;
    FrameGrab fg;
    const char* eepfn = nullptr;
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "-n") && i + 1 < argc) max_ins = strtoull(argv[++i], 0, 0);
        else if (!strcmp(argv[i], "-m") && i + 1 < argc) memchk = strtoull(argv[++i], 0, 0);
        else if (!strcmp(argv[i], "-b")) bootpri = true;
        else if (!strcmp(argv[i], "-p") && i + 1 < argc) pause_pct = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-q")) quiet = true;
        else if (!strcmp(argv[i], "-r") && i + 1 < argc) ref_spiram_banks = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-e") && i + 1 < argc) eepfn = argv[++i];
        else if (!strcmp(argv[i], "-f") && i + 1 < argc) {
            std::string s = argv[++i]; size_t p = 0;
            while (p < s.size()) { fg.want.insert(atoi(s.c_str() + p));
                p = s.find(',', p); if (p == std::string::npos) break; p++; }
        }
    }
    if (!load_hex(hexfn)) return 2;

    // Same fuse logic as CUzeBox autofuse
    bool hasgame = crom[0] || crom[1];
    bool hasboot = crom[0xF000] || crom[0xF001];
    bool boot = hasboot && (bootpri || !hasgame);
    // CUzeBox treats 0xFFFF (erased) as code too; mirror its test on raw bytes
    hasgame = (crom[0] != 0) || (crom[1] != 0);

    ref_init(crom, bootpri ? 1 : 0);

    Vtop* t = new Vtop;
    t->rst = 1; t->clk = 0;
    t->rst_vec = boot ? 0x7800 : 0x0000;
    t->wd_seed = 0;
    t->pad1_data = 1; t->pad2_data = 1;
    t->spi_miso = 1;
    t->spi_int_rx = 0xFF;
    t->ce = 1;
    t->ld_we = 0; t->ee_ext_we = 0;
#ifdef TOP_LS
    for (int i = 0; i < 20000 && !t->sdram_ready; i++) { t->clk = 1; t->eval(); t->clk = 0; t->eval(); }
#endif
    auto tick = [&]() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); };
    t->eval();
    // Load flash through the loader port
    for (int w = 0; w < 32768; w++) {
        t->ld_we = 1; t->ld_addr = w;
        t->ld_data = crom[w * 2] | (crom[w * 2 + 1] << 8);
        tick();
    }
    t->ld_we = 0;
    if (eepfn) {
        FILE* f = fopen(eepfn, "rb"); uint8_t e[2048];
        if (f) { size_t n = fread(e, 1, 2048, f); fclose(f);
            for (size_t i = 0; i < n; i++) { t->ee_ext_we = 1; t->ee_ext_addr = i; t->ee_ext_wdata = e[i]; tick(); }
            t->ee_ext_we = 0; }
    }
    tick(); tick();
    t->rst = 0; t->eval();

    uint64_t cyc = 0, cyc0 = 0, ins = 0;
    static uint64_t opstat[64], vecstat[64];
    bool started = false;
    uint32_t rc0 = ref_cycle();
    int errors = 0;
    auto* R = t->rootp;

    uint32_t lfsr = 0xACE1u;
    while (ins < max_ins) {
        if (pause_pct) {
            lfsr = lfsr * 1103515245u + 12345u;
            t->ce = ((lfsr >> 16) % 100) >= (unsigned)pause_pct;
            if (!t->ce) { t->eval(); tick(); continue; }
        }
        t->eval();
        if (t->dbg_istart) {
            if (!started) { started = true; cyc0 = cyc; }
            uint32_t rpc = ref_pc();
            uint32_t rcy = ref_cycle() - rc0;
            const uint8_t* io = ref_iors();
            uint64_t ccy = cyc - cyc0;
            bool bad = false;
            char msg[512]; msg[0] = 0;
            if (rpc != t->dbg_pc) { bad = true; snprintf(msg, sizeof msg, "PC ref=%04X rtl=%04X", rpc, t->dbg_pc); }
            else if (rcy != (uint32_t)ccy) { bad = true; snprintf(msg, sizeof msg, "cycle ref=%u rtl=%llu", rcy, (unsigned long long)ccy); }
            else {
                for (int r = 0; r < 32 && !bad; r++) {
                    uint8_t v = (t->dbg_regs[r / 4] >> ((r % 4) * 8)) & 0xFF;
                    if (v != io[r]) { bad = true; snprintf(msg, sizeof msg, "r%d ref=%02X rtl=%02X", r, io[r], v); }
                }
                if (!bad && io[0x5F] != t->dbg_sreg) { bad = true; snprintf(msg, sizeof msg, "SREG ref=%02X rtl=%02X", io[0x5F], t->dbg_sreg); }
                uint16_t rsp = io[0x5D] | (io[0x5E] << 8);
                if (!bad && rsp != t->dbg_sp) { bad = true; snprintf(msg, sizeof msg, "SP ref=%04X rtl=%04X", rsp, t->dbg_sp); }
            }
            if (!bad && memchk && (ins % memchk) == 0) {
                const uint8_t* sr = ref_sram();
                for (int a = 0; a < 4096 && !bad; a++) {
                    uint8_t v = a < 2048 ? RP(sram__DOT__lo_ram__DOT__mem)[a] : RP(sram__DOT__hi_ram__DOT__mem)[a - 2048];
                    if (v != sr[a]) { bad = true; snprintf(msg, sizeof msg, "SRAM[%03X] ref=%02X rtl=%02X", a, sr[a], v); }
                }
                // I/O registers (as read by the CPU)
                static const uint8_t chk[] = {0x21,0x22,0x24,0x25,0x27,0x28,0x2A,0x2B,0x36,0x3E,0x3F,0x40,0x41,0x42,
                    0x4A,0x4B,0x4C,0x4D,0x4E,0x55,0x57,0x60,0x6F,0x81,0x88,0x89,0x8A,0x8B,0xB3,0xC0,0xC1,0xC2};
                for (unsigned k = 0; k < sizeof chk && !bad; k++) {
                    uint8_t a = chk[k];
                    t->eval();
                    // read via the mirror of the read mux
                    uint8_t v;
                    switch (a) {
                    case 0x36: v = RP(io__DOT__tifr1); break;
                    case 0x3F: v = RP(io__DOT__eecr); break;
                    case 0x40: v = RP(io__DOT__eedr); break;
                    case 0x4D: v = RP(io__DOT__spsr); break;
                    case 0x4E: v = RP(io__DOT__spdr); break;
                    case 0x57: v = RP(io__DOT__spmcsr); break;
                    case 0x60: v = RP(io__DOT__wdtcsr); break;
                    case 0xC0: v = RP(io__DOT__ucsr0a); break;
                    case 0xC2: v = RP(io__DOT__ucsr0c); break;
                    case 0x88: v = RP(io__DOT__ocr1a) & 0xFF; break;
                    case 0x89: v = RP(io__DOT__ocr1a) >> 8; break;
                    case 0x8A: v = RP(io__DOT__ocr1b) & 0xFF; break;
                    case 0x8B: v = RP(io__DOT__ocr1b) >> 8; break;
                    case 0x21: v = RP(io__DOT__r_ddra); break;
                    case 0x22: v = RP(io__DOT__r_porta); break;
                    case 0x24: v = RP(io__DOT__r_ddrb); break;
                    case 0x25: v = RP(io__DOT__r_portb); break;
                    case 0x27: v = RP(io__DOT__r_ddrc); break;
                    case 0x28: v = RP(io__DOT__r_portc); break;
                    case 0x2A: v = RP(io__DOT__r_ddrd); break;
                    case 0x2B: v = RP(io__DOT__r_portd); break;
                    case 0x41: v = RP(io__DOT__r_eearl); break;
                    case 0x42: v = RP(io__DOT__r_eearh); break;
                    case 0x4C: v = RP(io__DOT__r_spcr); break;
                    case 0x55: v = RP(io__DOT__r_mcucr); break;
                    case 0x6F: v = RP(io__DOT__r_timsk1); break;
                    case 0x81: v = RP(io__DOT__r_tccr1b); break;
                    case 0xB3: v = RP(io__DOT__r_ocr2a); break;
                    case 0xC1: v = RP(io__DOT__r_ucsr0b); break;
                    default:   v = RP(io__DOT__gmem)[a]; break;
                    }
                    if (v != io[a]) { bad = true; snprintf(msg, sizeof msg, "IO[%02X] ref=%02X rtl=%02X", a, io[a], v); }
                }
                uint16_t rt = (uint16_t)ref_tcnt1();
                if (!bad && rt != RP(io__DOT__tcnt1)) { bad = true; snprintf(msg, sizeof msg, "TCNT1 ref=%04X rtl=%04X", rt, RP(io__DOT__tcnt1)); }
            }
            if (bad) {
                printf("MISMATCH at instruction %llu (cycle %llu): %s\n", (unsigned long long)ins, (unsigned long long)ccy, msg);
                if (++errors >= 1) break;
            }
            {   // coverage statistics
                uint16_t w = crom[(rpc*2) & 0xFFFF] | (crom[(rpc*2+1) & 0xFFFF] << 8);
                opstat[w >> 10]++;
                if (rpc > 0 && rpc < 0x3E && !(rpc & 1)) vecstat[rpc]++;
            }
            ref_step();
            ins++;
            if (!quiet && (ins % 1000000) == 0) printf("  %llu instructions, %llu cycles OK\n", (unsigned long long)ins, (unsigned long long)ccy);
        }
        if (started) fg.cycle(cyc - cyc0, (t->portb & t->ddrb & 1) ? 1 : 0, t->portc);
        tick();
        cyc++;
    }
    printf("%s: %llu instructions, %llu cycles, %s\n", hexfn, (unsigned long long)ins,
           (unsigned long long)(cyc - cyc0), errors ? "FAILED" : "PASSED (lock-step with " REF_NAME ")");
    if (!quiet) printf("  video frames seen: %d\n", fg.frame_no);
#ifdef TOP_LS
    printf("  SDRAM protocol errors: %u\n", t->sdram_errors);
#endif
    if (!quiet || getenv("TB_STATS")) {
        printf("  interrupt vectors entered:");
        for (int v = 0; v < 64; v++) if (vecstat[v]) printf(" %02X:%llu", v, (unsigned long long)vecstat[v]);
        printf("\n  opcode groups (top 6 bits) executed: %d of 64 groups seen\n",
               (int)std::count_if(opstat, opstat + 64, [](uint64_t x){ return x != 0; }));
    }
    delete t;
    return errors ? 1 : 0;
}
