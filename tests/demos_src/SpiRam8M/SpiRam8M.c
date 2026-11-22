/*
 *  SpiRam8M - UzeTang SPI RAM size and pattern test
 *  Copyright (C) 2026 UzeTang contributors - GPL v3 or later.
 *
 *  Detects the SPI RAM size with the kernel's SpiRamInitGetSize(), writes a
 *  pattern to the start and end of every 64 KB bank and a block that
 *  crosses each bank boundary (sequential mode), then reads everything
 *  back. Run it in lock-step with CUzeBox-ex set to the same SPI RAM size:
 *  any wrong byte from the emulated SPI RAM makes the run diverge.
 */
#include <avr/io.h>
#include <avr/pgmspace.h>
#include <uzebox.h>
#include <spiram.h>

#if   (TILE_WIDTH == 6) && (TILE_HEIGHT == 8)
	#include "data/font-6x8-full.inc"
#elif (TILE_WIDTH == 6) && (TILE_HEIGHT == 12)
	#include "data/font-6x12-full.inc"
#else
	#include "data/font-8x8-full.inc"
#endif

static u32 pat(u8 bank, u8 k)
{
	return ((u32)bank << 24) ^ ((u32)k << 16) ^ ((u32)(bank * 37U + k) << 8) ^ 0x5AU;
}

int main(){
	u16 size;
	u16 b;
	u16 err = 0U;
	u8  buf[32];
	u8  i;

	SetFontTable(font);
	ClearVram();
	size = SpiRamInitGetSize();
	Print(2, 2, PSTR("SPI RAM 64K BANKS:"));
	PrintInt(25, 2, size, false);
	if (size == 0U){ while(1); }

	/* write */
	for (b = 0U; b < size; b++){
		SpiRamWriteU32((u8)b, 0x0000U, pat((u8)b, 0U));
		SpiRamWriteU32((u8)b, 0xFFF0U - 16U, pat((u8)b, 1U));
		if ((b & 15U) == 0U){ PrintInt(25, 4, b, false); }
	}
	/* then the blocks crossing each bank boundary (these overwrite the
	** first 24 bytes of every bank but bank 0) */
	for (b = 0U; b + 1U < size; b++){
		for (i = 0U; i < 32U; i++){ buf[i] = (u8)(b + i * 7U); }
		SpiRamWriteFrom((u8)b, 0xFFF8U, buf, 32U);
	}
	/* read back */
	for (b = 0U; b < size; b++){
		if (b + 1U < size){
			SpiRamReadInto((u8)b, 0xFFF8U, buf, 32U);
			for (i = 0U; i < 32U; i++){
				if (buf[i] != (u8)(b + i * 7U)){ err++; }
			}
		}
		/* bank b's start was overwritten by bank b-1's crossing block
		** (bytes 0..23), so only check the end pattern and, for bank 0,
		** the start pattern */
		if (SpiRamReadU32((u8)b, 0xFFF0U - 16U) != pat((u8)b, 1U)){ err++; }
		if ((b == 0U) && (SpiRamReadU32(0U, 0x0000U) != pat(0U, 0U))){ err++; }
	}
	Print(2, 6, PSTR("ERRORS:"));
	PrintInt(25, 6, err, false);
	Print(2, 8, (err == 0U) ? PSTR("SPI RAM TEST PASSED") : PSTR("SPI RAM TEST FAILED"));
	while(1){ WaitVsync(1); }
}
