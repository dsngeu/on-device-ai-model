#!/usr/bin/env bash

set -euo pipefail

PROJECT="Debrief.xcodeproj"
SCHEME="Debrief"
BUNDLE_ID="com.debriefus.app.Debrief"
BUILD_DIR="${PWD}/build"
DEFAULT_SIMULATOR="iPhone 17"
DEFAULT_DEVICE="iPhone"

usage() {
  cat <<'EOF'
Usage:
  ./run-ios.sh sim [SIMULATOR_NAME]
  ./run-ios.sh device [DEVICE_NAME_OR_ID]
  ./run-ios.sh list-sims
  ./run-ios.sh list-devices

Examples:
  ./run-ios.sh sim
  ./run-ios.sh sim "iPhone 17"
  ./run-ios.sh device
  ./run-ios.sh device "iPhone"

Notes:
  - `device` stays attached to the app console until the app exits.
  - Press Ctrl+C to stop watching the device console.
EOF
}

list_sims() {
  xcrun simctl list devices available
}

list_devices() {
  xcrun devicectl list devices
}

run_simulator() {
  local simulator_name="${1:-$DEFAULT_SIMULATOR}"

  echo "Opening Simulator..."
  open -a Simulator

  echo "Booting simulator: ${simulator_name}"
  xcrun simctl boot "${simulator_name}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${simulator_name}" -b

  echo "Building for simulator..."
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "platform=iOS Simulator,name=${simulator_name}" \
    -derivedDataPath "${BUILD_DIR}" \
    build

  local app_path="${BUILD_DIR}/Build/Products/Debug-iphonesimulator/${SCHEME}.app"

  echo "Installing app on simulator..."
  xcrun simctl install booted "${app_path}"

  echo "Launching app on simulator..."
  xcrun simctl launch booted "${BUNDLE_ID}"
}

run_device() {
  local device_name="${1:-$DEFAULT_DEVICE}"

  echo "Building for device: ${device_name}"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath "${BUILD_DIR}" \
    build

  local app_path="${BUILD_DIR}/Build/Products/Debug-iphoneos/${SCHEME}.app"

  echo "Installing app on device..."
  xcrun devicectl device install app --device "${device_name}" "${app_path}"

  echo "Launching app on device and attaching to console..."
  xcrun devicectl device process launch \
    --device "${device_name}" \
    "${BUNDLE_ID}" \
    --activate \
    --terminate-existing \
    --console
}

main() {
  local mode="${1:-}"

  case "${mode}" in
    sim)
      shift || true
      run_simulator "${1:-}"
      ;;
    device)
      shift || true
      run_device "${1:-}"
      ;;
    list-sims)
      list_sims
      ;;
    list-devices)
      list_devices
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
