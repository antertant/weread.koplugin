-- Local, opt-in timing only. Never record URLs, bodies, headers or credentials.
local ok_socket, socket = pcall(require, "socket")
local ok_storage, DataStorage = pcall(require, "datastorage")
local Profile = {}
local directory
if ok_storage and type(DataStorage.getSettingsDir) == "function" then
    local ok, value = pcall(DataStorage.getSettingsDir, DataStorage)
    if ok and type(value) == "string" then directory = value end
end
local marker = directory and io.open(directory .. "/weread-pw2-profile.enabled", "rb")
Profile.enabled = marker ~= nil and ok_socket and type(socket.gettime) == "function"
if marker then marker:close() end
local sequence = 0
local unpack_values = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end
local function pid()
    local ok, result = pcall(function() return require("ffi").C.getpid() end)
    return ok and tonumber(result) or 0
end
function Profile.start(parent)
    if not Profile.enabled then return nil end
    sequence = sequence + 1
    local wall = socket.gettime()
    return { wall = wall, cpu = os.clock(), id = parent and parent.id
        or string.format("%d-%.0f-%d", pid(), wall * 1000000, sequence) }
end
function Profile.finish(stage, span, metrics)
    if not span then return end
    local wall, cpu = socket.gettime(), os.clock()
    -- Diagnostics must never fail a functional operation, including a full disk.
    pcall(function()
        local row = { "PW2P1", string.format("%.6f", wall), tostring(pid()), span.id,
            stage, string.format("%.3f", (wall - span.wall) * 1000),
            string.format("%.3f", (cpu - span.cpu) * 1000) }
        local names = {}
        for name in pairs(metrics or {}) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local value = metrics[name]
            if type(value) == "number" then
                row[#row + 1] = name .. "=" .. string.format("%.3f", value)
            elseif name == "kind" and type(value) == "string"
                and value:match("^[a-z_0-9]+$") then
                row[#row + 1] = "kind=" .. value
            end
        end
        local out = io.open(directory .. "/weread-pw2-profile.tsv", "ab")
        if out then out:write(table.concat(row, "\t"), "\n"); out:close() end
    end)
end
function Profile.kind(url)
    -- Classify only against fixed labels. Never log arbitrary paths or query strings.
    local path = tostring(url or ""):match("^https?://[^/]+(/[^?#]*)") or ""
    if path:match("^/web/reader/") then return "reader_page" end
    local shard = path:match("^/web/book/chapter/([et]_[0-3])$")
    if shard then return shard end
    if path == "/web/book/chapterInfos" then return "catalog" end
    if path == "/api/agent/gateway" then return "gateway" end
    return "other"
end
function Profile.http_request(http, opts)
    if not Profile.enabled then return { pcall(http.request, opts) } end
    local span = Profile.start()
    local kind = Profile.kind(opts.url)
    local saved_open, saved_sink = http.open, opts.sink
    local bytes, first_byte_ms = 0, -1
    opts.sink = function(chunk, err)
        if type(chunk) == "string" and #chunk > 0 then
            if first_byte_ms < 0 then first_byte_ms = (socket.gettime() - span.wall) * 1000 end
            bytes = bytes + #chunk
        end
        return saved_sink(chunk, err)
    end
    if type(saved_open) == "function" then
        http.open = function(...)
            local opening = Profile.start(span)
            local result = pack(pcall(saved_open, ...))
            Profile.finish("connect_tls", opening, { kind = kind, ok = result[1] and 1 or 0 })
            if not result[1] then error(result[2], 0) end
            return unpack_values(result, 2, result.n)
        end
    end
    local result = { pcall(http.request, opts) }
    http.open, opts.sink = saved_open, saved_sink
    Profile.finish("http_transport", span, { kind = kind, bytes = bytes,
        first_byte_ms = first_byte_ms, status = tonumber(result[3]) or 0,
        ok = result[1] and 1 or 0 })
    return result
end
return Profile
