// SPDX-License-Identifier: GPL-2.0-or-later
//
// Full screen and with no way out, on purpose. A notification can be swiped
// away and forgotten, and this phone's shipped password is printed on a public
// web page: anybody who read it knows the password of a phone nobody changed.
// So it is a step, not a suggestion.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.utsugi.firstpassword

Kirigami.ApplicationWindow {
    id: root

    title: "Choose a password"
    visibility: Window.FullScreen
    // No title bar to close from, and Escape does nothing.
    flags: Qt.Window | Qt.FramelessWindowHint

    property string error: ""
    property bool working: false

    Passwd { id: passwd }

    function apply() {
        if (working) {
            return;
        }
        if (first.text !== second.text) {
            root.error = "The two do not match.";
            second.text = "";
            second.forceActiveFocus();
            return;
        }
        root.working = true;
        root.error = passwd.change(first.text);
        root.working = false;
        if (root.error === "") {
            // Nothing to save and nowhere to go: the flag this window was
            // started for lives in /run and the check that wrote it will not
            // match any more. Leaving is the whole of "done".
            Qt.quit();
        } else {
            first.text = "";
            second.text = "";
            first.forceActiveFocus();
        }
    }

    pageStack.initialPage: Kirigami.Page {
        title: "Choose a password"

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Kirigami.Units.gridUnit * 2,
                            Kirigami.Units.gridUnit * 22)
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: "security-medium"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                Layout.preferredHeight: Kirigami.Units.iconSizes.huge
            }

            Kirigami.Heading {
                text: "This phone still has the password it came with"
                level: 2
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            QQC2.Label {
                text: "It is written on the page you downloaded the image from, "
                    + "so it is not a secret. Pick your own before anything else."
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.8
                Layout.fillWidth: true
            }

            QQC2.TextField {
                id: first
                echoMode: TextInput.Password
                placeholderText: "New password"
                Layout.fillWidth: true
                onAccepted: second.forceActiveFocus()
                focus: true
            }

            QQC2.TextField {
                id: second
                echoMode: TextInput.Password
                placeholderText: "Again"
                Layout.fillWidth: true
                onAccepted: root.apply()
            }

            QQC2.Label {
                text: root.error
                visible: root.error !== ""
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            QQC2.Button {
                text: root.working ? "Changing…" : "Set password"
                enabled: !root.working && first.text.length > 0 && second.text.length > 0
                Layout.fillWidth: true
                onClicked: root.apply()
            }
        }
    }
}
