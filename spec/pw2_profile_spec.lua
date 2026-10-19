-- Opt-in profiling must be inert without KOReader services or a marker.
package.path = "./?.lua;" .. package.path
package.preload.datastorage = function() return {} end
package.preload.socket = function() return {} end
local Profile = require("weread.lib.pw2_profile")
assert(not Profile.enabled and Profile.start() == nil)
assert(Profile.kind("https://example.invalid/web/reader/PRIVATE?token=PRIVATE") == "reader_page")
assert(Profile.kind("https://example.invalid/web/book/chapter/e_0") == "e_0")
assert(Profile.kind("https://example.invalid/private") == "other")
local request = { secret = "not logged" }
local http = { request = function(opts)
    assert(opts == request)
    return nil, "closed", nil, "last"
end }
local result = Profile.http_request(http, request)
assert(result[1] and result[2] == nil and result[3] == "closed" and result[5] == "last")
http.request = function() error("synthetic failure") end
assert(not Profile.http_request(http, request)[1])
print("pw2_profile_spec: disabled profiling preserves HTTP returns and failures")
