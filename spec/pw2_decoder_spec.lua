package.path = "./?.lua;" .. package.path
local calls = 0
package.preload.mime = function()
    return { unb64 = function(value)
        calls = calls + 1
        if value == "AAEC/w==" then return string.char(0, 1, 2, 255) end
        if value == "Zm9v" then return "foo" end
        error("synthetic native failure")
    end }
end
local Content = require("weread.lib.content")
local function upvalue(fn, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing upvalue: " .. wanted)
end
local decode = upvalue(Content.decode_content_shards, "decode_encoded_body")
local base64 = upvalue(decode, "base64_decode")
assert(base64("Zm9v") == "foo" and calls == 2, "native decoder was not used")
assert(base64("aGVsbG8=") == "hello", "native error did not use Lua fallback")
print("pw2_decoder_spec: native MIME self-test, native decoding and fallback passed")
