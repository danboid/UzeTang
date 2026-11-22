# UzeTang - Gowin command line build (Gowin EDA, e.g. V1.9.9 or newer)
#   env -u DISPLAY -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen gw_sh build.tcl
# (gw_sh can be run from any directory; the paths below are relative to the
# folder this script is in.) The bitstream ends up in impl/pnr/uzetang.fs
cd [file dirname [file normalize [info script]]]
set_device GW2AR-LV18QN88C8/I7 -device_version C

add_file -type verilog "rtl/tang20k/uzetang_top.v"
add_file -type verilog "rtl/uzebox_system.v"
add_file -type verilog "rtl/uzebox_core.v"
add_file -type verilog "rtl/avr_soc.v"
add_file -type verilog "rtl/avr_cpu.v"
add_file -type verilog "rtl/avr_io.v"
add_file -type verilog "rtl/flash_bank.v"
add_file -type verilog "rtl/snes_pad.v"
add_file -type verilog "rtl/spiram_emu.v"
add_file -type verilog "rtl/sdram_ctl.v"
add_file -type verilog "rtl/video_capture.v"
add_file -type verilog "rtl/framelock.v"
add_file -type verilog "rtl/uzebox_hdmi.v"
add_file -type verilog "rtl/hdmi/hdmi.sv"
add_file -type verilog "rtl/hdmi/tmds_channel.sv"
add_file -type verilog "rtl/hdmi/packet_picker.sv"
add_file -type verilog "rtl/hdmi/packet_assembler.sv"
add_file -type verilog "rtl/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "rtl/hdmi/audio_info_frame.sv"
add_file -type verilog "rtl/hdmi/audio_sample_packet.sv"
add_file -type verilog "rtl/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "rtl/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "rtl/hdmi/serializer.sv"
add_file -type cst "rtl/tang20k/uzetang.cst"
add_file -type sdc "rtl/tang20k/uzetang.sdc"

set_option -synthesis_tool gowinsynthesis
set_option -top_module uzetang_top
set_option -output_base_name uzetang
set_option -verilog_std sysv2017
set_option -include_path {rtl}
set_option -rw_check_on_ram 1
set_option -place_option 2
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_cpu_as_gpio 1

run all
