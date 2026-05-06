#!/bin/bash
# Session cleanup: orphaned process detection and removal

set -euo pipefail

MONITOR_LOG="${MONITOR_LOG:-/var/log/xrdp/session-monitor.log}"

cleanup_orphaned_sessions() {
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local cleaned=0

    {
        echo "[$timestamp] === Session Cleanup ==="

        local active_xvnc_pids; active_xvnc_pids=$(pgrep -f "Xvnc" 2>/dev/null || true)

        for chansrv_pid in $(pgrep -f "xrdp-chansrv" 2>/dev/null || true); do
            local has_parent=false
            for xvnc_pid in $active_xvnc_pids; do
                if ps -o cgroup= -p "$chansrv_pid" 2>/dev/null | grep -q "$(ps -o cgroup= -p "$xvnc_pid" 2>/dev/null | head -1)"; then
                    has_parent=true
                    break
                fi
            done
            if [ "$has_parent" = false ]; then
                local chansrv_time; chansrv_time=$(ps -o lstart= -p "$chansrv_pid" 2>/dev/null || echo "")
                if [ -n "$chansrv_time" ]; then
                    echo "  Killing orphaned xrdp-chansrv PID $chansrv_pid (started $chansrv_time)"
                    kill "$chansrv_pid" 2>/dev/null || true
                    cleaned=$((cleaned + 1))
                fi
            fi
        done

        for pw_pid in $(pgrep -f "pw-cli.*xrdp" 2>/dev/null || true); do
            local has_parent=false
            for xvnc_pid in $active_xvnc_pids; do
                if ps -o cgroup= -p "$pw_pid" 2>/dev/null | grep -q "$(ps -o cgroup= -p "$xvnc_pid" 2>/dev/null | head -1)"; then
                    has_parent=true
                    break
                fi
            done
            if [ "$has_parent" = false ]; then
                local pw_time; pw_time=$(ps -o lstart= -p "$pw_pid" 2>/dev/null || echo "")
                if [ -n "$pw_time" ]; then
                    echo "  Killing orphaned pw-cli PID $pw_pid (started $pw_time)"
                    kill "$pw_pid" 2>/dev/null || true
                    cleaned=$((cleaned + 1))
                fi
            fi
        done

        for gs_pid in $(pgrep -f "gnome-shell" 2>/dev/null || true); do
            local gs_display; gs_display=$(ps -o args= -p "$gs_pid" 2>/dev/null | grep -oE 'DISPLAY=:[0-9]+' || echo "")
            if [ -n "$gs_display" ]; then
                local display_num; display_num=$(echo "$gs_display" | grep -oE '[0-9]+')
                if ! pgrep -f "Xvnc.*:$display_num" > /dev/null 2>&1; then
                    echo "  Killing orphaned gnome-shell PID $gs_pid (display :$display_num)"
                    kill "$gs_pid" 2>/dev/null || true
                    cleaned=$((cleaned + 1))
                fi
            fi
        done

        if [ "$cleaned" -gt 0 ]; then
            echo "  Cleaned $cleaned orphaned processes"
        else
            echo "  No orphaned sessions found"
        fi

    } >> "$MONITOR_LOG" 2>&1
}

periodic_sweep() {
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local swept=0

    for xvnc_pid in $(pgrep -f "Xvnc" 2>/dev/null || true); do
        local session_age_seconds; session_age_seconds=$(ps -o etime= -p "$xvnc_pid" 2>/dev/null \
            | awk '{print $1}' | tr '-' ':' \
            | awk -F: '{if (NF==1) print $1*60; else print $1*1440+$2*60+$3}')
        if [ -n "$session_age_seconds" ] && [ "$session_age_seconds" -gt 1440 ]; then
            if ! ps -p "$xvnc_pid" > /dev/null 2>&1; then
                echo "[$timestamp] Removing stale Xvnc PID $xvnc_pid (age: ${session_age_seconds}m)"
                kill "$xvnc_pid" 2>/dev/null || true
                swept=$((swept + 1))
            fi
        fi
    done

    [ "$swept" -gt 0 ] && echo "[$timestamp] Swept $swept stale sessions"
}

export -f cleanup_orphaned_sessions periodic_sweep
