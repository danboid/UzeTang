// ============================================================================
//  tb_system.cpp - full UzeTang system simulation
//
//  Simulates uzebox_system (AVR core, frame lock, line buffer, HDMI encoder,
//  SDRAM controller) with real clock ratios (AVR 28.6875 MHz, pixel 27 MHz),
//  an SDRAM model, a bit-level SD card (SPI mode, SDHC, CRC16) backed by a
//  disk image file, and scripted controller input. HDMI frames are captured
//  from the encoder's RGB input and written as PPM files.
//
//  usage: tb_system flash.hex [options]
//    -d disk.img     SD card image (raw, FAT16/FAT32)
//    -t frames       number of HDMI frames to simulate
//    -f a,b,c        dump HDMI frames a,b,c to hdmi_NNN.ppm
//    -k f:mask:len   press buttons 'mask' (SNES bit order) at frame f for len frames
//    -g game.hex     preload a game at 0x0000 as well
//    -n              disable frame lock
// ============================================================================
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <set>
#include "Vsim_system.h"
#include "Vsim_system___024root.h"
#include "verilated.h"

static uint8_t flash[65536];

static bool load_hex(const char* fn, bool clear)
{
    FILE* f = fopen(fn, "r");
    if (!f) { perror(fn); return false; }
    if (clear) memset(flash, 0xFF, sizeof(flash));
    char line[600]; uint32_t base = 0;
    while (fgets(line, sizeof line, f)) {
        if (line[0] != ':') continue;
        unsigned cnt, addr, type;
        sscanf(line + 1, "%2x%4x%2x", &cnt, &addr, &type);
        if (type == 0) {
            for (unsigned i = 0; i < cnt; i++) {
                unsigned b; sscanf(line + 9 + i * 2, "%2x", &b);
                uint32_t a = base + addr + i;
                if (a < 65536) flash[a] = (uint8_t)b;
            }
        } else if (type == 2) { unsigned s; sscanf(line + 9, "%4x", &s); base = s << 4; }
        else if (type == 4) { unsigned s; sscanf(line + 9, "%4x", &s); base = s << 16; }
        else if (type == 1) break;
    }
    fclose(f);
    return true;
}

// ---------------------------------------------------------------------------
// SD card model (SPI mode)
// ---------------------------------------------------------------------------
struct SdCard {
    FILE* img = nullptr;
    uint64_t size = 0;
    // SPI bit level
    int sck_q = 0, cs_q = 1;
    uint8_t in_b = 0; int bitcnt = 0;
    uint8_t out_sh = 0xFF; int miso = 1;
    // protocol
    std::vector<uint8_t> outq;   // bytes queued for output
    uint8_t cmd[6]; int cmdlen = 0;
    bool app = false, idle = true;
    int acmd41_cnt = 0;
    bool crc_on = false;
    // multi-block read / write state
    bool mbr = false; uint32_t mbr_blk = 0;
    int wr_state = 0; uint32_t wr_blk = 0; std::vector<uint8_t> wr_buf;
    uint64_t reads = 0, writes = 0, cmds = 0;

