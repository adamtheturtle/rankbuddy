#!/usr/bin/env bash
#
# Generate the signed Sparkle feed published beside a tagged release (#11).
#
# Usage: scripts/generate-appcast.sh <tag> [<dmg>]
#
# SPARKLE_PRIVATE_ED_KEY must contain the private key exported by Sparkle's
# `generate_keys -x`. The matching public key is injected into the Release
# build by the workflow and is never derived from this secret.
set -euo pipefail

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

tag="${1:-}"
[ -n "$tag" ] || die "usage: $0 <tag> [<dmg>]"

archive="${2:-rankbuddy-${tag}.dmg}"
[ -f "$archive" ] || die "update archive not found: $archive"
: "${SPARKLE_PRIVATE_ED_KEY:?set SPARKLE_PRIVATE_ED_KEY}"

sparkle_version="${SPARKLE_VERSION:-2.9.6}"
server_url="${GITHUB_SERVER_URL:-https://github.com}"
repository="${GITHUB_REPOSITORY:-adamtheturtle/rankbuddy-macos}"
download_prefix="${server_url}/${repository}/releases/download/${tag}/"

work="$(mktemp -d)"
cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT

key_file="$work/sparkle-private-key"
archives_dir="$work/archives"
(umask 077 && printf '%s' "$SPARKLE_PRIVATE_ED_KEY" > "$key_file")

curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 180 \
    "https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/Sparkle-${sparkle_version}.tar.xz" \
    -o "$work/sparkle.tar.xz"
tar -xJf "$work/sparkle.tar.xz" -C "$work"
[ -x "$work/bin/generate_appcast" ] || die "generate_appcast not found in Sparkle archive"

mkdir -p "$archives_dir"
cp "$archive" "$archives_dir/"
"$work/bin/generate_appcast" \
    --ed-key-file "$key_file" \
    --download-url-prefix "$download_prefix" \
    "$archives_dir"
cp "$archives_dir/appcast.xml" appcast.xml
