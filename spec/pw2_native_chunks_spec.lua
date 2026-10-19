package.path = "./?.lua;" .. package.path
local calls, maximum, fail_second, malformed = 0, 0, false, false
package.preload.mime = function()
    return { unb64 = function(input)
        if input == "AAEC/w==" then return string.char(0, 1, 2, 255) end
        calls, maximum = calls + 1, math.max(maximum, #input)
        if malformed then return "legacy malformed result" end
        assert(#input <= 65536 and #input % 4 == 0)
        if fail_second and calls == 2 then error("synthetic decoder failure") end
        local tail = ""
        if input:sub(-4) == "QQ==" then input, tail = input:sub(1, -5), "A"
        elseif input:sub(-4) == "QUI=" then input, tail = input:sub(1, -5), "AB" end
        assert(input:gsub("QUJD", "") == "")
        return string.rep("ABC", #input / 4) .. tail
    end }
end
local Content = require("weread.lib.content")
local function up(fn, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
end
local base64 = up(up(Content.decode_content_shards, "decode_encoded_body"), "base64_decode")
for _, groups in ipairs({ 16383, 16384, 16385, 32768, 1002449 }) do
    for _, ending in ipairs({ { "", "" }, { "QQ==", "A" }, { "QUI=", "AB" } }) do
        calls, maximum = 0, 0
        local result, native = base64(string.rep("QUJD", groups) .. ending[1])
        assert(result == string.rep("ABC", groups) .. ending[2] and native == 1)
        assert(maximum <= 65536)
    end
end
calls, maximum, fail_second = 0, 0, true
assert(base64(string.rep("QUJD", 32768)) == string.rep("ABC", 32768), "partial native output leaked into fallback")
assert(calls == 2)
calls, malformed = 0, true
local internal_padding = string.rep("QUJD", 17000) .. "=QUJD"
assert(base64(internal_padding) == "legacy malformed result" and calls == 1)
print("pw2_native_chunks_spec: quartet boundaries, padding, bounded native buffers and safe full fallback passed")
