#!/usr/bin/env bash
# Generate the signed feed using the resolved Sparkle tool release.
# Usage: scripts/generate-appcast.sh <vMAJOR.MINOR.PATCH> [<dmg>]
# SPARKLE_PRIVATE_ED_KEY signs the enclosure. Its matching public key is
# injected separately into the Release app; it is never derived here.
# SPARKLE_VERSION may select another explicitly trusted tool version.
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

tag="${1:-}"
component='(0|[1-9][0-9]{0,8})'
[[ "$tag" =~ ^v${component}\.${component}\.${component}$ ]] \
    || die "tag must use canonical vMAJOR.MINOR.PATCH form"

archive="${2:-rankbuddy-${tag}.dmg}"
[ -f "$archive" ] || die "update archive not found: $archive"
archive_name="$(basename -- "$archive")"
[ "$archive_name" = "rankbuddy-${tag}.dmg" ] \
    || die "update archive must be named rankbuddy-${tag}.dmg"

output="./appcast.xml"
if [ -L "$output" ] || { [ -e "$output" ] && [ ! -f "$output" ]; }; then
    die "appcast.xml output must be absent or a regular file"
fi

server_url="${GITHUB_SERVER_URL:-https://github.com}"
[[ "$server_url" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?/?$ ]] \
    || die "GITHUB_SERVER_URL must be an HTTPS origin without credentials, path, query, or fragment"
server_url="${server_url%/}"
repository="${GITHUB_REPOSITORY:-adamtheturtle/rankbuddy}"
[[ "$repository" =~ ^[A-Za-z0-9](-?[A-Za-z0-9])*/[A-Za-z0-9._-]+$ ]] \
    || die "GITHUB_REPOSITORY must be owner/repo"
case "$repository" in
    */.|*/..|*/.git) die "GITHUB_REPOSITORY must not name a dot segment" ;;
esac
download_prefix="${server_url}/${repository}/releases/download/${tag}/"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolved="$repo_root/rankbuddy-macos.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
resolved_version="$(jq -er '.pins[] | select(.identity == "sparkle") | .state.version' "$resolved")" \
    || die "could not resolve Sparkle version from $resolved"
sparkle_version="${SPARKLE_VERSION:-$resolved_version}"
case "$sparkle_version" in
    2.9.6)
        archive_sha256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
        ;;
    *) die "no trusted archive checksum pinned for Sparkle $sparkle_version" ;;
esac
: "${SPARKLE_PRIVATE_ED_KEY:?set SPARKLE_PRIVATE_ED_KEY}"

work="$(mktemp -d)"
output_tmp=""
cleanup() {
    rm -rf "$work"
    [ -z "$output_tmp" ] || rm -f "$output_tmp"
}
trap cleanup EXIT

# Authenticate the downloaded tool archive before extracting code or writing
# signing-key material into its working directory.
curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 180 \
    "https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/Sparkle-${sparkle_version}.tar.xz" \
    -o "$work/sparkle.tar.xz"
actual_sha256="$(shasum -a 256 "$work/sparkle.tar.xz" | awk '{print $1}')"
[ "$actual_sha256" = "$archive_sha256" ] \
    || die "Sparkle archive checksum mismatch (expected $archive_sha256, got $actual_sha256)"
tar -xJf "$work/sparkle.tar.xz" -C "$work"
[ -x "$work/bin/generate_appcast" ] || die "generate_appcast not found in Sparkle archive"

key_file="$work/sparkle-private-key"
archives_dir="$work/archives"
(umask 077 && printf '%s' "$SPARKLE_PRIVATE_ED_KEY" > "$key_file")
mkdir -p "$archives_dir"
cp "$archive" "$archives_dir/$archive_name"
"$work/bin/generate_appcast" \
    --ed-key-file "$key_file" \
    --download-url-prefix "$download_prefix" \
    "$archives_dir"
output_tmp="$(mktemp ./appcast.xml.tmp.XXXXXX)"
cp "$archives_dir/appcast.xml" "$output_tmp"
mv -f "$output_tmp" "$output"
output_tmp=""
