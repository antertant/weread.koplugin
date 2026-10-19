-- Preserve original HTML rune offsets without preserving tags, images or CSS.
-- WeRead heat-map ranges address the source HTML, not the rendered EPUB text.
local Source = {}
local function length(byte)
    if byte < 128 then return 1 elseif byte < 224 then return 2
    elseif byte < 240 then return 3 else return 4 end
end

function Source.plain(text)
    text = text:gsub("^\239\187\191", "")
    local i, count = 1, 0
    while i <= #text do i, count = i + length(text:byte(i)), count + 1 end
    return { { 0, count, text, true } }
end

function Source.index(html)
    html = html:gsub("^\239\187\191", "")
    local spans, offset, i, start, start_byte = {}, 0, 1, nil, nil
    local in_tag, quote, suppressed = false, nil, nil
    local tag_start
    local function flush()
        if start then spans[#spans + 1] = { start, offset, html:sub(start_byte, i - 1) } end
        start, start_byte = nil, nil
    end
    while i <= #html do
        local size = length(html:byte(i))
        -- ASCII syntax bytes can be tested without allocating a string for
        -- every rune. Text remains a contiguous slice with identical offsets.
        local byte = html:byte(i)
        if in_tag then
            if quote then
                if byte == quote then quote = nil end
            elseif byte == 34 or byte == 39 then quote = byte
            elseif byte == 62 then
                in_tag = false
                -- These anchored tag-name patterns need at most eight bytes,
                -- not a copy of possibly enormous attribute values.
                local name = html:sub(tag_start, math.min(i, tag_start + 7)):lower()
                if name:match("^/?script[%s>]") or name:match("^/?style[%s>]") then
                    suppressed = name:sub(1, 1) ~= "/" or nil
                end
            end
        elseif byte == 60 then
            flush()
            in_tag, tag_start = true, i + 1
        elseif not suppressed then
            if not start then start, start_byte = offset, i end
        end
        i, offset = i + size, offset + 1
    end
    flush()
    return spans
end

function Source.quote(spans, range)
    local first, last = tostring(range):match("^(%d+)%-(%d+)$")
    first, last = tonumber(first), tonumber(last)
    if not first or not last or first >= last then return "" end
    local pieces = {}
    for _, span in ipairs(spans or {}) do
        if span[1] < last and span[2] > first then
            local offset, i, start_byte = span[1], 1, nil
            while i <= #span[3] and offset < last do
                if offset >= first and not start_byte then start_byte = i end
                i, offset = i + length(span[3]:byte(i)), offset + 1
            end
            if start_byte then
                local text = span[3]:sub(start_byte, i - 1)
                -- A cut entity cannot be interpreted safely.
                if span[4] then
                    pieces[#pieces + 1] = text
                else
                    if text:match("&[^;]*$")
                        or span[3]:sub(1, start_byte - 1):match("&[^;]*$") then return "" end
                    pieces[#pieces + 1] = require("util").htmlEntitiesToUtf8(text)
                end
            end
        end
    end
    return table.concat(pieces)
end
return Source
