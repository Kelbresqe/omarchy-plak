#!/usr/bin/env bash
# bin/ytm-app: browser choice and launch flags, against a fake PATH.
set -uo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/bin/ytm-app"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fake="$tmp/bin"; mkdir -p "$fake"
# Only the tools the launcher itself needs; no real browsers can leak in.
tools="$tmp/tools"; mkdir -p "$tools"; for t in mkdir chmod printf head tr; do ln -s "$(command -v $t)" "$tools/$t"; done
export YTM_PROFILE_DIR="$tmp/profile"
pass=0; fail=0
ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); echo "FAIL: $*"; }
stub() { printf '#!/bin/sh\nexit 0\n' > "$fake/$1"; chmod +x "$fake/$1"; }
xdg()  { printf '#!/bin/sh\necho "%s"\n' "$1" > "$fake/xdg-settings"; chmod +x "$fake/xdg-settings"; }
reset() { rm -f "$fake"/*; }
run()  { PATH="$fake:$tools" /usr/bin/bash "$APP" --print "$@" 2>"$tmp/err"; }

# 1. firefox only -> exit 3
reset; stub firefox; xdg firefox.desktop
run; rc=$?
[ $rc -eq 3 ] && ok || bad "firefox only: rc=$rc"
grep -q 'Chromium-family' "$tmp/err" && ok || bad "firefox only: no hint in stderr"

# 2. brave + chromium, xdg default firefox -> brave (order chrome, brave, chromium)
reset; stub brave; stub chromium; xdg firefox.desktop
out=$(run); [ "$(echo "$out" | head -1)" = "$fake/brave" ] && ok || bad "order: got $(echo "$out" | head -1)"

# 3. xdg default chromium.desktop, both present -> chromium
reset; stub brave; stub chromium; xdg chromium.desktop
out=$(run); [ "$(echo "$out" | head -1)" = "$fake/chromium" ] && ok || bad "xdg default: got $(echo "$out" | head -1)"

# 3b. xdg default google-chrome.desktop maps to google-chrome-stable
reset; stub brave; stub google-chrome-stable; xdg google-chrome.desktop
out=$(run); [ "$(echo "$out" | head -1)" = "$fake/google-chrome-stable" ] && ok || bad "xdg chrome map: got $(echo "$out" | head -1)"

# 4. --browser vivaldi wins; --browser firefox refused
reset; stub google-chrome-stable; stub vivaldi; stub firefox; xdg firefox.desktop
out=$(run --browser vivaldi); [ "$(echo "$out" | head -1)" = "$fake/vivaldi" ] && ok || bad "--browser: got $(echo "$out" | head -1)"
run --browser firefox >/dev/null; rc=$?; [ $rc -eq 3 ] && ok || bad "--browser firefox: rc=$rc"
run --browser 'brave; touch /tmp/x' >/dev/null; rc=$?; [ $rc -eq 3 ] && ok || bad "--browser hostile: rc=$rc"

# 5. flags, in order
reset; stub chromium; xdg chromium.desktop
out=$(run)
expected="$fake/chromium
--app=https://music.youtube.com
--user-data-dir=$YTM_PROFILE_DIR
--remote-debugging-port=0
--autoplay-policy=no-user-gesture-required
--no-first-run
--no-default-browser-check"
[ "$out" = "$expected" ] && ok || { bad "flags"; diff <(echo "$expected") <(echo "$out"); }
echo "$out" | grep -q 9222 && bad "fixed port present" || ok
[ -d "$YTM_PROFILE_DIR" ] && [ "$(stat -c %a "$YTM_PROFILE_DIR")" = "700" ] && ok || bad "profile dir not 0700"

# 7. the browser recorded in the profile wins over a changed default
reset; stub brave; stub chromium; xdg brave.desktop
mkdir -p "$YTM_PROFILE_DIR"; printf 'chromium\n' > "$YTM_PROFILE_DIR/Plak-Browser"
out=$(run); [ "$(echo "$out" | head -1)" = "$fake/chromium" ] && ok || bad "recorded browser: got $(echo "$out" | head -1)"
# 8. ...unless it is no longer installed
reset; stub brave; xdg brave.desktop
out=$(run); [ "$(echo "$out" | head -1)" = "$fake/brave" ] && ok || bad "recorded missing: got $(echo "$out" | head -1)"
# 9. an explicit --browser beats the record
reset; stub brave; stub chromium; xdg chromium.desktop
out=$(run --browser brave); [ "$(echo "$out" | head -1)" = "$fake/brave" ] && ok || bad "explicit over record: got $(echo "$out" | head -1)"
# 10. a hostile record is ignored
reset; stub brave; stub chromium; xdg brave.desktop
printf 'chromium; touch /tmp/x\n' > "$YTM_PROFILE_DIR/Plak-Browser"
out=$(run); [ "$(echo "$out" | head -1)" = "$fake/brave" ] && ok || bad "hostile record: got $(echo "$out" | head -1)"
# --print never writes the record
[ "$(cat "$YTM_PROFILE_DIR/Plak-Browser")" = "chromium; touch /tmp/x" ] && ok || bad "--print rewrote the record"
rm -f "$YTM_PROFILE_DIR/Plak-Browser"

# 6. --signin: same profile, Google's sign-in page, and no debug port
reset; stub chromium; xdg chromium.desktop
out=$(run --signin --marker "$tmp/marker")
expected="$fake/chromium
--user-data-dir=$YTM_PROFILE_DIR
--no-first-run
--no-default-browser-check
https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com%2F"
[ "$out" = "$expected" ] && ok || { bad "signin flags"; diff <(echo "$expected") <(echo "$out"); }
echo "$out" | grep -q -- '--remote-debugging' && bad "signin has debug port" || ok
[ -e "$tmp/marker" ] && bad "--print wrote the marker" || ok

echo "test-app-launch: $pass passed, $fail failed"
[ $fail -eq 0 ]
