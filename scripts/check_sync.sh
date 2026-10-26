#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output_dir=$(mktemp -d /tmp/questlog-sync-check.XXXXXX)
trap 'rm -rf "$output_dir"' EXIT
swiftc -parse-as-library sync/Snapshot.swift sync/CloudKitTransport.swift sync/MacPublisher.swift phone/PhoneModel.swift tests/SyncChecks.swift -module-cache-path /tmp/questlog-swift-cache -framework AppKit -framework CloudKit -o "$output_dir/checks"
"$output_dir/checks"
