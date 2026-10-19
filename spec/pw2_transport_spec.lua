package.path = "./?.lua;" .. package.path
local saved_open = io.open
io.open = function(path, ...)
    if path == "synthetic/weread-pw2-keepalive.enabled" then return { close = function() end } end
    if path == "synthetic/weread-pw2-profile.enabled" then return nil end
    return saved_open(path, ...)
end
package.preload.datastorage = function() return { getSettingsDir = function() return "synthetic" end } end
package.preload.socket = function() return { gettime = function() return 100 end } end
local pid = 101
package.loaded.ffi = { C = { getpid = function() return pid end } }
local Transport = require("weread.lib.pw2_transport")
io.open = saved_open
local opens, closes, requests = 0, 0, 0
local behavior = "ok"
local http = {}
local original_open = function()
    opens = opens + 1
    return { close = function(self) self.closed = true; closes = closes + 1 end }
end
http.open = original_open
http.request = function(opts)
    requests = requests + 1
    local handle = http.open("weread.qq.com", 443)
    assert(not handle.closed)
    if behavior == "stale" then behavior = "ok"; handle:close(); return nil, "closed" end
    if behavior == "partial" then opts.sink("part"); handle:close(); return nil, "closed" end
    if behavior == "throw" then error("synthetic transport error") end
    opts.sink("abc"); opts.sink(nil); handle:close()
    local headers = { ["content-length"] = "3" }
    if behavior == "server_close" then headers.connection = "close" end
    if behavior == "unframed" then headers = {} end
    if behavior == "chunked" then headers = { ["transfer-encoding"] = "chunked" } end
    return 1, 200, headers, "HTTP/1.1 200 OK"
end
local received = ""
local sink = function(chunk) if chunk then received = received .. chunk end; return 1 end
local headers = { Cookie = "SYNTHETIC" }
local opts = { url = "https://weread.qq.com/web/book/chapter/e_0", method = "POST", headers = headers, sink = sink }
local function call()
    local result = Transport.request(http, opts)
    assert(http.open == original_open and opts.sink == sink and opts.headers == headers)
    return result
end
assert(call()[3] == 200 and opens == 1 and closes == 0)
assert(call()[3] == 200 and opens == 1)
behavior = "stale"; received = ""
assert(call()[3] == 200 and opens == 2 and received == "abc")
assert(call()[3] == 200 and opens == 3)
behavior = "partial"; received = ""
local before = requests
assert(call()[3] == "closed" and requests == before + 1 and received == "part")
behavior = "server_close"; assert(call()[3] == 200)
before = opens; assert(call()[3] == 200 and opens == before + 1)
behavior = "unframed"; assert(call()[3] == 200)
before = opens; assert(call()[3] == 200 and opens == before + 1)
behavior = "chunked"; assert(call()[3] == 200)
before = opens; assert(call()[3] == 200 and opens == before)
pid = 102; assert(call()[3] == 200 and opens == before + 1)
behavior = "throw"; assert(call()[1] == false)
behavior = "ok"; opts.url = "https://weread.qq.com/web/book/read"
before = closes; assert(call()[3] == 200 and closes == before + 1)
print("pw2_transport_spec: reuse, safe fallback, framing, fork isolation and endpoint boundaries passed")
