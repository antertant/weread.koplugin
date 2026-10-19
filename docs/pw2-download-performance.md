# PW2 download performance and low-memory fixes

These changes were developed against the v1.6.0 plugin on a Kindle
Paperwhite 2 (256 MB RAM, firmware 5.12.2.2) and KOReader 2026.07.1, then
ported onto current upstream main. The device owner reported that the final
revision completed the previously failing whole-book download.

## What changes

- Single-chapter foreground downloads and chapter prefetch no longer request
  an initial reader page that source fetching immediately requests again.
- Binary-self-tested native MIME decoding replaces the slow pure-Lua path
  where available. Native Base64 runs in bounded, quartet-aligned 64 KiB calls
  for well-framed large inputs. Failure discards partial output before fallback.
- Sparse character swaps avoid an array element per encoded byte. Fallback
  Base64 avoids expanding the complete input to binary digits. Large temporary
  input references are released before the next allocation-heavy phase.
- Original-source indexes use contiguous text slices while retaining exactly
  the same UTF-8 rune offsets, suppression rules and quote behavior.
- Multi-document XHTML checkpoint assembly uses a cursor instead of repeatedly
  copying the unprocessed suffix. No chapter text, images or annotations are
  deliberately skipped by these optimizations.
- An unexpectedly exited full-book worker pauses with checkpoints intact,
  rather than immediately repeating a potentially OOM-producing allocation.
  Ordinary HTTP failures keep the existing retry policy. The pause message
  does not claim every unexpected exit is OOM or that the book is complete.

The device investigation confirmed an OOM-killed large-chapter worker and
subsequent system-level page/file-I/O blocking. Later traces localized additional
peaks to checkpoint rendering and Base64 for another large chapter. An earlier
power-management log storm was a separate observation, not a proven cause of
every failure. Device logs, account data, book content and caches are deliberately
not included in this repository.

## Optional HTTPS connection reuse

Connection reuse is **off by default**. Create an empty file named
`weread-pw2-keepalive.enabled` in KOReader's `settings` directory and restart
KOReader to enable it. Remove the marker and restart to disable it.

Only exact read-only chapter-fragment POST endpoints on `weread.qq.com` are
eligible. Connections stay within one process, expire after 15 seconds idle,
and are discarded after fork, errors, server-close responses or unsafe framing.
A failed reused request gets one fresh-connection fallback only before any
body bytes arrive. Login, progress writes, proxies and other endpoints bypass
the pool. Existing LuaSocket/LuaSec TLS handling remains in place.

Five sequential single-chapter device tests averaged about 15.81 seconds before
and 9.11 seconds after the initial session/native/reuse changes. This small
adjacent comparison is not a controlled guarantee for other books or networks.

## Optional local diagnostics

Both diagnostic features are **off by default**. Create the corresponding empty
marker in KOReader's `settings` directory and restart KOReader:

| Marker | Output |
| --- | --- |
| `weread-pw2-profile.enabled` | `settings/weread-pw2-profile.tsv` |
| `weread-pw2-freeze.enabled` | `settings/pw2-freeze/run-*/events.tsv` and `system.log` |

Timing records contain fixed categories, process IDs, times, status codes and
numeric byte counts. They do not include raw URLs, cookies, request/response
bodies, error bodies or book titles. Detailed timing records append until
disabled; remove the marker and restart after a measurement session.

The freeze observer is Linux/Kindle-oriented and requires `/proc` and a POSIX
shell. It samples CPU, memory, reclaim counters, process state, wait channels
and descriptor counts approximately every five seconds. It exits after the
foreground job stops, the owning process exits or its PID is reused, or after
720 samples/one hour (checked between samples). It does not change powerd,
swap, system services or network settings and never kills a download process.
It has nonzero overhead and a forced reboot can lose final filesystem writes.
Remove its marker and restart to disable future collection; do not publish
raw device reports without reviewing them for sensitive system information.

## Validation and limitations

Run the normal standalone Lua suite with `bash scripts/run_lua_specs.sh`.
The `spec/pw2_*_spec.lua` tests add synthetic regressions for swaps, Base64,
original offsets, malformed/multi-document HTML, HTTP pooling safety, worker
pause behavior and optional diagnostics. Tests never require real WeRead
credentials, a connected Kindle, downloaded books or paths on the author's PC.

Desktop LuaJIT synthetic tests measured substantially smaller temporary heap
peaks for multi-megabyte swaps/indexing and multi-document checkpoint assembly.
These are not Kindle process-RSS measurements. The real-device result predates
the port to newer upstream main; automated checks cannot replace an on-device
smoke test of the newly ported revision or the project's full KOReader/UI
integration matrix. No release version or update URL is changed by this branch.
