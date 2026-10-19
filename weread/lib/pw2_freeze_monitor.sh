#!/bin/sh
# Independent, read-only observer: every 5s for <=1h. No system services changed.
# Arguments are a private run directory and the owning KOReader PID.
umask 077
trace_dir=$1
trace_owner=$2
case "$trace_owner" in ''|*[!0-9]*) exit 2 ;; esac
[ -d "$trace_dir" ] && [ -r "/proc/$trace_owner/stat" ] || exit 3
owner_start=$(awk '{print $22}' "/proc/$trace_owner/stat")
exec >> "$trace_dir/system.log" 2>&1
printf 'PW2FS1 observer=%s owner=%s start=%s\n' "$$" "$trace_owner" "$owner_start"
printf 'CLK_TCK='
getconf CLK_TCK 2>/dev/null || echo unknown
trace_count=0
read -r observer_started observer_idle < /proc/uptime
observer_started=${observer_started%%.*}
while [ "$trace_count" -lt 720 ]; do
    [ ! -e "$trace_dir/stop" ] && [ -r "/proc/$trace_owner/stat" ] || break
    current_start=$(awk '{print $22}' "/proc/$trace_owner/stat" 2>/dev/null)
    [ "$current_start" = "$owner_start" ] || break
    read -r observer_now observer_idle < /proc/uptime
    observer_now=${observer_now%%.*}
    [ "$((observer_now - observer_started))" -lt 3600 ] || break
    trace_count=$((trace_count + 1))
    printf 'SAMPLE %s epoch=' "$trace_count"
    date +%s
    printf 'UPTIME '; read -r trace_uptime < /proc/uptime; echo "$trace_uptime"
    printf 'LOAD '; read -r trace_load < /proc/loadavg; echo "$trace_load"
    awk '/^cpu / || /^ctxt / || /^processes / || /^procs_running / || /^procs_blocked / {print "CPU " $0}' /proc/stat
    awk '/^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapCached|AnonPages|Shmem|Slab|SReclaimable|SUnreclaim|Dirty|Writeback|PageTables|SwapTotal|SwapFree):/ {print "MEM " $0}' /proc/meminfo
    awk '/^(pgpgin|pgpgout|pswpin|pswpout|pgfault|pgmajfault|allocstall|oom_kill|pgscan.*|pgsteal.*|compact_stall) / {print "VM " $0}' /proc/vmstat
    printf 'FILE_NR '; read -r trace_files < /proc/sys/fs/file-nr; echo "$trace_files"
    printf 'SYSLOG_BYTES '; stat -c %s /var/log/messages 2>/dev/null
    for trace_proc in /proc/[0-9]*; do
        [ -r "$trace_proc/comm" ] || continue
        read -r trace_name < "$trace_proc/comm" || continue
        case "$trace_name" in
            reader.lua|luajit|powerd|syslog-ng|cvm)
                printf 'PROCESS pid=%s name=%s\n' "${trace_proc##*/}" "$trace_name"
                # comm/stat/status are kernel metadata, never command arguments.
                [ ! -r "$trace_proc/stat" ] || { printf 'PSTAT '; read -r trace_stat < "$trace_proc/stat"; echo "$trace_stat"; }
                awk '/^(State|PPid|VmPeak|VmSize|VmHWM|VmRSS|VmSwap|Threads):/ {print "P " $0}' "$trace_proc/status" 2>/dev/null
                printf 'WCHAN '; read -r trace_wchan < "$trace_proc/wchan"; echo "$trace_wchan"
                printf 'FD_COUNT '; ls -1 "$trace_proc/fd" 2>/dev/null | wc -l
                ;;
        esac
    done
    echo END_SAMPLE
    # Shell/awk writes are unbuffered or closed each sample; no global sync.
    sleep 5
done
echo OBSERVER_END
