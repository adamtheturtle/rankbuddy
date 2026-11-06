#!/usr/bin/env bash
#
# Update one Xcode Swift package requirement and resolve the committed graph.

set -euo pipefail

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
  shift
fi

if [[ $# -ne 2 ]]; then
  echo "usage: $0 [--dry-run] <package-name> <version>" >&2
  exit 64
fi

package_name="$1"
version="$2"
if [[ ! "$package_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "error: invalid package name: $package_name" >&2
  exit 65
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$ ]]; then
  echo "error: version must be a semantic version without a leading v" >&2
  exit 65
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_file="$repo_root/rankbuddy-macos.xcodeproj/project.xcproj"
resolved_file="$repo_root/rankbuddy-macos.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

for command_name in ruby xcodebuild; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: $command_name is required" >&2
    exit 69
  fi
done

ruby - "$project_file" "$package_name" "$version" "$dry_run" <<'RUBY'
path, package, version, dry_run = ARGV
contents = File.read(path)
escaped = Regexp.escape(package)
pattern = /("repository"\s*:\s*"https:\/\/github\.com\/[^"\/]+\/#{escaped}(?:\.git)?\/?",\s*"version"\s*:\s*\{\s*"(?:version|up-to-next-major-version)"\s*:\s*")[^"]+"/i
matches = contents.scan(pattern).length
abort "error: expected one Xcode package requirement for #{package}, found #{matches}" unless matches == 1
updated = contents.sub(pattern) { "#{$1}#{version}\"" }
if dry_run == "1"
  puts "Would update #{package} to #{version}."
  exit
end
File.write(path, updated)
RUBY

if [[ "$dry_run" == "1" ]]; then
  exit 0
fi

cd "$repo_root"
xcodebuild -resolvePackageDependencies \
  -quiet \
  -project rankbuddy-macos.xcodeproj \
  -scheme rankbuddy-macos

ruby -rjson - "$resolved_file" "$package_name" "$version" <<'RUBY'
path, package, expected = ARGV
identity = package.downcase
pin = JSON.parse(File.read(path)).fetch("pins").find { |candidate| candidate.fetch("identity") == identity }
abort "error: Package.resolved has no #{package} pin" unless pin
actual = pin.fetch("state")["version"]
abort "error: resolved #{package} at #{actual.inspect}, expected #{expected}" unless actual == expected
puts "Updated #{package} to #{actual}. Review the graph, then run ./scripts/preflight.sh."
RUBY
