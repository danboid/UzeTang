# UzeTang simulation: lock-step comparison against CUzeBox
RTL      = ../rtl/avr_soc.v ../rtl/avr_cpu.v ../rtl/avr_io.v ../rtl/flash_bank.v gowin_prims.v
VFLAGS   = -I../rtl -O3 --x-assign fast --x-initial fast --public-flat-rw -Wno-fatal -Wno-WIDTH \
           --top-module avr_soc -CFLAGS "-O2 -I$(CURDIR) -I$(CURDIR)/cuzref"
# Reference emulator: cuzebox-ex (default, REF=ex) or original cuzebox (REF=cz)
REF ?= ex
ifeq ($(REF),cz)
REFDIR   = cuzref
REFSRC   = ref.c cu_avrc.c cu_avrfg.c cu_ctr.c cu_spi.c cu_spir.c
else
REFDIR   = cuzexref
REFSRC   = refex.c cu_avrc.c cu_avrfg.c cu_ctr_ref.c cu_spi.c cu_spir.c stubs.c
endif
REFOBJ   = $(patsubst %.c,refobj/%.o,$(REFSRC))

all: obj_dir/Vavr_soc

refobj/%.o: $(REFDIR)/%.c
	@mkdir -p refobj
	gcc -O2 -std=gnu99 -DFLAG_SELFCONT=1 -DFLAG_NOCONSOLE=1 -c $< -o $@

refobj/libcuzref.a: $(REFOBJ)
	ar rcs $@ $^

obj_dir/Vavr_soc: $(RTL) tb_lockstep.cpp refobj/libcuzref.a
	verilator --cc --exe --build -j 2 $(VFLAGS) $(RTL) $(CURDIR)/tb_lockstep.cpp \
	  -LDFLAGS "$(CURDIR)/refobj/libcuzref.a" -o Vavr_soc

clean:
	rm -rf obj_dir refobj

# ---- full system simulation ----
SYSRTL = sim_system.v sdram_model.v gowin_prims.v ../rtl/flash_bank.v ../rtl/uzebox_system.v ../rtl/uzebox_core.v ../rtl/avr_soc.v \
         ../rtl/avr_cpu.v ../rtl/avr_io.v ../rtl/snes_pad.v ../rtl/spiram_emu.v ../rtl/video_capture.v \
         ../rtl/framelock.v ../rtl/sdram_ctl.v ../rtl/uzebox_hdmi.v \
         ../rtl/hdmi/hdmi.sv ../rtl/hdmi/tmds_channel.sv ../rtl/hdmi/packet_picker.sv \
         ../rtl/hdmi/packet_assembler.sv ../rtl/hdmi/audio_clock_regeneration_packet.sv \
         ../rtl/hdmi/audio_info_frame.sv ../rtl/hdmi/audio_sample_packet.sv \
         ../rtl/hdmi/auxiliary_video_information_info_frame.sv \
         ../rtl/hdmi/source_product_description_info_frame.sv ../rtl/hdmi/serializer.sv

system: sysobj/Vsim_system

sysobj/Vsim_system: $(SYSRTL) tb_system.cpp
	verilator --cc --exe --build -j 2 -O3 --x-assign fast --x-initial fast --public-flat-rw \
	  -Wno-fatal -Wno-WIDTH -Wno-lint -Wno-style --top-module sim_system -Mdir sysobj -I../rtl \
	  $(SYSRTL) $(CURDIR)/tb_system.cpp -o Vsim_system

# ---- full system simulation with the open-source flow's HDMI encoder ----
SYSRTL_LITE = $(filter-out ../rtl/hdmi/%.sv,$(SYSRTL)) ../rtl/hdmi/hdmi_lite.v
system_lite: sysobj_lite/Vsim_system
sysobj_lite/Vsim_system: $(SYSRTL_LITE) tb_system.cpp
	verilator --cc --exe --build -j 2 -O3 --x-assign fast --x-initial fast --public-flat-rw \
	  -Wno-fatal -Wno-WIDTH -Wno-lint -Wno-style --top-module sim_system -Mdir sysobj_lite -I../rtl \
	  -DUZETANG_HDMI_LITE -DHDMI_NO_SERIALIZER $(SYSRTL_LITE) $(CURDIR)/tb_system.cpp -o Vsim_system

# ---- lock-step with SPI RAM + SDRAM ----
LSRTL = ls_top.v sdram_model.v $(RTL) ../rtl/spiram_emu.v ../rtl/sdram_ctl.v
lsram: lsobj/Vls_top
lsobj/Vls_top: $(LSRTL) tb_lockstep.cpp refobj/libcuzref.a
	verilator --cc --exe --build -j 2 -O3 --x-assign fast --x-initial fast --public-flat-rw -Wno-fatal \
	  -Wno-WIDTH --top-module ls_top -Mdir lsobj -I../rtl -CFLAGS "-O2 -I$(CURDIR) -DTOP_LS" \
	  $(LSRTL) $(CURDIR)/tb_lockstep.cpp -LDFLAGS "$(CURDIR)/refobj/libcuzref.a" -o Vls_top

# ---- lock-step with 8 MB SPI RAM (run Vls_top with -r 128) ----
lsram8: lsobj8/Vls_top
lsobj8/Vls_top: $(LSRTL) tb_lockstep.cpp refobj/libcuzref.a
	verilator --cc --exe --build -j 2 -O3 --x-assign fast --x-initial fast --public-flat-rw -Wno-fatal \
	  -Wno-WIDTH --top-module ls_top -Mdir lsobj8 -I../rtl -DLS_SPIRAM_BITS=23 -CFLAGS "-O2 -I$(CURDIR) -DTOP_LS" \
	  $(LSRTL) $(CURDIR)/tb_lockstep.cpp -LDFLAGS "$(CURDIR)/refobj/libcuzref.a" -o Vls_top
