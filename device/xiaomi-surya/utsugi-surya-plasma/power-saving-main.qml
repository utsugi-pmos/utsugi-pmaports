// SPDX-License-Identifier: LGPL-2.0-or-later
//
// The power saving quick setting Plasma Mobile does not ship.
//
// This file is deliberately thin: it shows the profile and it sets the
// profile. Nothing else. Brightness and the idle timeouts are handled by
// power-saving-agent, a session unit, because Plasma Mobile instantiates a
// quick setting's QML only when the panel is pulled down -- so the tile is
// not alive to react to anything, and side effects put here silently never
// happened. That was measured, not assumed; see power-saving-agent.
//
// Unlike the location tile next door, there is no polling here either. Plasma
// already has a QML type that tracks the profile daemon with change signals --
// PowerProfilesControl, the same one the desktop battery applet uses -- so the
// state is pushed. That also keeps the tile correct when the profile is
// changed from System Settings or over ssh, which a poll would only catch on
// its next tick.
import QtQuick

import org.kde.plasma.private.mobileshell.quicksettingsplugin as QS
import org.kde.plasma.private.batterymonitor as BatteryMonitor

QS.QuickSetting {
    id: root

    // Profile names as tuned-ppd reports them on this phone; checked against
    // the Profiles property of net.hadess.PowerProfiles, which lists exactly
    // power-saver, balanced and performance.
    readonly property string savingProfile: "power-saver"
    readonly property string normalProfile: "balanced"

    BatteryMonitor.PowerProfilesControl {
        id: power
    }

    readonly property bool saving: power.activeProfile === root.savingProfile

    text: i18n("Power Saving")

    status: {
        if (!root.saving) {
            return i18n("Off");
        }
        // The daemon reports when it cannot deliver the profile it was asked
        // for -- thermal throttling is the usual reason. Saying so beats a
        // tile that claims to be saving power while the SoC is on fire.
        if (power.degradationReason) {
            return i18n("On, degraded");
        }
        return i18n("On");
    }

    icon: root.saving ? "battery-profile-powersave-symbolic"
                      : "battery-profile-balanced-symbolic"

    enabled: root.saving

    // Hide the tile outright if no profile daemon is answering, rather than
    // showing a switch that silently does nothing.
    available: power.isPowerProfileDaemonInstalled

    function toggle(): void {
        power.setProfile(root.saving ? root.normalProfile : root.savingProfile);
    }
}
