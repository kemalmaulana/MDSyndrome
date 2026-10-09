#!/usr/bin/env bash
# PRD NF-2 (cold launch to first window) and NF-5 (idle CPU, memory with a 1 MB document). Needs `make build` first.
# Launches its own copy, finds it by exact PID, and kills only that PID. The app comes to the front for about 15 seconds
# (a background launch shows no window, so there would be nothing to time): do not type while it runs.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/DerivedData/Build/Products/Debug/MDSyndrome.app"
[[ -d "$APP" ]] || { echo "build the app first: make build"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
DOC="$work/large.md"
for _ in $(seq 1 240); do cat Fixtures/kitchen-sink.md; echo; done > "$DOC"   # about 1 MB

# A tiny helper: how many normal on-screen windows does this PID own?
cat > "$work/windows.swift" <<'SWIFT'
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
print(list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }.count)
SWIFT
swiftc -O "$work/windows.swift" -o "$work/windows" 2>/dev/null

before=" $(pgrep -x MDSyndrome | sort | tr '\n' ' ' || true)"
start=$(python3 -c 'import time; print(time.time())')
open -n -F "$APP" "$DOC"
pid=""
for _ in $(seq 1 200); do
  for p in $(pgrep -x MDSyndrome); do [[ "$before" == *" $p "* ]] || pid=$p; done
  [[ -n "$pid" ]] && break
  sleep 0.02
done
[[ -n "$pid" ]] || { echo "could not find the new instance"; exit 1; }
trap 'kill "$pid" 2>/dev/null || true; rm -rf "$work"' EXIT

first=""
for _ in $(seq 1 600); do
  if [[ "$("$work/windows" "$pid")" -gt 0 ]]; then
    first=$(python3 -c "import time; print(round(time.time() - $start, 2))")
    break
  fi
  sleep 0.05
done
echo "PERF NF-2 launch to first window: ${first:-n/a} s (debug build, opening a 1 MB document)"

sleep 8   # let the first render and highlighting finish before sampling
cpu=$(top -l 3 -s 2 -pid "$pid" -stats cpu | tail -1 | tr -d ' ')
rss=$(ps -o rss= -p "$pid" | awk '{printf "%.0f", $1/1024}')
echo "PERF NF-5 idle CPU: ${cpu}%  memory: ${rss} MB (1 MB document open, debug build)"
