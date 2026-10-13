#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
marks_file="$script_dir/runtime-smoke-marks.txt"

usage() {
    cat <<'EOF'
Usage: runtime-smoke.sh --install-root PATH [options]

Options:
  --install-root PATH  Installed tree containing etc/xdg and usr/lib/qt6/qml
  --runs COUNT         Number of launch and shutdown cycles (default: 3)
  --timeout SECONDS    Per-cycle readiness timeout (default: 30)
  --max-startup-ms N   Fail when a cycle exceeds this startup time
  --max-rss-kb N       Fail when a cycle exceeds this resident memory
  --max-ipc-ms N       Fail when an IPC interaction exceeds this latency
  --max-idle-cpu N     Fail when a cycle idles above this CPU percentage
  --baseline PATH      JSON file with max_startup_ms, max_rss_kb, max_ipc_ms
                       and max_idle_cpu_percent; flags win over the baseline
  --log-dir PATH       Directory for Weston and Quickshell logs

A limit without a value - no flag and no baseline key - skips that check. The
measurement is still reported in the results document.
EOF
}

install_root=
runs=3
timeout_seconds=30
max_startup_ms=
max_rss_kb=
max_ipc_limit_ms=
max_idle_cpu=
baseline=
log_dir=

while (($#)); do
    case "$1" in
        --install-root)
            install_root=${2:?missing value for --install-root}
            shift 2
            ;;
        --runs)
            runs=${2:?missing value for --runs}
            shift 2
            ;;
        --timeout)
            timeout_seconds=${2:?missing value for --timeout}
            shift 2
            ;;
        --max-startup-ms)
            max_startup_ms=${2:?missing value for --max-startup-ms}
            shift 2
            ;;
        --max-rss-kb)
            max_rss_kb=${2:?missing value for --max-rss-kb}
            shift 2
            ;;
        --max-ipc-ms)
            max_ipc_limit_ms=${2:?missing value for --max-ipc-ms}
            shift 2
            ;;
        --max-idle-cpu)
            max_idle_cpu=${2:?missing value for --max-idle-cpu}
            shift 2
            ;;
        --baseline)
            baseline=${2:?missing value for --baseline}
            shift 2
            ;;
        --log-dir)
            log_dir=${2:?missing value for --log-dir}
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$install_root" ]]; then
    echo "--install-root is required" >&2
    usage >&2
    exit 2
fi

