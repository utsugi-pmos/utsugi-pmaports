// SPDX-License-Identifier: LGPL-2.0-or-later
//
// The location quick setting Plasma Mobile does not ship. Every stock quick
// setting is backed by a compiled C++ plugin; this one deliberately is not, so
// that it installs as plain data files with no build step. The work happens in
// `location-switch`, called through the executable data engine.
import QtQuick

import org.kde.plasma.private.mobileshell.quicksettingsplugin as QS
import org.kde.plasma.plasma5support as P5Support

QS.QuickSetting {
    id: root

    // Whether apps are ALLOWED to locate you, not whether the radio is hot.
    property bool allowed: false
    // Whether the GPS engine is drawing power right now.
    property bool gathering: false

    text: i18n("Location")
    status: !allowed ? i18n("Off")
                     : (gathering ? i18n("In use") : i18n("Allowed"))
    icon: allowed ? "gps-symbolic" : "find-location-symbolic"
    enabled: allowed
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
                // A write (on/off) returns nothing useful. Re-read instead of
                // assuming it worked, so the tile can never lie about state.
                settle.restart();
                return;
            }

            const out = (data["stdout"] || "").trim();
            root.allowed = out.indexOf("on") === 0;
            root.gathering = out.indexOf("gathering") !== -1;
        }

        // @SWITCH@ is replaced by the setting with the absolute path. It has to
        // be absolute: the executable engine does not expand variables, and
        // plasmashell's PATH does not include ~/.local/bin -- checked, it is
        // /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin.
        function run(arg: string): void {
            connectSource("@SWITCH@ " + arg);
        }
    }

    // Polling, because neither ModemManager nor the agent emits anything this
    // tile could subscribe to without a compiled plugin. 5 s is slow enough to
    // be free and fast enough that the tile is not visibly stale.
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.run("status")
    }

    // Killing the agent and disabling gathering are not instantaneous; reading
    // back immediately would show the OLD state and make the tile flicker.
    Timer {
        id: settle
        interval: 800
        onTriggered: exec.run("status")
    }

    function toggle(): void {
        exec.run(root.allowed ? "off" : "on");
    }
}
