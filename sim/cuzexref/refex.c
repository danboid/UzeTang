/*
 * Thin wrapper exposing the CUzeBox AVR core (GPL v3, Sandor Zsuga et al.)
 * as a single-step reference model for the UzeTang lock-step testbench.
 */
#include "cu_avr.c"
#include "cu_spir.h"

#include "ref.h"

int ref_spiram_banks = 2;

void ref_init(const uint8_t* crom, int bootpri)
{
 memset(&cpu_state, 0, sizeof(cpu_state));
 memcpy(cpu_state.crom, crom, 65536U);
 memset(cpu_state.eepr, 0xFF, sizeof(cpu_state.eepr));
 cpu_state.wd_seed = 0U;
 cu_avr_autofuse(bootpri ? TRUE : FALSE);
 cu_spir_set_size((auint)ref_spiram_banks);   /* default 128 KB (23LC1024) */
 cu_avr_reset();
}

/* Execute one instruction (plus any interrupt entry following it). */
void ref_step(void)
{
 cu_avr_exec();
 if (video_cycle >= VIDEO_CY_MAX){ video_cycle -= VIDEO_CY_MAX; }
}

uint32_t ref_pc(void)    { return cpu_state.pc & 0xFFFFU; }
uint32_t ref_cycle(void) { return cpu_state.cycle; }
const uint8_t* ref_iors(void) { return cpu_state.iors; }
const uint8_t* ref_sram(void) { return cpu_state.sram; }
const uint8_t* ref_crom(void) { return cpu_state.crom; }
const uint8_t* ref_eepr(void) { return cpu_state.eepr; }
uint32_t ref_tcnt1(void) { return (cpu_state.cycle - timer1_base) & 0xFFFFU; }