if ! [[ "$runs" =~ ^[1-9][0-9]*$ && "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
    echo "--runs and --timeout must be positive integers" >&2
    exit 2
fi
if [[ -n "$max_startup_ms" && ! "$max_startup_ms" =~ ^[1-9][0-9]*$ ]] || \
    [[ -n "$max_rss_kb" && ! "$max_rss_kb" =~ ^[1-9][0-9]*$ ]] || \
    [[ -n "$max_ipc_limit_ms" && ! "$max_ipc_limit_ms" =~ ^[1-9][0-9]*$ ]] || \
    [[ -n "$max_idle_cpu" && ! "$max_idle_cpu" =~ ^[1-9][0-9]*$ ]]; then
    echo "performance limits must be positive integers" >&2
    exit 2
fi
if [[ -n "$baseline" ]]; then
    [[ -f "$baseline" ]] || { echo "baseline not found: $baseline" >&2; exit 2; }
    baseline_value() {
        python3 -c 'import json, sys; data = json.load(open(sys.argv[1], encoding="utf-8")); print(data.get(sys.argv[2], ""))' "$baseline" "$1"
    }
    max_startup_ms=${max_startup_ms:-$(baseline_value max_startup_ms)}
    max_rss_kb=${max_rss_kb:-$(baseline_value max_rss_kb)}
    max_ipc_limit_ms=${max_ipc_limit_ms:-$(baseline_value max_ipc_ms)}
    max_idle_cpu=${max_idle_cpu:-$(baseline_value max_idle_cpu_percent)}
fi

for command_name in dbus-run-session python3 quickshell weston; do
    command -v "$command_name" >/dev/null || {
        echo "required runtime command not found: $command_name" >&2
        exit 2
    }
done

config_path="$install_root/etc/xdg/quickshell/caelestia/shell.qml"
qml_import_path="$install_root/usr/lib/qt6/qml"
[[ -f "$config_path" ]] || { echo "installed shell not found: $config_path" >&2; exit 2; }
[[ -d "$qml_import_path" ]] || { echo "installed QML imports not found: $qml_import_path" >&2; exit 2; }
[[ -f "$marks_file" ]] || { echo "runtime mark declaration not found: $marks_file" >&2; exit 2; }

if [[ -z "$log_dir" ]]; then
    log_dir=$(mktemp -d)
    remove_log_dir=1
else
    mkdir -p "$log_dir"
    remove_log_dir=0
fi

runtime_dir=$(mktemp -d)
chmod 700 "$runtime_dir"
weston_pid=
results_tsv="$runtime_dir/results.tsv"
: >"$results_tsv"
results_emitted=0

# Built here rather than with printf so a log path containing a quote or a
# backslash cannot produce a broken document.
emit_results() {
    if ((results_emitted)); then
        return 0
    fi
    results_emitted=1
    python3 - "$runs" "$log_dir" "$results_tsv" <<'PY'
import json
import sys

runs, log_dir, tsv = sys.argv[1], sys.argv[2], sys.argv[3]
records = []
with open(tsv, encoding="utf-8") as stream:
    for line in stream:
        run, scenario, startup, rss, cpu, ipc = line.rstrip("\n").split("\t")
        records.append({
            "run": int(run),
            "scenario": scenario,
            "startup_ms": int(startup),
            "rss_kb": int(rss),
            "idle_cpu_percent": float(cpu),
            "max_ipc_ms": int(ipc),
        })
print(json.dumps({"runs": int(runs), "results": records, "log_dir": log_dir}, indent=2))
PY
}

cleanup() {
    local status=$?
    emit_results
    if [[ -n "$weston_pid" ]] && kill -0 "$weston_pid" 2>/dev/null; then
        kill "$weston_pid" 2>/dev/null || true
        wait "$weston_pid" 2>/dev/null || true
    fi
    rm -rf "$runtime_dir"
    if ((remove_log_dir)); then
        rm -rf "$log_dir"
    fi
    trap - EXIT INT TERM
    exit "$status"
}

on_signal() {
    exit 130
}

trap cleanup EXIT
trap on_signal INT TERM

export XDG_RUNTIME_DIR="$runtime_dir"
export XDG_CONFIG_HOME="$install_root/etc/xdg"
export XDG_STATE_HOME="$runtime_dir/state"
export QML2_IMPORT_PATH="$qml_import_path"
export QT_QPA_PLATFORM=wayland
export LD_LIBRARY_PATH="$install_root/usr/lib/caelestia${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
mkdir -p "$XDG_STATE_HOME/caelestia"
printf '{invalid scheme state' >"$XDG_STATE_HOME/caelestia/scheme.json"

weston --backend=headless-backend.so --socket=wayland-runtime --idle-time=0 \
    >"$log_dir/weston.log" 2>&1 &
weston_pid=$!

for _ in {1..50}; do
    [[ -S "$runtime_dir/wayland-runtime" ]] && break
    sleep 0.1
done
[[ -S "$runtime_dir/wayland-runtime" ]] || {
    echo "Weston did not create a Wayland socket" >&2
    exit 1
}

now_ms() {
    date +%s%3N
}

# pgrep matches an extended regular expression, so a path cannot be
# interpolated into the pattern as-is.
ere_escape() {
    printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'
}

ipc_call() {
    echo "runtime IPC: $*" >&2
    ipc_start_ms=$(now_ms)
    if ! quickshell ipc --path "$config_path" --newest --any-display call "$@" >/dev/null; then
        echo "runtime IPC failed: $*" >&2
        return 1
    fi
    ipc_elapsed_ms=$(( $(now_ms) - ipc_start_ms ))
    if ((ipc_elapsed_ms > max_ipc_ms)); then
        max_ipc_ms=$ipc_elapsed_ms
    fi
}

ipc_try() {
    ipc_call "$@" 2>/dev/null || true
}

check_run_marks() {
    local log_file="$1" run="$2"
    local minimum marker count created destroyed
    while IFS='|' read -r minimum marker; do
        case "$minimum" in
            ''|'#'*) continue ;;
        esac
        if [[ ! "$minimum" =~ ^[1-9][0-9]*$ || -z "$marker" ]]; then
            echo "malformed runtime mark declaration: ${minimum}|${marker}" >&2
            return 1
        fi
        count=$(grep -Fc -- "$marker" "$log_file" || true)
        if ((count < minimum)); then
            echo "runtime smoke run $run saw ${count} of the ${minimum} required '${marker}'" >&2
            return 1
        fi
    done <"$marks_file"

    # Everything created has to be destroyed again. Only the balance is
    # asserted: the engine may process the final close later than the last IPC
    # reply, so the individual counts are not fixed.
    created=$(grep -Fc -- '[caelestia] nexus=created' "$log_file" || true)
    destroyed=$(grep -Fc -- '[caelestia] nexus=destroyed' "$log_file" || true)
    if ((created < 1 || created != destroyed)); then
        echo "runtime smoke run $run created ${created} nexus window(s) but destroyed ${destroyed}" >&2
        return 1
    fi
    return 0
}
for ((run = 1; run <= runs; run++)); do
    log_file="$log_dir/quickshell-$run.log"
    max_ipc_ms=0
    start_ms=$(now_ms)
    dbus-run-session -- env WAYLAND_DISPLAY=wayland-runtime \
        timeout "$timeout_seconds" quickshell --no-color --log-times \
        --path "$config_path" >"$log_file" 2>&1 &
    quickshell_pid=$!
    ready=0
    while kill -0 "$quickshell_pid" 2>/dev/null; do
        if grep -Fq 'Configuration Loaded' "$log_file"; then
            ready=1
            break
        fi
        if (( $(now_ms) - start_ms >= timeout_seconds * 1000 )); then
            break
        fi
        sleep 0.1
    done
    end_ms=$(now_ms)
    startup_ms=$((end_ms - start_ms))

    if ((ready == 0)); then
        echo >&2
        echo "runtime smoke run $run did not reach Configuration Loaded" >&2
        cat "$log_file" >&2
        kill "$quickshell_pid" 2>/dev/null || true
        wait "$quickshell_pid" 2>/dev/null || true
        exit 1
    fi

    for drawer in launcher sidebar dashboard utilities overview session; do
        ipc_try drawers toggle "$drawer"
        ipc_try drawers toggle "$drawer"
    done
    ipc_try notifs toggleDnd
    ipc_try notifs toggleDnd
    ipc_try notifs clear
    ipc_try wallpaper get
    ipc_try wallpaper list
    ipc_try plugins count
    ipc_try nexus open
    ipc_try nexus openPage 0 -1
    ipc_try nexus open
    ipc_try nexus close
    ipc_try nexus open
    ipc_try nexus close

    shell_pid=$(pgrep -n -f "quickshell.*$(ere_escape "$config_path")" || true)
    rss_kb=0
    idle_cpu_percent=0
    sleep 2
    if [[ -n "$shell_pid" && -r "/proc/$shell_pid/status" ]]; then
        rss_kb=$(awk '/VmRSS:/ {print $2}' "/proc/$shell_pid/status")
        idle_cpu_percent=$(ps -p "$shell_pid" -o %cpu= | tr -d ' ')
        if [[ -z "$rss_kb" ]]; then
            rss_kb=0
        fi
        if [[ -z "$idle_cpu_percent" ]]; then
            idle_cpu_percent=0
        fi
    fi
    if ! check_run_marks "$log_file" "$run"; then
        cat "$log_file" >&2
        exit 1
    fi
    if grep -Eq 'ERROR: Failed to load configuration|Cannot load library|Type .* unavailable' "$log_file"; then
        echo "runtime smoke run $run reported a fatal QML/plugin error" >&2
        grep -E 'ERROR: Failed to load configuration|Cannot load library|Type .* unavailable' "$log_file" >&2
        exit 1
    fi

    kill "$quickshell_pid" 2>/dev/null || true
    wait "$quickshell_pid" 2>/dev/null || true
    if [[ -n "$max_startup_ms" && "$startup_ms" -gt "$max_startup_ms" ]]; then
        echo "runtime smoke run $run exceeded startup limit: ${startup_ms}ms > ${max_startup_ms}ms" >&2
        exit 1
    fi
    if [[ -n "$max_rss_kb" && "$rss_kb" -gt "$max_rss_kb" ]]; then
        echo "runtime smoke run $run exceeded RSS limit: ${rss_kb}KiB > ${max_rss_kb}KiB" >&2
        exit 1
    fi
    if [[ -n "$max_ipc_limit_ms" && "$max_ipc_ms" -gt "$max_ipc_limit_ms" ]]; then
        echo "runtime smoke run $run exceeded IPC limit: ${max_ipc_ms}ms > ${max_ipc_limit_ms}ms" >&2
        exit 1
    fi
    if [[ -n "$max_idle_cpu" ]] && awk -v cpu="$idle_cpu_percent" -v limit="$max_idle_cpu" \
        'BEGIN { exit !(cpu > limit) }'; then
        echo "runtime smoke run $run exceeded idle CPU limit: ${idle_cpu_percent}% > ${max_idle_cpu}%" >&2
        exit 1
    fi

    scenario=cold
    if ((run > 1)); then
        scenario=warm
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$run" "$scenario" "$startup_ms" "$rss_kb" "$idle_cpu_percent" "$max_ipc_ms" >>"$results_tsv"
done