    static uint8_t crc7(const uint8_t* d, int n) {
        uint8_t c = 0;
        for (int i = 0; i < n; i++) {
            uint8_t b = d[i];
            for (int j = 0; j < 8; j++) {
                c <<= 1;
                if ((b ^ c) & 0x80) c ^= 0x09;
                b <<= 1;
            }
        }
        return c & 0x7F;
    }
    static uint16_t crc16(const uint8_t* d, int n) {
        uint16_t c = 0;
        for (int i = 0; i < n; i++) {
            c ^= (uint16_t)d[i] << 8;
            for (int j = 0; j < 8; j++) c = (c & 0x8000) ? (c << 1) ^ 0x1021 : (c << 1);
        }
        return c;
    }
    void queue_block(uint32_t blk) {
        uint8_t buf[512]; memset(buf, 0, 512);
        if (img && (uint64_t)blk * 512 < size) {
            fseek(img, (long)blk * 512, SEEK_SET);
            size_t r = fread(buf, 1, 512, img); (void)r;
        }
        reads++;
        for (int i = 0; i < 3; i++) outq.push_back(0xFF);    // access time
        outq.push_back(0xFE);
        for (int i = 0; i < 512; i++) outq.push_back(buf[i]);
        uint16_t c = crc16(buf, 512);
        outq.push_back(c >> 8); outq.push_back(c & 0xFF);
    }
    void r1(uint8_t v) { outq.push_back(0xFF); outq.push_back(v); }
    void command() {
        cmds++;
        uint8_t idx = cmd[0] & 0x3F;
        uint32_t arg = (cmd[1] << 24) | (cmd[2] << 16) | (cmd[3] << 8) | cmd[4];
        if (crc_on || idx == 0 || idx == 8) {
            if (crc7(cmd, 5) != (cmd[5] >> 1)) { r1(0x08 | (idle ? 1 : 0)); app = false; return; }
        }
        uint8_t st = idle ? 0x01 : 0x00;
        bool was_app = app; app = false;
        if (was_app && idx == 41) {
            if (++acmd41_cnt >= 3) idle = false;
            r1(idle ? 0x01 : 0x00);
            return;
        }
        switch (idx) {
        case 0:  idle = true; acmd41_cnt = 0; crc_on = false; mbr = false; r1(0x01); break;
        case 8:  r1(st); outq.push_back(0x00); outq.push_back(0x00);
                 outq.push_back(0x01); outq.push_back(arg & 0xFF); break;
        case 55: app = true; r1(st); break;
        case 59: crc_on = arg & 1; r1(st); break;
        case 58: r1(st); outq.push_back(0xC0); outq.push_back(0xFF);
                 outq.push_back(0x80); outq.push_back(0x00); break;
        case 16: r1(st); break;
        case 17: r1(st); queue_block(arg); break;
        case 18: r1(st); mbr = true; mbr_blk = arg; queue_block(mbr_blk++); break;
        case 12: mbr = false; outq.clear(); outq.push_back(0xFF); outq.push_back(st);
                 outq.push_back(0x00); outq.push_back(0xFF); break;
        case 24: r1(st); wr_state = 1; wr_blk = arg; wr_buf.clear(); break;
        case 13: r1(st); outq.push_back(0x00); break;
        case 9: case 10: {
            r1(st);
            uint8_t reg[16]; memset(reg, 0, 16);
            if (idx == 9) {           // CSD v2: C_SIZE = size/512K - 1
                uint32_t cs = (uint32_t)(size / (512 * 1024)) - 1;
                reg[0] = 0x40; reg[7] = (cs >> 16) & 0x3F; reg[8] = cs >> 8; reg[9] = cs;
            }
            outq.push_back(0xFF); outq.push_back(0xFE);
            for (int i = 0; i < 16; i++) outq.push_back(reg[i]);
            uint16_t c = crc16(reg, 16); outq.push_back(c >> 8); outq.push_back(c & 0xFF);
            break; }
        default: r1(st | 0x04); break;          // illegal command
        }
    }
    uint8_t next_out() {
        if (outq.empty()) {
            if (mbr) queue_block(mbr_blk++);
            else return 0xFF;
        }
        uint8_t b = outq.front(); outq.erase(outq.begin());
        return b;
    }
    void byte_in(uint8_t b) {
        if (wr_state == 1) {                       // waiting for data token
            if (b == 0xFE) wr_state = 2;
            return;
        }
        if (wr_state == 2) {
            wr_buf.push_back(b);
            if (wr_buf.size() == 514) {
                if (img) { fseek(img, (long)wr_blk * 512, SEEK_SET); fwrite(wr_buf.data(), 1, 512, img); fflush(img); }
                writes++;
                outq.push_back(0x05); outq.push_back(0x00); outq.push_back(0x00);
                wr_state = 0;
            }
            return;
        }
        if (cmdlen == 0 && (b & 0xC0) != 0x40) return;
        cmd[cmdlen++] = b;
        if (cmdlen == 6) { cmdlen = 0; outq.clear(); command(); }
    }
    // called every AVR clock with current pin levels; returns MISO
    int step(int sck, int mosi, int cs_n) {
        if (cs_n) {
            if (!cs_q) { bitcnt = 0; cmdlen = 0; }
            cs_q = 1; sck_q = sck; miso = 1;
            return 1;
        }
        if (cs_q) { cs_q = 0; out_sh = next_out(); miso = out_sh >> 7; bitcnt = 0; }
        if (sck && !sck_q) {                       // rising: sample MOSI
            in_b = (in_b << 1) | (mosi & 1);
            if (++bitcnt == 8) { bitcnt = 0; byte_in(in_b); }
        } else if (!sck && sck_q) {                // falling: shift out
            if (bitcnt == 0) out_sh = next_out(); else out_sh <<= 1;
            miso = (out_sh >> 7) & 1;
        }
        sck_q = sck;
        return miso;
    }
};

