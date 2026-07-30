#!/usr/bin/env bash

set -euo pipefail

to="${2:-HEAD}"
from="${1:-$(git describe --tags --match 'v[0-9]*' --abbrev=0 "${to}^" 2>/dev/null || true)}"

if [[ -n "$from" ]]; then
  range="${from}..${to}"
  echo "## Changes (${from} → ${to})"
else
  range="$to"
  echo "## Changes (initial release)"
fi
echo

if ! git log --no-merges --reverse --pretty=format:'- %s' "$range" | grep -q .; then
  echo "_No changes._"
  exit 0
fi
git log --no-merges --reverse --pretty=format:'- %s' "$range"
echo

remote="$(git config --get remote.origin.url 2>/dev/null || true)"
slug="${remote#git@github.com:}"
slug="${slug#https://github.com/}"
slug="${slug#ssh://git@github.com/}"
slug="${slug%.git}"
if [[ -n "$from" && "$slug" != "$remote" ]]; then
  echo
  echo "**Full diff:** https://github.com/${slug}/compare/${from}...${to}"
fi
