#!/usr/bin/env bash
# Analyze the complete shipping module once, then check imports only in files
# changed by the supplied pull-request base. Full import audits remain opt-in.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <xcodebuild-compiler-log>" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler_log="$1"
if [[ "$compiler_log" != /* ]]; then
  compiler_log="$PWD/$compiler_log"
fi
swiftlint_bin="${SWIFTLINT_BIN:-swiftlint}"
parallel_jobs="${SWIFTLINT_ANALYZER_JOBS-4}"
# Validated up front: an empty, negative, non-numeric, or zero value reached `xargs` and
# failed there with a tool-specific diagnostic, after the expensive whole-module analysis
# had already run. `-P 0` means "unlimited" on GNU xargs and is an error on
# BSD, so it is rejected rather than being silently platform-dependent.
if [[ ! "$parallel_jobs" =~ ^[1-9][0-9]*$ ]] || (( parallel_jobs > 64 )); then
  echo "error: SWIFTLINT_ANALYZER_JOBS must be an integer from 1 to 64, got '$parallel_jobs'" >&2
  exit 64
fi

analyzer_roots=(rankbuddy-macos)
baseline="$repo_root/.swiftlint-analyzer-baseline.json"

cd "$repo_root"

if [[ ! -f "$compiler_log" ]]; then
  echo "error: SwiftLint compiler log does not exist: $compiler_log" >&2
  exit 66
fi

if [[ ! -f "$baseline" ]]; then
  echo "error: SwiftLint analyzer baseline does not exist: $baseline" >&2
  exit 66
fi

temporary_directory="$(mktemp -d)"
# SwiftLint recognizes file lists by their .xcfilelist extension.
module_files="$temporary_directory/shipping.xcfilelist"
changed_files="$temporary_directory/changed"
trap 'rm -f "$module_files" "$changed_files"; rmdir "$temporary_directory"' EXIT

# Positional paths are combined with the normal config's `included` roots:
# a positional app directory also selected the configured test roots.
# A positional changed file repeated that scope for every import check.
# Script inputs preserve the intended module and individual-file scopes.
for source_root in "${analyzer_roots[@]}"; do
  find "$repo_root/$source_root" -name '*.swift' -print
done > "$module_files"

diff_base=""
if [[ "${SWIFTLINT_ANALYZE_ALL_IMPORTS:-0}" != "1" ]]; then
  if [[ -n "${SWIFTLINT_ANALYZER_DIFF_BASE:-}" ]]; then
    if ! git rev-parse --verify "${SWIFTLINT_ANALYZER_DIFF_BASE}^{commit}" >/dev/null 2>&1; then
      echo "error: cannot resolve SWIFTLINT_ANALYZER_DIFF_BASE: $SWIFTLINT_ANALYZER_DIFF_BASE" >&2
      exit 64
    fi
    if ! diff_base="$(git merge-base "$SWIFTLINT_ANALYZER_DIFF_BASE" HEAD)"; then
      echo "error: analyzer base and HEAD have no common history" >&2
      exit 64
    fi
  elif git rev-parse --verify HEAD^ >/dev/null 2>&1; then
    diff_base="HEAD^"
  fi
fi

rm -f "$repo_root/swiftlint-analyzer-findings.json"
analyzer_status=0
SCRIPT_INPUT_FILE_LIST_COUNT=1 SCRIPT_INPUT_FILE_LIST_0="$module_files" \
  "$swiftlint_bin" analyze --use-script-input-file-lists \
  --only-rule unused_declaration \
  --only-rule capture_variable \
  --only-rule typesafe_array_init \
  --baseline "$baseline" \
  --strict \
  --compiler-log-path "$compiler_log" \
  --reporter json \
  --output "$repo_root/swiftlint-analyzer-findings.json" \
  --quiet || analyzer_status=$?

# GitHub retains only ten error annotations per step. Print every location as
# plain text too, so the job log retains the complete report.
if [[ -s "$repo_root/swiftlint-analyzer-findings.json" ]]; then
  python3 - "$repo_root/swiftlint-analyzer-findings.json" <<'PYREPORT'
import json
import sys


def escape(value, *, property=False):
    value = str(value).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return value.replace(":", "%3A").replace(",", "%2C") if property else value


with open(sys.argv[1]) as report:
    for finding in json.load(report):
        path = finding["file"]
        line = finding["line"]
        column = finding.get("character", 1)
        level = finding["severity"].lower()
        message = f'{finding["reason"]} ({finding["rule_id"]})'
        print(f"{path}:{line}:{column}: {level}: {message}")
        print(f"::{level} file={escape(path, property=True)},line={line},col={column}::{escape(message)}")
PYREPORT
fi
if [[ "$analyzer_status" -ne 0 ]]; then
  exit "$analyzer_status"
fi

if [[ "${SWIFTLINT_ANALYZE_ALL_IMPORTS:-0}" == "1" ]]; then
  find "${analyzer_roots[@]}" -name '*.swift' -print0 > "$changed_files"
elif [[ -n "$diff_base" ]]; then
  while IFS= read -r -d '' source_file; do
    if [[ "$source_file" == *.swift && -f "$source_file" ]]; then
      printf '%s\0' "$source_file"
    fi
  done < <(git diff --name-only --diff-filter=ACMR -z "$diff_base" HEAD -- "${analyzer_roots[@]}") > "$changed_files"
else
  echo "warning: no parent commit is available; analyzing imports in every shipping source file" >&2
  find "${analyzer_roots[@]}" -name '*.swift' -print0 > "$changed_files"
fi

if [[ ! -s "$changed_files" ]]; then
  echo "SwiftLint unused-import analysis: no changed shipping Swift files"
  exit 0
fi

export SWIFTLINT_ANALYZER_BIN="$swiftlint_bin"
export SWIFTLINT_ANALYZER_COMPILER_LOG="$compiler_log"

# shellcheck disable=SC2016 # Variables expand in the nested bash process.
xargs -0 -n 1 -P "$parallel_jobs" bash -c '
  SCRIPT_INPUT_FILE_COUNT=1 SCRIPT_INPUT_FILE_0="$PWD/$1" \
    "$SWIFTLINT_ANALYZER_BIN" analyze --use-script-input-files \
    --only-rule unused_import \
    --strict \
    --compiler-log-path "$SWIFTLINT_ANALYZER_COMPILER_LOG" \
    --reporter github-actions-logging \
    --quiet
' _ < "$changed_files"
