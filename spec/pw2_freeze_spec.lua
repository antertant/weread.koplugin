package.path = "./?.lua;" .. package.path
local opened, output, commands = {}, {}, {}
local pid = 123
local saved_open, saved_execute = io.open, os.execute
rawset(io, "open", function(path, mode)
    opened[#opened + 1] = path
    if path == "synthetic/weread-pw2-freeze.enabled" then return { close = function() end } end
    if mode == "ab" or mode == "wb" then
        return { write = function(_self, ...)
            output[#output + 1] = { path = path, text = table.concat({ ... }) }
        end, close = function() end }
    end
    return nil
end)
rawset(os, "execute", function(command) commands[#commands + 1] = command; return 0 end)
package.preload.datastorage = function() return { getSettingsDir = function() return "synthetic" end } end
package.preload.socket = function() return { gettime = function() return 100 end } end
package.preload["libs/libkoreader-lfs"] = function()
    return { attributes = function() return "directory" end, mkdir = function() return true end }
end
package.loaded.ffi = { C = { getpid = function() return pid end } }
local Trace = require("weread.lib.pw2_freeze")
local dl = { total = 145, index = 132 }
Trace.start(dl); Trace.start(dl)
assert(#commands == 1, "observer launched more than once")
Trace.event("http_begin", "SECRET", 132, 1)
pid = 456; Trace.event("child_begin", "source", 132, 1); Trace.stop(dl)
for _, row in ipairs(output) do assert(not row.path:match("/stop$"), "child stopped parent observer") end
pid = 123; Trace.stop({}); Trace.stop(dl)
local count = #output
Trace.event("http_begin", "other")
assert(#output == count, "events written after stop")
local stopped = false
for _, row in ipairs(output) do
    assert(not row.text:find("SECRET", 1, true))
    if row.path:match("/stop$") then stopped = true end
end
assert(stopped)
rawset(io, "open", function() return nil end)
Trace.start({ total = 1 }); Trace.event("http_begin", "other"); Trace.stop(dl)
rawset(io, "open", saved_open)
rawset(os, "execute", saved_execute)
assert(#opened > 1)
print("pw2_freeze_spec: opt-in observer, PID ownership, privacy and safe diagnostic failure passed")
