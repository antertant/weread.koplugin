package.path = "./?.lua;" .. package.path
for _, name in ipairs({ "ui/widget/confirmbox", "ui/uimanager", "ui/time", "weread.lib.content",
    "weread.ui.download_dialog", "weread.lib.footnotes", "weread.lib.standby_guard",
    "weread.lib.protocol", "weread.lib.worker_settings" }) do
    package.preload[name] = function() return {} end
end
package.preload["weread.lib.i18n"] = function() return { tr = function(s) return s end } end
package.preload["weread.lib.logger"] = function() return { warn = function() end } end
package.preload["ffi/util"] = function() return { template = function(s) return s end } end
local Downloader = require("weread.lib.downloader")
local preserved, notices, scheduled = 0, 0, 0
local downloader = Downloader:new { show_info = function() notices = notices + 1 end }
downloader._preserveWorkspace = function(_self, dl, reason)
    assert(reason == "download_worker_exited" and dl.index == 132 and dl.completed_count == 131)
    preserved = preserved + 1
end
downloader._scheduleGuarded = function() scheduled = scheduled + 1 end
downloader._setStage = function() end
local dl = { resumable = true, index = 132, total = 145, completed_count = 131,
    chapters = { [132] = { chapterUid = 132 } } }
assert(not downloader:_retryChapterSource(dl, "source.lua:1: download worker returned no result"))
assert(preserved == 1 and notices == 1 and scheduled == 0 and dl.index == 132)
assert(downloader:_retryChapterSource(dl, "timeout"))
assert(scheduled == 1 and dl.chapter_source_retries["132"] == 1)
dl.resumable = false
assert(downloader:_retryChapterSource(dl, "download worker returned no result"))
assert(scheduled == 2 and preserved == 1)
print("pw2_worker_guard_spec: preserve full-book checkpoints without immediate abnormal-worker retries")
