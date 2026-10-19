# Captive Portal

Detects captive portals on Wi-Fi networks, opens the sign-in page in a
centered floating window, and adds sign-in status to Omarchy's Wi-Fi dropdown.

Many public networks connect successfully but block traffic until you sign in
on a portal page. This plugin detects that state, sends a notification naming
the network, opens the sign-in page, and makes the portal URL available to copy
from the Wi-Fi dropdown.

## Installation

```bash
omarchy plugin add https://github.com/zachfleeman/omarchy-captive-portal
omarchy plugin enable io.github.zachfleeman.captive
```

Enabling the plugin replaces the stock `omarchy.network` bar widget with the
bundled Wi-Fi widget. Disabling or removing it restores the stock widget.
The bundled widget is a snapshot of Omarchy's network widget and may need
updates when Omarchy changes that widget.
Existing users upgrading from the service-only version should run:

```bash
omarchy plugin update io.github.zachfleeman.captive
omarchy plugin disable io.github.zachfleeman.captive
omarchy plugin enable io.github.zachfleeman.captive
```

## Usage

Detection and opening are automatic. The Wi-Fi dropdown has compact sign-in
status and a URL copy icon in its connection-details grid. Click the copy icon
to copy the full portal URL. When no portal is detected, it copies the manual
`http://neverssl.com/` fallback instead. "Portal check → Run now" retries
detection. The copied URL can be pasted into a browser; the automatic browser
opening is unchanged.

```bash
omarchy-shell captive open     # reopen the sign-in page
omarchy-shell captive check    # force a probe now
omarchy-shell captive status   # connectivity, SSID, pending portal
omarchy-shell captive statusJson # structured status for the Wi-Fi widget
```

## How it works

NetworkManager signals when a network connects but is not carrying traffic,
triggering a probe against `captive.apple.com` to check whether the connection
is being intercepted. When the network allows that check through but
NetworkManager still reports limited connectivity, the plugin also probes
`ping.archlinux.org/nm-check.txt`. A redirect or intercepted response yields
the portal's sign-in URL, which the plugin opens.

If a portal does not load, DNS is worth checking. Portals redirect by
intercepting DNS, so a pinned public resolver can stop that from working.
`omarchy dns DHCP` restores DNS from the network being joined.

## What it does on your system

- Requests `http://captive.apple.com/hotspot-detect.html` when connectivity is
  not full, and may request `http://ping.archlinux.org/nm-check.txt` when
  NetworkManager suspects a portal, to detect interception and read the URL
- Launches a centered sign-in browser window in a throwaway profile under
  `$XDG_RUNTIME_DIR`, removed when the window closes. Browsers it does not
  recognize are opened with `xdg-open`, which uses your normal session
- Sends desktop notifications through `notify-send`
- Replaces the stock network dropdown with a bundled copy of Omarchy's network
  widget. Its source is MIT-licensed; see `NETWORK-WIDGET-LICENSE`.

It requires no elevated privileges and installs no separate system service.
Enabling a bar widget updates the user's Omarchy shell configuration as usual.

## Uninstalling

```bash
omarchy plugin remove io.github.zachfleeman.captive
```

## Development

```bash
tests/detect-portal.sh
omarchy plugin validate .
```

## License

MIT. `Panel.qml` and `Model.js` also carry Omarchy's MIT notice in
`NETWORK-WIDGET-LICENSE`.
