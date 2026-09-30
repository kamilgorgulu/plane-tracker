#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ $# -ne 1 ]]; then
  print 'Usage: zsh scripts/install.sh IOS_DEVICE_IDENTIFIER'
  exit 1
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
plane_build_dir="${TMPDIR:-/tmp}/plane-tracker-install"
device_identifier="$1"
xcodebuild -project PlaneTracker.xcodeproj -scheme PlaneTracker -configuration Debug \
  -destination "id=$device_identifier" -derivedDataPath "$plane_build_dir" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device "$device_identifier" "$plane_build_dir/Build/Products/Debug-iphoneos/PlaneTracker.app"
bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plane_build_dir/Build/Products/Debug-iphoneos/PlaneTracker.app/Info.plist")
xcrun devicectl device process launch --device "$device_identifier" "$bundle_identifier"
