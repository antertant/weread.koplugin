-- Opt-in, local-only diagnostics. No credentials, titles, URLs or error bodies.
-- Loading ordinary downloads must not require diagnostic-only services.
-- Marker changes take effect after restarting KOReader.
local noop = function() end
local disabled = { start = noop, stop = noop, event = noop }
local ok_storage, DataStorage = pcall(require, "datastorage")
if not ok_storage or type(DataStorage.getSettingsDir) ~= "function" then return disabled end
local ok_directory, directory = pcall(DataStorage.getSettingsDir, DataStorage)
if not ok_directory or type(directory) ~= "string" then return disabled end
local enabled_marker = io.open(directory .. "/weread-pw2-freeze.enabled", "rb")
if not enabled_marker then return disabled end
enabled_marker:close()
local socket = require("socket")
local lfs = require("libs/libkoreader-lfs")
local Trace = {}
local active
local sequence = 0
local module_path = debug.getinfo(1, "S").source:sub(2)
local script_path = module_path:gsub("pw2_freeze%.lua$", "pw2_freeze_monitor.sh")
local labels = { worker=true, connect=true, source=true, finalize=true,
    reader_page=true, catalog=true, gateway=true, other=true,
    e_0=true, e_1=true, e_2=true, e_3=true, t_0=true, t_1=true, t_2=true, t_3=true,
    reverse_swaps=true, base64=true, source_index=true, source_store=true,
    checkpoint_render=true, checkpoint_write=true }
local events = { job_start=true, job_end=true, worker_begin=true,
    child_begin=true, child_end=true, worker_return=true, http_begin=true, http_end=true,
    processing_begin=true, processing_end=true }
local function pid()
    local ok, value = pcall(function() return require("ffi").C.getpid() end)
    return ok and tonumber(value) or 0
end
local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end
local function append(event, label, chapter, number)
    if not active or not events[event] then return end
    local file = io.open(active.dir .. "/events.tsv", "ab")
    if not file then return end
    file:write(string.format("PW2F1\t%.6f\t%d\t%s\t%s\t%d\t%d\n",
        socket.gettime(), pid(), event, labels[label] and label or "other",
        tonumber(chapter) or 0, tonumber(number) or 0))
    file:close()
end
function Trace.event(event, label, chapter, number)
    -- Diagnostics must not interrupt the functional operation, even on full disk.
    pcall(append, event, label, chapter, number)
end
function Trace.start(dl)
    pcall(function()
        if active then return end
        local marker = io.open(DataStorage:getSettingsDir() .. "/weread-pw2-freeze.enabled", "rb")
        if not marker then return end
        marker:close()
        local owner = pid()
        if owner <= 0 then return end
        local root = DataStorage:getSettingsDir() .. "/pw2-freeze"
        if not lfs.attributes(root, "mode") then assert(lfs.mkdir(root)) end
        sequence = sequence + 1
        local dir = string.format("%s/run-%.0f-%d-%d", root, socket.gettime()*1000000, owner, sequence)
        assert(lfs.mkdir(dir))
        dl._pw2_trace_dir = dir
        active = { dir=dir, owner=owner }
        Trace.event("job_start", "worker", 0, dl.total)
        os.execute("sh " .. quote(script_path) .. " " .. quote(dir) .. " " .. tostring(owner)
            .. " </dev/null >/dev/null 2>&1 &")
    end)
end
function Trace.stop(dl)
    pcall(function()
        if not active or active.dir ~= dl._pw2_trace_dir or active.owner ~= pid() then return end
        Trace.event("job_end", "worker", dl.index, dl.cancelled and 1 or 0)
        local file = io.open(active.dir .. "/stop", "wb")
        if file then file:write("stop\n"); file:close() end
        active = nil
    end)
end
return Trace
