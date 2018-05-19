--[[
camera side "glue" script to use rawopint v0.25 with remoteshoot
http://chdk.wikia.com/wiki/Lua/Scripts:_Raw_Meter_Intervalometer

-shots and -int options to remoteshoot are passed through
use like 
rs -script=rawopint_rs.lua -shots=100 -int=5

other options are ignored
--]]

ui_shots=rs_opts.shots --"Shots (0 = unlimited)"
ui_interval_s10=rs_opts.int/100 --"Interval Sec/10"
ui_use_remote=false --"USB remote interval control"
ui_meter_width_pct=90 --"Meter width %" [1 100]
ui_meter_height_pct=90 --"Meter height %" [1 100]
ui_meter_step=15 --"Meter step"
ui_max_ev_change_e=3 --"Max Ev change" {1/16 1/8 1/4 1/3 1/2 1}
ui_ev_use_initial=false --"Use initial Ev as target"
ui_ev_shift_e=10 --"Ev shift" {-2.1/2 -2.1/4 -2 -1.3/4  -1.1/2 -1.1/4 -1 -3/4 -1/2 -1/4 0 1/4 1/2 3/4 1 1.1/4 1.1/2 1.3/4 2 2.1/4 2.1/2}
ui_bv_ev_shift_pct=0 --"Bv Ev shift %" [0 100]
ui_bv_ev_shift_base_e=0 --"Bv Ev shift base Bv" {First -1 -1/2 0 1/2 1 1.1/2 2 2.1/2 3 3.1/2 4 4.1/2 5 5.1/2 6 6.1/2 7 7.1/2 8 8.1/2 9 9.1/2 10 10.1/2 11 11.1/2 12 12.1/2 13}
ui_tv_max_s1k=1000 --"Max Tv Sec/1000"
ui_tv_min_s100k=10 --"Min Tv Sec/100K" [1 99999]
ui_sv_target_mkt=80 --"Target ISO"
ui_tv_sv_adj_s1k=250 --"ISO adj Tv Sec/1000"
ui_sv_max_mkt=800 --"Max ISO"
ui_tv_nd_thresh_s10k=1 --"ND Tv Sec/10000"
ui_nd_hysteresis_e=2 --"ND hysteresis Ev" {none 1/4 1/2 3/4 1}
ui_nd_value=288 --"ND value APEX*96 (0=guess)" [0 1000]
ui_meter_high_thresh_e=2 --"Meter high thresh Ev" {1/2 3/4 1 1.1/4 1.1/2 1.3/4}
ui_meter_high_limit_e=3 --"Meter high limit Ev" {1 1.1/4 1.1/2 1.3/4 2 2.1/4}
ui_meter_high_limit_weight=200 --"Meter high max weight" [100 300]
ui_meter_low_thresh_e=5 --"Meter low thresh -Ev" {1/2 3/4 1 1.1/4 1.1/2 1.3/4 2 2.1/4 2.1/2 2.3/4 3 3.1/4 3.1/2 3.3/4 4 4.1/4 4.1/2 4.3/4 5}
ui_meter_low_limit_e=7 --"Meter low limit -Ev" {1 1.1/4 1.1/2 1.3/4 2 2.1/4 2.1/2 2.3/4 3 3.1/4 3.1/2 3.3/4 4 4.1/4 4.1/2 4.3/4 5 5.1/4 5.1/2 5.3/4 6}
ui_meter_low_limit_weight=200 --"Meter low max weight" [100 300]
ui_exp_over_thresh_frac=3000 --"Overexp thresh x/100k (0=Off)" [0 100000]
ui_exp_over_margin_e=3 --"Overexp Ev range" {1/32 1/16 1/8 1/4 1/3 1/2 2/3 3/4 1}
ui_exp_over_weight_max=200 --"Overexp max weight" [100 300]
ui_exp_over_prio=0 --"Overexp prio" [0 200]
ui_exp_under_thresh_frac=10000 --"Underexp thresh x/100k (0=Off)" [0 100000]
ui_exp_under_margin_e=5 --"Underexp -Ev" {7 6 5.1/2 5 4.1/2 4 3.1/2 3 2.1/2 2}
ui_exp_under_weight_max=200 --"Underexp max weight" [100 300]
ui_exp_under_prio=0 --"Underexp prio" [0 200]
ui_histo_step_t={} --"Histogram step (pixels)" {5 7 9 11 15 19 23 27 31} table
ui_histo_step_t.value=5
ui_zoom_mode_t={} -- "Zoom mode" {Off Pct Step} table
ui_zoom_mode_t.value="Off"
ui_zoom=0 -- "Zoom value" [0 500]
ui_sd_mode_t={} -- "Focus override mode" {Off MF AFL AF} table
ui_sd_mode_t.value="Off" -- "Focus override mode" {Off MF AFL AF} table
ui_sd=0 -- "Focus dist (mm)" long
ui_image_size_e=0 --"Image size" {Default L M1 M2 M3 S W}
ui_use_raw_e=0 --"Use raw" {Default Yes No}
ui_use_cont=true --"Use cont. mode if set"
ui_start_hour=-1 -- "Start hour (-1 off)" [-1 23]
ui_start_min=0 -- "Start minute" [0 59]
ui_start_sec=0 -- "Start second" [0 59]
ui_display_mode_t={} --"Display" {On Off Blt_Off} table
ui_display_mode_t.value="On"
ui_shutdown_finish=false --"Shutdown on finish"
ui_shutdown_lowbat=true --"Shutdown on low battery"
ui_shutdown_lowspace=true --"Shutdown on low space"
ui_interval_warn_led=-1 --"Interval warn LED (-1=off)"
ui_interval_warn_beep=false --"Interval warn beep"
ui_do_draw=false --"Draw debug info"
ui_draw_meter_t={} --" Meter area" {None Corners Box} table
ui_draw_meter_t.value="None"
ui_draw_gauge_y_pct=0 --" Gauge Y offset %" [0 94]
ui_log_mode={} --"Log mode" {None Append Replace} table
ui_log_mode.value="Append"
ui_raw_hook_sleep=0 --"Raw hook sleep ms (0=off)" [0 100]
ui_noyield=false --"Disable script yield"
ui_sim=false --"Run simulation"
loadfile('A/CHDK/SCRIPTS/rawopint.lua')()

