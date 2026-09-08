// SPDX-License-Identifier: LGPL-2.0-or-later
//
// The "charge this device / charge the other device" choice Android offers
// when a USB-C cable is plugged in, as a Plasma Mobile quick setting.
//
// Plain QML plus a shell script, like the location tile: no build step. The
// work happens in `usb-power-switch`, called through the executable data
// engine; this file only shows the state and asks for the other one.
import QtQuick

import org.kde.plasma.private.mobileshell.quicksettingsplugin as QS
import org.kde.plasma.plasma5support as P5Support

QS.QuickSetting {
    id: root

    // "none" (no partner), "source", "sink charging" or "sink idle": the
    // tokens the switch prints, verbatim.
    property string state: "none"

    readonly property bool giving: state === "source"
    readonly property bool cable: state !== "none"

    text: i18n("USB power")
    status: {
        if (!root.cable) {
            return i18n("No cable");
        }
        if (root.giving) {
            return i18n("Giving power");
        }
        if (root.state === "sink charging") {
            return i18n("Charging");
        }
        return i18n("Taking power");
    }
    // Lit when the phone is the one paying: that is the state worth noticing.
    icon: root.giving ? "battery-060-symbolic" : "battery-charging-symbolic"
    enabled: root.giving
    available: true

    P5Support.DataSource {
        id: exec

        engine: "executable"
        connectedSources: []

        onNewData: (source, data) => {
            // Always disconnect: the executable engine keeps the source alive
            // otherwise, and repeated polling then leaks one entry per tick.
            disconnectSource(source);

            if (source.indexOf("status") === -1) {
                // A write returns nothing useful, and a swap the partner
                // refuses returns an error. Re-read instead of assuming.
                settle.restart();
                return;
            }

            root.state = (data["stdout"] || "").trim();
        }

        // @SWITCH@ is replaced by the installer with the absolute path: the
        // executable engine does not expand variables, and plasmashell's PATH
        // does not include ~/.local/bin.
        function run(arg: string): void {
            connectSource("@SWITCH@ " + arg);
        }
    }

    // Polling, because a role swap is negotiated by the kernel with the other
    // end and nothing tells QML about it without a compiled plugin.
    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.run("status")
    }

    // A power role swap takes the partner a moment to honour; reading back at
    // once shows the OLD role and makes the tile flicker.
    Timer {
        id: settle
        interval: 1500
        onTriggered: exec.run("status")
    }

    function toggle(): void {
        if (!root.cable) {
            return;
        }
        exec.run(root.giving ? "sink" : "source");
    }
}
