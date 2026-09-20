#!/bin/zsh
set -euo pipefail

cd "${0:A:h}/.."

identity="${1:-}"
if [[ -z "$identity" ]]; then
    identity=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)
fi

if [[ -z "$identity" ]]; then
    print -u2 "No Apple Development signing identity found."
    print -u2 "Create one in Xcode > Settings > Accounts > Manage Certificates,"
    print -u2 "or pass an identity as the first argument."
    exit 1
fi

swift build -c release
binary="$(swift build -c release --show-bin-path)/sleepd"
codesign --force --sign "$identity" --entitlements Sleep.entitlements "$binary"
codesign --verify --strict --verbose=2 "$binary"
codesign -d --entitlements - "$binary"
print "Signed binary: $binary"
