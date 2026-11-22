#include "Vtb_ref.h"
#include "verilated.h"
#include <cstdio>
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_ref* t = new Vtb_ref; FILE* f = fopen("sym.txt", "w"); FILE* fa = fopen("audio_in.txt", "w");
    t->rst = 1; t->clk = 0; t->eval();
    for (int i = 0; i < 20; i++) { t->clk ^= 1; t->eval(); }
    t->rst = 0;
    for (long n = 0; n < 858L*525*3 + 2000; n++) {
        t->clk = 1; t->eval();
        fprintf(f, "%u %u %u\n", t->q0, t->q1, t->q2);
        if (t->push) fprintf(fa, "%u %u\n", t->a0, t->a1);
        t->clk = 0; t->eval();
    }
    fclose(f); fclose(fa); return 0;
}
