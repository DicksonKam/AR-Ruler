#!/bin/zsh
# Proves that Release builds can't accept virtual input, by looking for the feature in the built binaries.
# It also checks a Debug build, because finding nothing means little unless the same search finds it there.
set -u
cd "$(dirname "$0")/.."
work="${1:-$(mktemp -d)}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
pattern='input-script|VirtualInput|setPhysicalInputEnabled|rightclick'

matches() {
    { strings -a "$1"; nm -a "$1" 2>/dev/null; } | grep -cE "$pattern"
}

for configuration in Debug Release; do
    xcodebuild -project AR-Ruler.xcodeproj -scheme AR-Ruler -configuration "$configuration" \
        -derivedDataPath "$work/$configuration" build >/dev/null 2>&1 || { echo "FAILED: $configuration build"; exit 1; }
done

app="$work/%s/Build/Products/%s/AR-Ruler.app/Contents/MacOS"
debug_dir=$(printf "$app" Debug Debug)
release_dir=$(printf "$app" Release Release)

debug_count=0
for file in "$debug_dir"/*; do debug_count=$((debug_count + $(matches "$file"))); done
release_count=0
for file in "$release_dir"/*; do release_count=$((release_count + $(matches "$file"))); done

echo "Debug matches:   $debug_count"
echo "Release matches: $release_count"
if [ "$debug_count" -eq 0 ]; then
    echo "FAILED: the search found nothing in Debug either, so it proves nothing"
    exit 1
fi
if [ "$release_count" -ne 0 ]; then
    echo "FAILED: Release contains virtual input"
    exit 1
fi
echo "OK: Release has no virtual input"
