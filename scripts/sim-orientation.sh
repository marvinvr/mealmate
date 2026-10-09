#!/usr/bin/env bash
# Rotates a simulator (e.g. an iPad for landscape screenshots).
#
#   scripts/sim-orientation.sh [--derived-data <dir>] <udid> landscape|portrait
#
# simctl can't rotate a device and iPad apps can't rotate themselves in windowing modes, so
# this runs the one-line UI test DeviceOrientationUITests (XCUIDevice.orientation). The
# orientation sticks after the test runner exits; take screenshots with scripts/screenshot.sh.
# Builds the MealMateUITests scheme for testing first if needed (no server or token used).
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

derived_data="${MEALMATE_DERIVED_DATA:-}"
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --derived-data) derived_data="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) positional+=("$1"); shift ;;
  esac
done
[[ ${#positional[@]} -eq 2 ]] || usage
udid="${positional[0]}"
orientation="${positional[1]}"
[[ "$orientation" == landscape || "$orientation" == portrait ]] || usage

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${derived_data:-$repo_root/build/DD-uitest}"
cd "$repo_root"

xctestrun=$(ls "$derived_data"/Build/Products/MealMateUITests_*.xctestrun 2>/dev/null | head -1 || true)
if [[ -z "$xctestrun" ]]; then
  xcodebuild -project MealMate.xcodeproj -scheme MealMateUITests -configuration Debug \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$derived_data" \
    build-for-testing >/dev/null
  xctestrun=$(ls "$derived_data"/Build/Products/MealMateUITests_*.xctestrun | head -1)
fi

TEST_RUNNER_MEALMATE_ORIENTATION="$orientation" \
  xcodebuild test-without-building -xctestrun "$xctestrun" \
  -destination "platform=iOS Simulator,id=$udid" \
  -only-testing:MealMateUITests/DeviceOrientationUITests/testSetOrientation 2>&1 \
  | grep -E "error|\*\* TEST" || true
rm -rf "$derived_data/Logs/Test"
