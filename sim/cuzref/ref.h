#ifndef UZETANG_REF_H
#define UZETANG_REF_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void ref_init(const uint8_t* crom, int bootpri);
extern int ref_spiram_banks;   /* SPI RAM size in 64 KB banks (default 2) */
void ref_step(void);
uint32_t ref_pc(void);
uint32_t ref_cycle(void);
const uint8_t* ref_iors(void);
const uint8_t* ref_sram(void);
const uint8_t* ref_crom(void);
const uint8_t* ref_eepr(void);
uint32_t ref_tcnt1(void);
#ifdef __cplusplus
}
#endif
#endif
