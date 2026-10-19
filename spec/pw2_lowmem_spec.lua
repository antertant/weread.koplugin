-- Synthetic regressions only: never load a downloaded book or real settings.
package.path = "./?.lua;" .. package.path
package.preload.mime = function() error("exercise Lua fallback") end
local Content = require("weread.lib.content")
local Source = require("weread.lib.annotation_source")
local function up(fn, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
end
local decode = up(Content.decode_content_shards, "decode_encoded_body")
local swap = up(decode, "reverse_swaps")
local base64 = up(decode, "base64_decode")
local function legacy_swap(encoded, positions)
    local chars = {}
    for i = 1, #encoded do chars[i] = encoded:sub(i, i) end
    for i = #positions, 1, -2 do
        for k = 1, 0, -1 do
            local left, right = positions[i] + k + 1, positions[i - 1] + k + 1
            chars[left], chars[right] = chars[right], chars[left]
        end
    end
    return table.concat(chars)
end
math.randomseed(132)
for _case = 1, 500 do
    local chars, positions = {}, {}
    for i = 1, math.random(4, 2000) do chars[i] = string.char(math.random(0, 255)) end
    local input = table.concat(chars)
    for i = 1, math.random(0, 5) * 2 do positions[i] = math.random(0, #input - 2) end
    assert(swap(input, positions) == legacy_swap(input, positions), "overlapping sparse swaps changed bytes")
end
assert(base64("aGVsbG8=") == "hello")
assert(base64("AAEC_w==") == string.char(0, 1, 2, 255))
assert(base64("aG Vs\nbG8=") == "hello")
assert(base64("Zm9v") == "foo")
local function legacy_index(input)
    input = input:gsub("^\239\187\191", "")
    local spans, offset, i, start, pieces = {}, 0, 1, nil, {}
    local in_tag, quote, suppressed, tag = false, nil, nil, {}
    local function flush()
        if start then spans[#spans + 1] = { start, offset, table.concat(pieces) } end
        start, pieces = nil, {}
    end
    while i <= #input do
        local byte = input:byte(i)
        local size = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
        local char = input:sub(i, i + size - 1)
        if in_tag then
            tag[#tag + 1] = char
            if quote then
                if char == quote then quote = nil end
            elseif char == '"' or char == "'" then quote = char
            elseif char == ">" then
                in_tag = false
                local name = table.concat(tag):lower()
                if name:match("^/?script[%s>]") or name:match("^/?style[%s>]") then
                    suppressed = name:sub(1, 1) ~= "/" or nil
                end
            end
        elseif char == "<" then flush(); in_tag, tag = true, {}
        elseif not suppressed then start = start or offset; pieces[#pieces + 1] = char end
        i, offset = i + size, offset + 1
    end
    flush()
    return spans
end
local function compare(input)
    local expected, actual = legacy_index(input), Source.index(input)
    assert(#expected == #actual)
    for i, span in ipairs(expected) do
        for j = 1, 3 do assert(span[j] == actual[i][j], "source rune offsets/text changed") end
    end
end
local tokens = { "中", "🙂", "abc", "&amp;", "<p>", "</p>", "<script>", "</script>",
    "<STYLE>", "</STYLE>", '<x a=">">', "'", '"', "<", ">", "\n", "\255\128" }
for _case = 1, 500 do
    local parts = {}
    for i = 1, math.random(1, 80) do parts[i] = tokens[math.random(#tokens)] end
    compare(table.concat(parts))
end
compare("\239\187\191<p>中🙂</p>")
compare("<p>" .. string.rep("A", 1024 * 1024) .. "</p>")
compare('<p title="' .. string.rep("X", 1024 * 1024) .. '">tail</p>')
print("pw2_lowmem_spec: sparse swaps, bounded fallback and source-index equivalence passed")
