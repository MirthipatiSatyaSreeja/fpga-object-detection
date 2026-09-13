## Arty A7-100T, XC7A100TCSG324-1

## 100 MHz clock
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk100mhz }]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports { clk100mhz }]

## Pmod VGA J1 on JA: red and blue
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }]
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }]
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }]
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }]

set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }]
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }]
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }]

## Pmod VGA J2 on JB: green and sync
set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }]
set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }]
set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }]
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }]

set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { vga_hs }]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { vga_vs }]

## OV7670 D0..D7 on JC pins 1,2,3,4,7,8,9,10
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports { cam_d[0] }]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { cam_d[1] }]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports { cam_d[2] }]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports { cam_d[3] }]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { cam_d[4] }]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { cam_d[5] }]
set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports { cam_d[6] }]
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports { cam_d[7] }]

## OV7670 control on JD pins 1,2,3,4,7,8
set_property -dict { PACKAGE_PIN D4 IOSTANDARD LVCMOS33 } [get_ports { cam_pclk }]
set_property -dict { PACKAGE_PIN D3 IOSTANDARD LVCMOS33 } [get_ports { cam_vsync }]
set_property -dict { PACKAGE_PIN F4 IOSTANDARD LVCMOS33 } [get_ports { cam_href }]
set_property -dict { PACKAGE_PIN F3 IOSTANDARD LVCMOS33 } [get_ports { cam_xclk }]
set_property -dict { PACKAGE_PIN E2 IOSTANDARD LVCMOS33 } [get_ports { cam_reset }]
set_property -dict { PACKAGE_PIN D2 IOSTANDARD LVCMOS33 } [get_ports { cam_pwdn }]

## Camera SCCB on the Arty ChipKit I2C header
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports { cam_scl }]
set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports { cam_sda }]

## Enable the Arty's physical 2.2 kOhm I2C pull-up resistors
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports { cam_scl_pup }]
set_property -dict { PACKAGE_PIN A13 IOSTANDARD LVCMOS33 } [get_ports { cam_sda_pup }]

## User LEDs LD4..LD7
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T9 IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

## OV7670 PCLK timing. D4 requires the dedicated-clock-route override on
## this project/board routing. This affects only the camera PCLK input route.
create_clock -add -name cam_pclk_in -period 40.000 -waveform {0.000 20.000} [get_ports { cam_pclk }]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {cam_pclk_IBUF}]

## The camera PCLK domain is asynchronous to the 100 MHz/MMCM domain.
set_clock_groups -asynchronous \
    -group [get_clocks {cam_pclk_in}] \
    -group [get_clocks {sys_clk_pin}]
