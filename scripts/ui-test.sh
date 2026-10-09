#!/usr/bin/env bash
# Runs the MealMateUITests (XCUITest) suite against a real Mealie server.
#
#   scripts/ui-test.sh [options] <udid> [TestClass[/testMethod] ...]
#
# Builds and tests the MealMateUITests scheme. Without test names it runs every UI test;
# otherwise it passes -only-testing:MealMateUITests/<name> for each.
#
# Options:
#   --derived-data <dir>  DerivedData dir (default: $MEALMATE_DERIVED_DATA or build/DD-uitest)
#   --keep-results        keep the .xcresult bundle (build/ui-tests.xcresult). It contains
#                         the typed API token in its activity log: local only, never share it.
#
# Server and token are read from ~/.config/mealmate/test-server and ~/.config/mealmate/test-token
# (override with MEALMATE_TEST_SERVER_FILE / MEALMATE_TEST_TOKEN_FILE) and handed to the
# test runner as TEST_RUNNER_MEALMATE_TEST_SERVER / TEST_RUNNER_MEALMATE_TEST_TOKEN. Both are
# redacted from the xcodebuild output. Screenshots land in screenshots/qa-*.png (git-ignored).
set -euo pipefail

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

derived_data="${MEALMATE_DERIVED_DATA:-}"
keep_results=0
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --derived-data) derived_data="$2"; shift 2 ;;
    --keep-results) keep_results=1; shift ;;
    -h|--help) usage ;;
    *) positional+=("$1"); shift ;;
  esac
done
[[ ${#positional[@]} -ge 1 ]] || usage
udid="${positional[0]}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${derived_data:-$repo_root/build/DD-uitest}"
results="$repo_root/build/ui-tests.xcresult"
server_file="${MEALMATE_TEST_SERVER_FILE:-$HOME/.config/mealmate/test-server}"
token_file="${MEALMATE_TEST_TOKEN_FILE:-$HOME/.config/mealmate/test-token}"

server=""; token=""
[[ -f "$server_file" ]] && server="$(tr -d '[:space:]' < "$server_file")"
[[ -f "$token_file" ]] && token="$(tr -d '[:space:]' < "$token_file")"
[[ -n "$server" ]] || { echo "error: no server in $server_file" >&2; exit 1; }
[[ -n "$token" ]] || { echo "error: no token in $token_file" >&2; exit 1; }

only=()
for name in "${positional[@]:1}"; do only+=("-only-testing:MealMateUITests/$name"); done

rm -rf "$results"
export TEST_RUNNER_MEALMATE_TEST_SERVER="$server"
export TEST_RUNNER_MEALMATE_TEST_TOKEN="$token"
export MEALMATE_REDACT_TOKEN="$token" MEALMATE_REDACT_SERVER="$server"

cd "$repo_root"
status=0
xcodebuild -project MealMate.xcodeproj -scheme MealMateUITests -configuration Debug \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$derived_data" \
  -resultBundlePath "$results" ${only[@]+"${only[@]}"} test 2>&1 \
  | perl -pe 'BEGIN { $t = $ENV{MEALMATE_REDACT_TOKEN}; $s = $ENV{MEALMATE_REDACT_SERVER} }
              s/\Q$t\E/<token>/g; s/\Q$s\E/<server>/g if $s =~ m{[.:/]}' \
  || status=$?

# The result bundle records typed text (the token) and xcodebuild also keeps a copy in
# DerivedData's test logs.
rm -rf "$derived_data/Logs/Test"
if [[ $keep_results -eq 0 ]]; then rm -rf "$results"; fi
exit "$status"
