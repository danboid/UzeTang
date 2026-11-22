/* UzeTang reference build: cuzebox-ex peripherals that are not attached
 * (ESP8266 / UART peer, haptics, keyboard). Mirrors cuzebox-ex's own
 * "no ESP" stubs in cu_uart.c. */
#include "types.h"
#include "cu_types.h"
void  cu_esp_reset_pin(uint8 state, auint cycle){ (void)state; (void)cycle; }
void  cu_esp_uzebox_write(uint8 val, auint cycle){ (void)val; (void)cycle; }
auint cu_esp_uzebox_read(auint cycle){ (void)cycle; return 0xFFu; }
void  cu_esp_uzebox_modify(auint port, auint val, auint cycle){ (void)port; (void)val; (void)cycle; }
auint cu_esp_uzebox_read_ready(auint cycle){ (void)cycle; return 0u; }
auint cu_esp_uzebox_write_ready(auint cycle){ (void)cycle; return (1u << UDRE0) | (1u << TXC0); }
auint cu_hap_process(auint prev, auint curr){ (void)prev; (void)curr; return 0u; }
auint cu_kbd_process(auint prev, auint curr){ (void)prev; (void)curr; return 0u; }
