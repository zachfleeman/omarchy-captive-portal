import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

// Detects captive portals and opens the sign-in page.
Item {
  id: root

  property var shell: null

  property bool autoOpenBrowser: true
  property bool notify: true
  property string probeUrl: "http://captive.apple.com/hotspot-detect.html"
  property string fallbackProbeUrl: "http://ping.archlinux.org/nm-check.txt"
  property int settleMs: 2500
  property int recheckMs: 8000

  readonly property string detectScript:
    Qt.resolvedUrl("detect-portal.sh").toString().replace(/^file:\/\//, "")

  readonly property string openScript:
    Qt.resolvedUrl("open-portal.sh").toString().replace(/^file:\/\//, "")

  readonly property int connectivity: Networking.connectivity

  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []

  readonly property bool suspect:
    connectivity === NetworkConnectivity.Portal
    || connectivity === NetworkConnectivity.None
    || connectivity === NetworkConnectivity.Limited

  property string handledUrl: ""
  property string handledSsid: ""
  property bool announcedOnline: true

  // SSID of the connected Wi-Fi network
  readonly property string ssid: {
    var device = findDevice(DeviceType.Wifi)
    if (!device) return ""
    var networks = device.networks ? device.networks.values : []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected) return networks[i].name || ""
    }
    return ""
  }

  // Returns the connected device of the given type, or any device of it.
  function findDevice(type) {
    var devices = networkDevices || []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }

  function log(message) {
    console.log("[captive] " + message)
  }

  // Runs the probe script; its output routes to onPortalFound or onNoPortal.
  function probe(force) {
    if (detectProcess.running) return
    detectProcess.command = [
      "bash", root.detectScript, root.probeUrl,
      force === true || root.suspect ? "suspect" : "confirm",
      root.fallbackProbeUrl
    ]
    detectProcess.running = true
  }

  // Notifies and opens the sign-in page for a newly seen portal.
  function onPortalFound(url) {
    if (url === "" || url === handledUrl) {
      recheckTimer.restart()
      return
    }

    handledUrl = url
    handledSsid = ssid
    announcedOnline = false
    log("portal detected on " + (ssid || "Wi-Fi"))

    if (notify) {
      notifyProcess.command = [
        "notify-send",
        "-a", "Captive Portal",
        "-u", "critical",
        root.ssid !== "" ? "Sign in to " + root.ssid : "Sign in to Wi-Fi",
        "This network requires you to sign in"
      ]
      notifyProcess.running = true
    }

    if (autoOpenBrowser) {
      browserProcess.command = ["bash", root.openScript, url]
      browserProcess.running = true
    }

    recheckTimer.restart()
  }

  // Reports a solved portal, but only for one found on the current network.
  function onNoPortal() {
    if (suspect) {
      recheckTimer.restart()
    } else {
      recheckTimer.stop()

      if (connectivity === NetworkConnectivity.Full
          && handledUrl !== ""
          && handledSsid === ssid
          && !announcedOnline) {
        announcedOnline = true
        handledUrl = ""
        handledSsid = ""
        if (notify) {
          notifyProcess.command = [
            "notify-send",
            "-a", "Captive Portal",
            "Connected",
            "Sign-in complete. This network is online."
          ]
          notifyProcess.running = true
        }
      }
    }
  }

  onConnectivityChanged: {
    log("connectivity: " + NetworkConnectivity.toString(connectivity))
    if (suspect) {
      settleTimer.restart()
    } else {
      handledUrl === "" ? recheckTimer.stop() : probe()
    }
  }

  // Roaming to another network retires a pending portal without a word.
  onSsidChanged: {
    if (handledUrl !== "" && handledSsid !== "" && handledSsid !== ssid) {
      log("left " + handledSsid + " with its portal unsolved; dropping it")
      handledUrl = ""
      handledSsid = ""
      announcedOnline = true
      recheckTimer.stop()
    }
    if (ssid !== "" && suspect) settleTimer.restart()
  }

  Timer {
    id: settleTimer
    interval: root.settleMs
    repeat: false
    onTriggered: root.probe()
  }

  Timer {
    id: recheckTimer
    interval: root.recheckMs
    repeat: true
    onTriggered: {
      Networking.checkConnectivity()
      root.probe()
    }
  }

  Process {
    id: detectProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var url = text.trim()
        if (url !== "") root.onPortalFound(url)
        else root.onNoPortal()
      }
    }
  }

  Process { id: notifyProcess }
  Process { id: browserProcess }
  Process { id: windowRuleProcess }

  IpcHandler {
    target: "captive"

    // Forces a probe regardless of the current connectivity verdict.
    function check(): void { root.handledUrl = ""; root.probe(true) }

    // Reopens the sign-in page; portal sessions expire constantly.
    function open(): void {
      var url = root.handledUrl !== "" ? root.handledUrl : "http://neverssl.com/"
      browserProcess.command = ["bash", root.openScript, url]
      browserProcess.running = true
    }

    // Reports connectivity, SSID and any pending portal URL.
    function status(): string {
      return NetworkConnectivity.toString(root.connectivity)
        + (root.ssid !== "" ? " ssid=" + root.ssid : "")
        + (root.handledUrl !== "" ? " portal=" + root.handledUrl : "")
    }

    // Structured state for the bundled Wi-Fi widget. Only expose a portal
    // while it belongs to the current SSID and sign-in is still pending.
    function statusJson(): string {
      var pending = root.handledUrl !== ""
        && root.handledSsid === root.ssid
        && root.connectivity !== NetworkConnectivity.Full
      return JSON.stringify({
        connectivity: NetworkConnectivity.toString(root.connectivity),
        ssid: root.ssid,
        url: pending ? root.handledUrl : "",
        redirected: pending && root.handledUrl !== root.probeUrl
          && root.handledUrl !== root.fallbackProbeUrl
      })
    }
  }

  // Floats the sign-in window; its app id ends in the profile set by open-portal.sh.
  function registerWindowRule() {
    windowRuleProcess.command = [
      "hyprctl", "eval",
      'o.window(".*-omarchy-captive$", { tag = "+floating-window" })'
    ]
    windowRuleProcess.running = true
  }

  Component.onCompleted: {
    registerWindowRule()
    if (suspect) settleTimer.restart()
  }
}
