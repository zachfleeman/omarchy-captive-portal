#!/bin/bash
# Probes a captive portal endpoint and prints the sign-in URL.

PROBE="${1:-http://captive.apple.com/hotspot-detect.html}"
MODE="${2:-confirm}"
FALLBACK="${3:-http://ping.archlinux.org/nm-check.txt}"

body=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/omarchy-captive-probe.XXXXXX") || exit 1
trap 'rm -f "$body"' EXIT

probe_once() {
  local url=$1 expected=$2 result code redirect

  # curl resolves relative Location headers for us. The first hop is the URL
  # the sign-in browser needs; following it could complete a login request.
  result=$(curl -sS -m 5 --max-redirs 0 -o "$body" \
    -w '%{http_code}\n%{redirect_url}' \
    -A "CaptiveNetworkSupport-355.200.27 wispr" \
    "$url" 2>/dev/null) || return 1

  code=${result%%$'\n'*}
  redirect=${result#*$'\n'}

  if [[ $code == 3[0-9][0-9] && $redirect =~ ^https?://[^[:cntrl:]]{1,2000}$ ]]; then
    printf '%s\n' "$redirect"
    return 0
  fi

  # A portal can return its login form directly with HTTP 200. A response
  # matching the expected body means this probe endpoint is reachable online.
  if [[ $code == 200 ]] && ! grep -Fqi "$expected" "$body"; then
    printf '%s\n' "$url"
    return 0
  fi

  return 1
}

probe_once "$PROBE" '<TITLE>Success</TITLE>' && exit 0

# Some networks allowlist Apple's check even before login. When NetworkManager
# still suspects a portal, try its configured Arch probe before giving up.
if [[ $MODE == suspect ]]; then
  probe_once "$FALLBACK" 'NetworkManager is online' && exit 0
fi

exit 1
