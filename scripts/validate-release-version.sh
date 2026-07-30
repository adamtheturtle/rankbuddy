#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $(basename "$0") <marketing-version> <build-number> <tag-name>" >&2
  exit 64
fi

marketing="$1"
build="$2"
tag="$3"

if [[ ! "$marketing" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "error: marketing version '$marketing' must look like 1.2 or 1.2.0" >&2
  exit 64
fi
if [[ ! "$build" =~ ^[0-9]+$ || "$build" == "0" ]]; then
  echo "error: build number '$build' must be a positive integer" >&2
  exit 64
fi
if [[ "$tag" != "v$marketing" ]]; then
  echo "error: tag '$tag' does not match marketing version '$marketing'" >&2
  exit 64
fi

max_prior_build=0
while IFS= read -r existing_tag; do
  [[ -n "$existing_tag" && "$existing_tag" != "$tag" ]] || continue
  existing_build="$(git rev-list --count "$existing_tag^{commit}")"
  (( existing_build > max_prior_build )) && max_prior_build="$existing_build"
done < <(git tag --list 'v[0-9]*')

if (( build <= max_prior_build )); then
  echo "error: build number '$build' must exceed prior release build '$max_prior_build'" >&2
  exit 1
fi

echo "Validated release version $marketing (build $build)."
