#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mock_dir=$repo_dir/tests/fixtures
apple='http://captive.apple.com/hotspot-detect.html'
arch='http://ping.archlinux.org/nm-check.txt'

assert_probe() {
  local scenario=$1 mode=$2 expected_status=$3 expected_url=$4 output status

  if output=$(MOCK_CASE=$scenario PATH="$mock_dir:$PATH" \
    bash "$repo_dir/detect-portal.sh" "$apple" "$mode" "$arch"); then
    status=0
  else
    status=$?
  fi

  if [[ $status -ne $expected_status || $output != "$expected_url" ]]; then
    printf 'FAIL %s/%s: status=%s url=%q (expected %s %q)\n' \
      "$scenario" "$mode" "$status" "$output" "$expected_status" "$expected_url" >&2
    exit 1
  fi
  printf 'ok %s/%s\n' "$scenario" "$mode"
}

assert_probe absolute confirm 0 'https://login.example/start?token=abc'
assert_probe relative confirm 0 'http://captive.apple.com/login'
assert_probe inline confirm 0 "$apple"
assert_probe online confirm 1 ''
assert_probe fallback-redirect suspect 0 'https://hotel.example/auth'
assert_probe fallback-inline suspect 0 "$arch"
assert_probe fallback-online suspect 1 ''
assert_probe invalid-redirect confirm 1 ''
assert_probe failure suspect 1 ''
