#!/usr/bin/env bash
#
# Retain complete xcodebuild output while keeping terminal and CI logs useful.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <log-path> <xcodebuild arguments...>" >&2
  exit 64
fi

log_path="$1"
shift
xcodebuild_bin="${XCODEBUILD_BIN:-xcodebuild}"
result_bundle=""
expect_result_bundle=0

for argument in "$@"; do
  if [[ "$expect_result_bundle" == "1" ]]; then
    result_bundle="$argument"
    break
  fi
  if [[ "$argument" == "-resultBundlePath" ]]; then
    expect_result_bundle=1
  fi
done

if [[ -n "$result_bundle" && "$result_bundle" != /* ]]; then
  result_bundle="$PWD/$result_bundle"
fi
if [[ "$log_path" != /* ]]; then
  log_path="$PWD/$log_path"
fi

mkdir -p "$(dirname "$log_path")"
started_at="$SECONDS"

if "$xcodebuild_bin" "$@" > "$log_path" 2>&1; then
  echo "xcodebuild succeeded in $((SECONDS - started_at))s; full log: $log_path"
  sed -n '/Build Timing Summary/,$p' "$log_path" | tail -n 120
  grep -E 'Test session results|Executed [0-9]+ tests|\*\* (BUILD|TEST|ARCHIVE) SUCCEEDED \*\*' \
    "$log_path" | tail -n 20 || true
  if [[ -d "$result_bundle" ]] && command -v jq >/dev/null 2>&1; then
    if ! xcrun xcresulttool get build-results metrics --path "$result_bundle" | \
      jq -r '"Result: \(.actionTitle) — \(.status) in \((.endTime - .startTime) | floor)s, "
        + "\(.warningCount) warnings, \(.errorCount) errors"'; then
      echo "warning: could not summarize result bundle: $result_bundle" >&2
    fi
  fi
  exit 0
fi

echo "xcodebuild failed after $((SECONDS - started_at))s; full log: $log_path" >&2
if ! grep -n -E -B 2 -A 2 \
  '(^| )error:|fatal error:|Test case .* failed|Failing tests:|\*\* (BUILD|TEST|ARCHIVE|EXPORT) FAILED \*\*' \
  "$log_path" | tail -n 300 >&2; then
  tail -n 200 "$log_path" >&2
fi
exit 1
