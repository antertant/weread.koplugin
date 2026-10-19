-- Reuse only read-only chapter-fragment HTTPS connections, within one process.
-- Retains LuaSocket/LuaSec's own HTTP framing, TLS configuration and error paths.
local Profile = require("weread.lib.pw2_profile")
local ok_socket, socket = pcall(require, "socket")
local ok_storage, DataStorage = pcall(require, "datastorage")
local directory
if ok_storage and type(DataStorage.getSettingsDir) == "function" then
    local ok, value = pcall(DataStorage.getSettingsDir, DataStorage)
    if ok and type(value) == "string" then directory = value end
end
local marker = directory and io.open(directory .. "/weread-pw2-keepalive.enabled", "rb")
local enabled = marker ~= nil and ok_socket and type(socket.gettime) == "function"
if marker then marker:close() end
local Transport = {}
local pooled
local function current_pid()
    local ok, value = pcall(function() return require("ffi").C.getpid() end)
    return ok and tonumber(value) or 0
end
local function discard()
    local old = pooled
    pooled = nil
    if old then
        old.handle.close = old.close
        pcall(old.close, old.handle)
    end
end
local function header(headers, wanted)
    for key, value in pairs(headers or {}) do
        if tostring(key):lower() == wanted and type(value) == "string" then return value end
    end
end
local function eligible(opts)
    return enabled and not opts.proxy and opts.method == "POST"
        and type(opts.url) == "string"
        and opts.url:match("^https://weread%.qq%.com/web/book/chapter/[et]_[0-3]$") ~= nil
        and type(opts.sink) == "function"
end
function Transport.request(http, opts)
    if not eligible(opts) or type(http.open) ~= "function" then
        return Profile.http_request(http, opts)
    end
    local process = current_pid()
    if pooled and (pooled.pid ~= process or socket.gettime() - pooled.last > 15) then discard() end
    local saved_open, saved_headers, saved_sink = http.open, opts.headers, opts.sink
    local request_headers = {}
    for key, value in pairs(saved_headers or {}) do
        if tostring(key):lower() ~= "connection" then request_headers[key] = value end
    end
    request_headers.connection = "keep-alive"
    opts.headers = request_headers
    local body_bytes, reused = 0, false
    opts.sink = function(chunk, err)
        if type(chunk) == "string" then body_bytes = body_bytes + #chunk end
        return saved_sink(chunk, err)
    end
    http.open = function(host, port, create)
        -- Exact endpoint allowlist above must agree with the actual socket target.
        if host ~= "weread.qq.com" or tonumber(port) ~= 443 then
            return saved_open(host, port, create)
        end
        if pooled then
            reused = true
            return pooled.handle
        end
        local handle = saved_open(host, port, create)
        pooled = { handle = handle, close = handle.close, pid = process, last = socket.gettime() }
        -- LuaSocket closes at the end of every successful request. Delay that
        -- close until the result headers establish whether reuse is safe.
        handle.close = function() return 1 end
        return handle
    end
    local span = Profile.start()
    local ok, results = pcall(Profile.http_request, http, opts)
    http.open, opts.headers, opts.sink = saved_open, saved_headers, saved_sink
    local code = ok and tonumber(results[3]) or nil
    local headers = ok and results[4] or nil
    local connection = (header(headers, "connection") or ""):lower()
    local length = tonumber(header(headers, "content-length") or "")
    local chunked = (header(headers, "transfer-encoding") or ""):lower():find("chunked", 1, true)
    local reusable = ok and results[1] and code == 200
        and not connection:find("close", 1, true) and (length ~= nil or chunked)
    if reusable and pooled then
        pooled.last = socket.gettime()
    else
        discard()
    end
    Profile.finish("keepalive_request", span, { reused = reused and 1 or 0,
        retained = reusable and 1 or 0, bytes = body_bytes, status = code or 0 })
    if not ok then error(results, 0) end
    -- A server can close an idle socket silently. Retry once with the original
    -- transport only if this read-only request received no response body.
    -- Partial bodies are never appended to a new response by this retry.
    if reused and not code and body_bytes == 0 then
        discard()
        local retry = Profile.start()
        local fresh = Profile.http_request(http, opts)
        Profile.finish("keepalive_fallback", retry, { status = tonumber(fresh[3]) or 0 })
        return fresh
    end
    return results
end
return Transport
