// UzeTang timing constraints (Gowin)
// The clocks are defined on the PLL / CLKDIV output pins: net names can change
// during synthesis, the primitives' pins do not.
create_clock -name sys_clk  -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}]
create_clock -name clk_tmds -period 7.407  -waveform {0 3.703}  [get_pins {pll_a/CLKOUT}]
create_clock -name clk_pix  -period 37.037 -waveform {0 18.518} [get_pins {pix_div/CLKOUT}]
create_clock -name clk_cpu  -period 34.858 -waveform {0 17.429} [get_pins {pll_b/CLKOUTD}]

// AVR <-> HDMI domains only meet through the dual-clock line buffer and
// synchronisers (frame toggle, audio toggle). clk_tmds only drives the OSER10
// serializers' fast clock input, which the tools handle internally.
set_clock_groups -asynchronous -group [get_clocks {clk_cpu}] -group [get_clocks {clk_pix}] -group [get_clocks {clk_tmds}]
