#!/usr/bin/env bash
# Takes light + dark screenshots of one MealMate screen in the simulator.
#
#   scripts/screenshot.sh [options] <udid> <route> <name>
#
# Installs an already built MealMate.app (it never builds), launches it with
# `-MealMateRoute <route>` and the DEBUG test harness credentials, and saves
# screenshots/<name>-light.png and screenshots/<name>-dark.png.
#
# Options:
#   --no-token        launch without MEALMATE_TEST_TOKEN (onboarding / login screens)
#   --app <path>      path to MealMate.app (default: derived from --derived-data)
#   --derived-data <dir>  DerivedData dir (default: $MEALMATE_DERIVED_DATA or build/DD-foundation)
#   --delay <sec>     wait before capturing (default: $MEALMATE_SHOT_DELAY or 4)
#   --only light|dark capture a single appearance
#   --width <points>  (iPad) narrow the window to that width, horizontally compact, like a
#                     narrow Split View / Slide Over window; the shot is cropped to it
#   --suffix <text>   appended to <name> (e.g. -landscape), default none
#
# Credentials are read from ~/.config/mise/test-server and ~/.config/mise/test-token
# (override with MEALMATE_TEST_SERVER_FILE / MEALMATE_TEST_TOKEN_FILE). The token is
# passed via SIMCTL_CHILD_* and never printed.
set -euo pipefail

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

with_token=1
app_path=""
derived_data="${MEALMATE_DERIVED_DATA:-}"
delay="${MEALMATE_SHOT_DELAY:-4}"
appearances=(light dark)
window_width=""
suffix=""
positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-token) with_token=0; shift ;;
    --app) app_path="$2"; shift 2 ;;
    --derived-data) derived_data="$2"; shift 2 ;;
    --delay) delay="$2"; shift 2 ;;
    --only) appearances=("$2"); shift 2 ;;
    --width) window_width="$2"; shift 2 ;;
    --suffix) suffix="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) positional+=("$1"); shift ;;
  esac
done
[[ ${#positional[@]} -eq 3 ]] || usage
udid="${positional[0]}"
route="${positional[1]}"
name="${positional[2]}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_id="com.mealmate-app.ios"
derived_data="${derived_data:-$repo_root/build/DD-foundation}"
app_path="${app_path:-$derived_data/Build/Products/Debug-iphonesimulator/MealMate.app}"
out_dir="$repo_root/screenshots"
server_file="${MEALMATE_TEST_SERVER_FILE:-$HOME/.config/mise/test-server}"
token_file="${MEALMATE_TEST_TOKEN_FILE:-$HOME/.config/mise/test-token}"

[[ -d "$app_path" ]] || { echo "error: app not found at $app_path (build first)" >&2; exit 1; }
mkdir -p "$out_dir"

server=""
[[ -f "$server_file" ]] && server="$(tr -d '[:space:]' < "$server_file")"
[[ -n "$server" ]] || { echo "error: no server in $server_file" >&2; exit 1; }

# Boot if needed, then install the current build.
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app_path"

# Clean status bar: 9:41, full battery, full signal.
xcrun simctl status_bar "$udid" override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true

# Narrow window launch argument (DEBUG `DebugWindow`). Rotate with scripts/sim-orientation.sh.
geometry_args=()
[[ -n "$window_width" ]] && geometry_args+=(-MealMateWindowWidth "$window_width")

for appearance in "${appearances[@]}"; do
  xcrun simctl ui "$udid" appearance "$appearance"
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true

  if [[ $with_token -eq 1 ]]; then
    [[ -f "$token_file" ]] || { echo "error: no token file at $token_file" >&2; exit 1; }
    SIMCTL_CHILD_MEALMATE_TEST_SERVER="$server" \
    SIMCTL_CHILD_MEALMATE_TEST_TOKEN="$(cat "$token_file")" \
      xcrun simctl launch "$udid" "$bundle_id" -MealMateRoute "$route" ${geometry_args[@]+"${geometry_args[@]}"} >/dev/null
  else
    SIMCTL_CHILD_MEALMATE_TEST_SERVER="$server" \
      xcrun simctl launch "$udid" "$bundle_id" -MealMateRoute "$route" ${geometry_args[@]+"${geometry_args[@]}"} >/dev/null
  fi

  sleep "$delay"
  file="$out_dir/$name$suffix-$appearance.png"
  xcrun simctl io "$udid" screenshot --type=png "$file" >/dev/null 2>&1
  if [[ -n "$window_width" ]]; then
    # Crop to the narrowed window (left edge); iPads render at 2x.
    height=$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')
    sips -c "$height" "$((window_width * ${MEALMATE_SHOT_SCALE:-2}))" --cropOffset 1 1 "$file" >/dev/null
  fi
  echo "saved screenshots/$name$suffix-$appearance.png"
done
