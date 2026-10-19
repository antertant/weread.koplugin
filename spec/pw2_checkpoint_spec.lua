package.path = "./?.lua;" .. package.path
local Content = require("weread.lib.content")
local function up(fn, wanted)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
end
local render = up(Content.save_full_download_chapter, "full_download_chapter_xhtml")
local fragment = up(render, "body_fragment")
local function legacy(input)
    local bodies, remaining = {}, input
    while remaining ~= "" do
        local first = remaining:find("<body", 1, true)
        if not first then break end
        local opening = remaining:find(">", first, true)
        if not opening then break end
        local closing = remaining:find("</body>", opening, true)
        if not closing then bodies[#bodies + 1] = remaining:sub(opening + 1); break end
        bodies[#bodies + 1] = remaining:sub(opening + 1, closing - 1)
        remaining = remaining:sub(closing + 7)
    end
    if #bodies > 0 then return table.concat(bodies, "\n") end
    return (input:gsub("<%?xml.-%?>", ""):gsub("<!DOCTYPE.-%>", ""))
end
math.randomseed(176)
local tokens = { "x", "<body>", "</body>", '<body a="x">', "<body", ">", "<BODY>", "<?xml x?>", "<!DOCTYPE x>" }
for _case = 1, 500 do
    local parts = {}
    for i = 1, math.random(1, 80) do parts[i] = tokens[math.random(#tokens)] end
    local input = table.concat(parts)
    assert(fragment(input) == legacy(input), "multi-body/malformed HTML behavior changed")
end
local documents, expected = {}, {}
for i = 1, 176 do
    local body = "<p>" .. tostring(i) .. string.rep("X", 14600) .. "</p>"
    documents[i] = "<html><body>" .. body .. "</body></html>"
    expected[i] = body
end
local input = table.concat(documents)
assert(fragment(input) == table.concat(expected, "\n"))
local result = render({ chapterUid = 132, title = "Synthetic appendix" }, 132, input)
assert(result:find("<!-- weread-chapter-uid: 132 -->", 1, true))
assert(result:find(table.concat(expected, "\n"), 1, true))
print("pw2_checkpoint_spec: cursor assembly preserves malformed and large multi-document XHTML")
