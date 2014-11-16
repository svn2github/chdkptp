--[[
(C)2014 msl

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2 as
  published by the Free Software Foundation.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
]]

--[[
module for user tab in gui
a place for user defined stuff
]]

ini = require("iniLib")

local m={}

function m.get_container_title()
    return "User"
end

function m.init()
    --ini file for modul gui_user
    ini_user, new = ini.read("gui_user_cfg")
    if new then
        ini_user.dcim_download = {
            dest = lfs.currentdir().."/images",
            raw = "OFF",
            gps = "OFF",
            pre = "OFF"
        }
        ini_user.remote_capture = {
        dest = lfs.currentdir()
        }
        ini.write(ini_user)
    end
    m.rs_dest   = ini_user.remote_capture.dest
    m.imdl_dest = ini_user.dcim_download.dest
    m.imdl_raw  = ini_user.dcim_download.raw
    m.imdl_gps  = ini_user.dcim_download.gps
    m.imdl_pre  = ini_user.dcim_download.pre
    return
end

function m.get_container()
    local usertab = iup.hbox{
        margin="4x4",
        gap="10",
        m.remote_capture_ui(),
        m.dcim_download_ui(),
    }
    return usertab
end

--[[
remote capture function as gui function
* Destination - dialog for file destination, default is chdkptp dir
* JPG Remote Shoot - shoot and save a JPG file in the destination (only available for cameras that support filewrite_task)
* DNG Remote Shoot - shoot and save a DNG file in the destination
]]
function m.remote_capture_ui()
    local gui_frame = iup.frame{
        title="Remote Capture",
        iup.vbox{
            gap="10",
            iup.button{
                title="Destination",
                size="75x15",
                fgcolor="0 0 255",
                --current path as tooltip
                tip=m.imdl_dest,
                action=function(self)
                    local dlg=iup.filedlg{
                        dialogtype = "DIR",
                        title = "Destination",
                        directory = m.rs_dest,
                    }
                    dlg:popup(iup_centerparent, iup_centerparent)
                    if dlg.status == "0" then
                        m.rs_dest = dlg.value
                        --update to new ini selection
                        ini_user.remote_capture.dest = m.rs_dest
                        ini.write(ini_user)
                        gui.infomsg("download destination %s\n", m.rs_dest)
                        --update path as tooltip
                        self.tip = m.rs_dest
                    end
                end,
            },
            iup.button{
                title="JPG Remote Shoot",
                size="75x15",
                fgcolor="255 0 0",
                tip="Does not work for all cameras!",
                action=function(self)
                    local cmd = string.format("rs '%s'", m.rs_dest)
                    add_status(cli:execute(cmd))
                end,
            },
            iup.button{
                title="DNG Remote Shoot",
                size="75x15",
                fgcolor="255 0 0",
                action=function(self)
                    local cmd = string.format("rs '%s' -dng", m.rs_dest)
                    add_status(cli:execute(cmd))
                end,
            },
        },
    }
    return gui_frame
end

--[[
-simple GUI mode for image download
-default destination is chdkptp/images
-subdirs are organized by capture date
-optional download from A/RAW & GPS data
]]
function m.dcim_download_ui()

    local raw_toggle = iup.toggle{
        title = "incl. A/RAW",
        value = m.imdl_raw,
        action=function(self, state)
            local new = state==1 and "ON" or "OFF"
            if new ~= state then
                m.imdl_raw = new
                ini_user.dcim_download.raw = m.imdl_raw
                ini.write(ini_user)
                self.value = m.imdl_raw
            end
        end
    }
    local gps_toggle = iup.toggle{
        title = "incl. GPS data",
        value = m.imdl_gps,
        action=function(self, state)
            local new = state==1 and "ON" or "OFF"
            if new ~= state then
                m.imdl_gps = new
                ini_user.dcim_download.gps = m.imdl_gps
                ini.write(ini_user)
                self.value = m.imdl_gps
            end
        end
    }
    local pre_toggle = iup.toggle{
        title = "pretend",
        value = m.imdl_pre,
        action=function(self, state)
            local new = state==1 and "ON" or "OFF"
            if new ~= state then
                m.imdl_pre = new
                ini_user.dcim_download.pre = m.imdl_pre
                ini.write(ini_user)
                self.value = m.imdl_pre
            end
        end
    }

    local gui_frame = iup.frame{
        title="Pic&Vid Download",
        iup.vbox{
            gap="10",
            iup.button{
                title="Destination",
                size="75x15",
                fgcolor="0 0 255",
                --current path as tooltip
                tip=m.imdl_dest,
                action=function(self)
                    local dlg=iup.filedlg{
                        dialogtype = "DIR",
                        title = "Destination",
                        directory = m.imdl_dest,
                    }
                    dlg:popup(iup_centerparent, iup_centerparent)
                    if dlg.status == "0" then
                        m.imdl_dest = dlg.value
                        --update to new ini selection
                        ini_user.dcim_download.dest = m.imdl_dest
                        ini.write(ini_user)
                        gui.infomsg("download destination %s\n", m.imdl_dest)
                        --update path as tooltip
                        self.tip = m.imdl_dest
                    end
                end,
            },
            iup.button{
                title="Download",
                size="75x15",
                fgcolor="0 0 0",
                tip="Does not overwrite existing files",
                action=function(self)
                    if con:is_connected() then
                        gui.infomsg("download started ...\n")
                        local pre = pre_toggle.value == "ON" and "-pretend" or ""
                        local cmd1 = "imdl "..pre.." -overwrite='n' -d="
                        local cmd2 = "mdl "..pre.." -overwrite='n'"
                        local path = string.gsub(m.imdl_dest, "\\", "/")
                        if string.sub(path, #path) ~= "/" then path = path.."/" end
                        local sub = "${mdate,%Y_%m_%d}/${name}"
                        add_status(cli:execute(cmd1..path..sub))
                        if raw_toggle.value == "ON" then
                            local check = con:execwait([[return os.stat("A/RAW")]])
                            if check and check.is_dir then
                                add_status(cli:execute(cmd1..path.."raw/"..sub.." A/RAW"))
                            end
                        end
                        if gps_toggle.value == "ON" then
                            local check = con:execwait([[return os.stat("A/DCIM/CANONMSC/GPS")]])
                            if check and check.is_dir then
                                add_status(cli:execute(cmd2.." A/DCIM/CANONMSC/GPS "..path.."gps/"))
                            end
                        end
                        gui.infomsg("... download finished\n")
                    else
                        gui.infomsg("No camera connected!\n")
                    end
                end,
            },
            raw_toggle,
            gps_toggle,
            pre_toggle,
        },
    }
    return gui_frame
end

return m
