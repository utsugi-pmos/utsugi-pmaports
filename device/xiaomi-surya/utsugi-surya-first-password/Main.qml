// SPDX-License-Identifier: GPL-2.0-or-later
//
// Full screen and with no way out, on purpose. A notification can be swiped
// away and forgotten, and this phone's shipped password is printed on a public
// web page: anybody who read it knows the password of a phone nobody changed.
// So it is a step, not a suggestion.
//
// Two steps, each shown only when the system half says it applies:
//   /run/utsugi-surya/password-is-default    -> choose a password
//   /run/utsugi-surya/disk-is-not-encrypted  -> encrypt the phone, or not
// The second is optional and can be declined for good. The first cannot.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.utsugi.firstpassword

Kirigami.ApplicationWindow {
    id: root

    title: "First steps"
    visibility: Window.FullScreen
    // No title bar to close from, and Escape does nothing.
    flags: Qt.Window | Qt.FramelessWindowHint

    property string error: ""
    property bool working: false

    Passwd { id: passwd }
    Encrypt { id: encrypt }

    readonly property bool needPassword: encrypt.exists("/run/utsugi-surya/password-is-default")
    readonly property bool offerEncryption: encrypt.exists("/run/utsugi-surya/disk-is-not-encrypted")

    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    Component.onCompleted: {
        if (needPassword) {
            pageStack.push(passwordPage);
        } else if (offerEncryption) {
            pageStack.push(encryptPage);
        } else {
            Qt.quit();
        }
    }

    // After the password: on to encryption if it applies, otherwise done.
    function next() {
        root.error = "";
        if (offerEncryption) {
            pageStack.replace(encryptPage);
        } else {
            Qt.quit();
        }
    }

    function applyPassword(first, second) {
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
            root.next();
        } else {
            first.text = "";
            second.text = "";
            first.forceActiveFocus();
        }
    }

    function applyEncryption(first, second) {
        if (working) {
            return;
        }
        if (first.text.length < 8) {
            root.error = "Use at least 8 characters. You will type this at every start.";
            return;
        }
        if (first.text !== second.text) {
            root.error = "The two do not match.";
            second.text = "";
            second.forceActiveFocus();
            return;
        }
        root.working = true;
        // On success the helper reboots the phone and this never returns.
        root.error = encrypt.request(first.text);
        root.working = false;
        if (root.error !== "") {
            first.text = "";
            second.text = "";
            first.forceActiveFocus();
        }
    }

    function declineEncryption() {
        root.working = true;
        root.error = encrypt.decline();
        root.working = false;
        if (root.error === "") {
            Qt.quit();
        }
    }

    // ---------------------------------------------------------------- password
    Component {
        id: passwordPage
        Kirigami.Page {
            ColumnLayout {
                // Anchored to the TOP, not centred: the on-screen keyboard
                // takes the bottom half of the panel the moment a field has
                // focus, and a centred column puts the fields and the button
                // exactly there. Everything that has to be read or touched
                // lives in the top half.
                anchors.top: parent.top
                anchors.topMargin: Kirigami.Units.gridUnit
                anchors.horizontalCenter: parent.horizontalCenter
                // Nearly the whole width, and generous spacing. The default
                // control sizes are made for a pointer; on this panel -- 1080
                // wide, held at arm's length -- they come out as a row of thin
                // slots that are hard to hit and harder to read.
                width: parent.width - Kirigami.Units.gridUnit * 2
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "security-medium"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                }
                Kirigami.Heading {
                    text: "This phone still has the password it came with"
                    level: 1
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
                QQC2.Label {
                    text: "A 4-digit PIN is fine. It is also the password for "
                        + "sudo and for ssh, if you ever use them."
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: "New password"
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    opacity: 0.75
                }
                QQC2.TextField {
                    id: pwFirst
                    echoMode: TextInput.Password
                    // A finger, not a mouse pointer: Kirigami's own touch target.
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
                    horizontalAlignment: TextInput.AlignHCenter
                    onAccepted: pwSecond.forceActiveFocus()
                    focus: true
                }
                QQC2.Label {
                    text: "Type it again"
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    opacity: 0.75
                }
                QQC2.TextField {
                    id: pwSecond
                    echoMode: TextInput.Password
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
                    horizontalAlignment: TextInput.AlignHCenter
                    onAccepted: root.applyPassword(pwFirst, pwSecond)
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
                    enabled: !root.working && pwFirst.text.length > 0 && pwSecond.text.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                    onClicked: root.applyPassword(pwFirst, pwSecond)
                }
            }
        }
    }

    // -------------------------------------------------------------- encryption
    Component {
        id: encryptPage
        Kirigami.Page {
            ColumnLayout {
                anchors.top: parent.top
                anchors.topMargin: Kirigami.Units.gridUnit
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Kirigami.Units.gridUnit * 2
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "object-locked"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Kirigami.Units.iconSizes.large
                    Layout.preferredHeight: Kirigami.Units.iconSizes.large
                }
                Kirigami.Heading {
                    text: "Encrypt this phone?"
                    level: 1
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: "Everything on it becomes unreadable without a passphrase, "
                        + "which you will type on the screen at every start, before "
                        + "the PIN. It is done here, on the phone, at the next restart: "
                        + "plug the charger in, it takes a while, and do not turn it off."
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.8
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: "There is no way to recover it. Forget the passphrase and the "
                        + "phone is a brick with your things inside."
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: "Passphrase"
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    opacity: 0.75
                }
                QQC2.TextField {
                    id: encFirst
                    echoMode: TextInput.Password
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
                    horizontalAlignment: TextInput.AlignHCenter
                    onAccepted: encSecond.forceActiveFocus()
                    focus: true
                }
                QQC2.Label {
                    text: "Type it again"
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    opacity: 0.75
                }
                QQC2.TextField {
                    id: encSecond
                    echoMode: TextInput.Password
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
                    horizontalAlignment: TextInput.AlignHCenter
                    onAccepted: root.applyEncryption(encFirst, encSecond)
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
                    text: root.working ? "Restarting…" : "Encrypt and restart"
                    enabled: !root.working && encFirst.text.length > 0 && encSecond.text.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                    onClicked: root.applyEncryption(encFirst, encSecond)
                }
                QQC2.Button {
                    text: "Not now"
                    flat: true
                    enabled: !root.working
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                    onClicked: root.declineEncryption()
                }
                QQC2.Label {
                    text: "\"Not now\" is for good: the question will not come back. "
                        + "It can be done later from a terminal, see the install page."
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.5
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                    Layout.fillWidth: true
                }
            }
        }
    }
}