// ---------------------------------------------------------------------------
struct Press { int frame, len; uint16_t mask; };

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);
    if (argc < 2) { fprintf(stderr, "usage: %s flash.hex [opts]\n", argv[0]); return 2; }
    const char* diskfn = nullptr;
    const char* gamefn = nullptr;
    int total_frames = 60;
    bool lock = true;
    int pad_conn = 1;
    std::set<int> dump;
    std::vector<Press> presses;
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "-d") && i + 1 < argc) diskfn = argv[++i];
        else if (!strcmp(argv[i], "-g") && i + 1 < argc) gamefn = argv[++i];
        else if (!strcmp(argv[i], "-t") && i + 1 < argc) total_frames = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-n")) lock = false;
        else if (!strcmp(argv[i], "-u")) pad_conn = 0;
        else if (!strcmp(argv[i], "-f") && i + 1 < argc) {
            std::string s = argv[++i]; size_t p = 0;
            while (true) { dump.insert(atoi(s.c_str() + p)); p = s.find(',', p); if (p == std::string::npos) break; p++; }
        } else if (!strcmp(argv[i], "-k") && i + 1 < argc) {
            Press pr; unsigned m;
            sscanf(argv[++i], "%d:%x:%d", &pr.frame, &m, &pr.len); pr.mask = m;
            presses.push_back(pr);
        }
    }
    if (!load_hex(argv[1], true)) return 2;
    if (gamefn && !load_hex(gamefn, false)) return 2;

    SdCard sd;
    if (diskfn) {
        sd.img = fopen(diskfn, "r+b");
        if (!sd.img) { perror(diskfn); return 2; }
        fseek(sd.img, 0, SEEK_END); sd.size = ftell(sd.img);
    }

    Vsim_system* t = new Vsim_system;
    auto* R = t->rootp;
    t->clk = 0; t->clk_pix = 0; t->rst = 1; t->rst_pix = 1; t->lock_en = lock;
    t->ld_we = 0; t->pad1_buttons = 0; t->pad1_connected = pad_conn; t->sd_miso = 1;
    t->eval();

    // time base in picoseconds
    const uint64_t T_CPU = 34858;     // 28.6875 MHz
    const uint64_t T_PIX = 37037;     // 27 MHz
    uint64_t now = 0, n_cpu = T_CPU / 2, n_pix = T_PIX / 2;
    uint64_t cpu_cycles = 0, pix_cycles = 0, ce_cycles = 0, wait_cycles = 0;
    uint64_t spi_edges = 0, cs_low = 0;

    // load flash during reset
    int ldw = 0;
    std::vector<uint8_t> fb(720 * 480 * 3);
    int hframe = 0, prev_cx = -1, prev_cy = -1;
    uint64_t last_report = 0;

    while (hframe < total_frames) {
        bool cpu_edge = n_cpu <= n_pix;
        now = cpu_edge ? n_cpu : n_pix;
        if (cpu_edge) {
            t->clk = !t->clk; n_cpu += T_CPU / 2;
            if (t->clk) {
                // rising edge of AVR clock: drive inputs before the edge settles
                cpu_cycles++;
                // the boot section (word 0x7800+) is filled by the core's boot
                // ROM copier; load only the game area here
                if (ldw < 0x7800) {
                    t->ld_we = 1; t->ld_addr = ldw; t->ld_data = flash[ldw * 2] | (flash[ldw * 2 + 1] << 8);
                    ldw++;
                } else {
                    t->ld_we = 0;
                    if (cpu_cycles == 0x7800 + 4096) t->rst = 0;
                }
            }
        } else {
            t->clk_pix = !t->clk_pix; n_pix += T_PIX / 2;
            if (t->clk_pix) {
                pix_cycles++;
                if (pix_cycles == 64) t->rst_pix = 0;
            }
        }
        t->eval();
        if (cpu_edge && t->clk) {
            if (t->cpu_ce) ce_cycles++; else wait_cycles++;
            t->sd_miso = sd.step(t->sd_sck, t->sd_mosi, t->sd_cs_n);
            { static int sck_q = 0; if (t->sd_sck && !sck_q) spi_edges++; sck_q = t->sd_sck;
              if (!t->sd_cs_n) cs_low++; }
            t->eval();
        }
        if (!cpu_edge && t->clk_pix) {
            // capture: rgb presented now belongs to pixel (cx-1)
            int cx = R->sim_system__DOT__sys__DOT__hdmi_out__DOT__cx;
            int cy = R->sim_system__DOT__sys__DOT__hdmi_out__DOT__cy;
            if (prev_cx >= 0 && prev_cx < 720 && prev_cy < 480) {
                uint32_t rgb = R->sim_system__DOT__sys__DOT__hdmi_out__DOT__rgb;
                uint8_t* p = &fb[(prev_cy * 720 + prev_cx) * 3];
                p[0] = rgb >> 16; p[1] = rgb >> 8; p[2] = rgb;
            }
            if (prev_cy == 479 && cy == 480 && cx == 0) {
                if (dump.count(hframe)) {
                    char fn[64]; snprintf(fn, sizeof fn, "hdmi_%03d.ppm", hframe);
                    FILE* f = fopen(fn, "wb");
                    fprintf(f, "P6\n720 480\n255\n"); fwrite(fb.data(), 1, fb.size(), f); fclose(f);
                }
                hframe++;
                // controller script (per HDMI frame)
                uint16_t b = 0;
                for (auto& pr : presses) if (hframe >= pr.frame && hframe < pr.frame + pr.len) b |= pr.mask;
                t->pad1_buttons = b;
                if (hframe % 10 == 0 || dump.count(hframe - 1)) {
                    printf("frame %4d: cpu %llu cyc, paused %.2f%%, locked %d, pc %04X, sd cmds %llu reads %llu writes %llu, sdram err %u, sck %llu cslow %llu\n",
                        hframe, (unsigned long long)cpu_cycles,
                        100.0 * wait_cycles / (double)(ce_cycles + wait_cycles + 1),
                        t->video_locked, t->dbg_pc, (unsigned long long)sd.cmds,
                        (unsigned long long)sd.reads, (unsigned long long)sd.writes, t->sdram_errors,
                        (unsigned long long)spi_edges, (unsigned long long)cs_low);
                    fflush(stdout);
                }
            }
            prev_cx = cx; prev_cy = cy;
        }
    }
    printf("done: %d HDMI frames, %llu AVR cycles (%llu active)\n", hframe,
           (unsigned long long)cpu_cycles, (unsigned long long)ce_cycles);
    if (sd.img) fclose(sd.img);
    delete t;
    return 0;
}
