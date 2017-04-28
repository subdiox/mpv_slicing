local msg = require "mp.msg"
local utils = require "mp.utils"
local options = require "mp.options"

local running = false
local cut_pos = nil
local copy_audio = true

string.split_it = function(str, sep)
        if str == nil then return nil end
        assert(type(str) == "string", "str must be a string")
        assert(type(sep) == "string", "sep must be a string")
        return string.gmatch(str, "[^\\" .. sep .. "]+")
end

string.split = function(str, sep)
        local ret = {}
        for seg in string.split_it(str, sep) do
                ret[#ret+1] = seg
        end
        return ret
end

table.join = function(tbl, sep)
        local ret
        for n, v in pairs(tbl) do
                local seg = tostring(v)
                if ret == nil then
                        ret = seg
                else
                        ret = ret .. sep .. seg
                end
        end
        return ret
end

local o = {
    target_dir = mp.get_property("path"),
    vcodec = "copy",
    acodec = "copy",
    prevf = "",
    vf = "",
    hqvf = "",
    postvf = "",
    opts = "",
    ext = "mp4",
    command_template = [[
        ffmpeg -y -stats
        -ss $shift -i "$in" -t $duration
        -c:v $vcodec -c:a $acodec $audio
        $opts "$out.$ext"
    ]],
}
options.read_options(o)

function timestamp(duration)
    local hours = duration / 3600
    local minutes = duration % 3600 / 60
    local seconds = duration % 60
    return string.format("%02d:%02d:%02.03f", hours, minutes, seconds)
end

function short_timestamp(duration)
    local hours = duration / 3600
    local minutes = duration % 3600 / 60
    local seconds = duration % 60
    return string.format("%02d%02d%02d", hours, minutes, seconds)
end


function osd(str)
    return mp.osd_message(str, 3)
end

function escape(str)
    return str:gsub("\\", "\\\\"):gsub("'", "'\\''")
end

function trim(str)
    return str:gsub("^%s+", ""):gsub("%s+$", "")
end

function get_csp()
    local csp = mp.get_property("colormatrix")
    if csp == "bt.601" then return "bt601"
        elseif csp == "bt.709" then return "bt709"
        elseif csp == "smpte-240m" then return "smpte240m"
        else
            local err = "Unknown colorspace: " .. csp
            osd(err)
            error(err)
    end
end

function get_outname(shift, endpos)
    local name = mp.get_property("filename")
    local dotidx = name:reverse():find(".", 1, true)
    if dotidx then name = name:sub(1, -dotidx-1) end
    --name = name:gsub(" ", "\\ ")
    name = name .. string.format(".%s-%s", short_timestamp(shift), short_timestamp(endpos))
    return name
end

function cut(shift, endpos)
    local path = escape(utils.join_path(utils.getcwd(), mp.get_property("stream-path")))
    local separator = package.config:sub(1,1)
    local path_array = path:split(separator)
    table.remove(path_array, table.maxn(path_array))
    local dir_path = table.join(path_array, separator)

    local cmd = trim(o.command_template:gsub("%s+", " "))
    local inpath = path
    if separator == "\\" then
        local inpath_array = path:split(separator)
        inpath = table.join(inpath_array, separator)
        inpath = escape(string.format("%s%s", separator, inpath))
    end

    local outpath = escape(string.format("%s%s%s%s", separator, dir_path, separator, get_outname(shift, endpos)))
    cmd = cmd:gsub("$shift", shift)
    cmd = cmd:gsub("$duration", endpos - shift)
    cmd = cmd:gsub("$vcodec", o.vcodec)
    cmd = cmd:gsub("$acodec", o.acodec)
    cmd = cmd:gsub("$audio", copy_audio and "" or "-an")
    cmd = cmd:gsub("$prevf", o.prevf)
    cmd = cmd:gsub("$vf", o.vf)
    cmd = cmd:gsub("$hqvf", o.hqvf)
    cmd = cmd:gsub("$postvf", o.postvf)
    cmd = cmd:gsub("$matrix", get_csp())
    cmd = cmd:gsub("$opts", o.opts)
    cmd = cmd:gsub("$ext", o.ext)
    cmd = cmd:gsub("$out", outpath)
    cmd = cmd:gsub("$in", inpath, 1)

    msg.info(cmd)
    running = true
    io.popen(cmd)
end

function toggle_mark()
    local pos = mp.get_property_number("time-pos")
    if cut_pos then
        local shift, endpos = cut_pos, pos
        if shift > endpos then
            shift, endpos = endpos, shift
        end
        if shift == endpos then
            osd("Cut fragment is empty")
        else
            cut_pos = nil
            osd(string.format("Cut fragment: %s - %s", timestamp(shift), timestamp(endpos)))
            cut(shift, endpos)
        end
    else
        running = false
        cut_pos = pos
        osd(string.format("Marked %s as start position", timestamp(pos)))
    end
end

function toggle_audio()
    copy_audio = not copy_audio
    osd("Audio capturing is " .. (copy_audio and "enabled" or "disabled"))
end

function toggle_revert()
    if cut_pos then
        osd(string.format("Reverted start position of %s", timestamp(cut_pos)))
        cut_pos = nil
    else
        osd("Cannot revert")
    end
end

mp.add_key_binding("c", "slicing_mark", toggle_mark)
mp.add_key_binding("a", "slicing_audio", toggle_audio)
mp.add_key_binding("b", "slicing_revert", toggle_revert)
