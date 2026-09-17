// SPDX-License-Identifier: GPL-2.0-or-later
//
// Full screen and with no way out, on purpose. A notification can be swiped
// away and forgotten, and this phone's shipped password is printed on a public
// web page: anybody who read it knows the password of a phone nobody changed.
// So it is a step, not a suggestion.
//
// Two steps, each shown only when the system half says it applies:
//   /run/utsugi-surya/password-is-default    -> choose a password
//   /run/utsugi-surya/offer-encryption       -> encrypt the phone, or not
// The second is optional and can be declined for good. The first cannot.
//
// Between them, after the password, a welcome page with Finish and Advanced
// setup (full name, the phone's name, PIN or password). Encryption comes LAST
// because accepting it reboots the phone on the spot: anything placed after it
// would never be seen.
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
    Identity { id: identity }

    // The password chosen in the first step, kept in memory only, so the
    // Advanced setup can change it again without asking for it.
    property string currentPassword: ""

    // A new user name waits for a restart: the account is renamed at boot,
    // before the session starts.
    property bool restartToRename: false

    function done() {
        if (restartToRename) {
            identity.reboot();
        } else {
            Qt.quit();
        }
    }

    readonly property string supportUrl: "https://utsugi-pmos.github.io/utsugi-pmaports/"

    function isPin(text) {
        return /^[0-9]+$/.test(text);
    }

    readonly property bool needPassword: encrypt.exists("/run/utsugi-surya/password-is-default")
    readonly property bool offerEncryption: encrypt.exists("/run/utsugi-surya/offer-encryption")

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

    // After the welcome (or the Advanced setup): on to encryption if it
    // applies, otherwise done.
    function next() {
        root.error = "";
        if (offerEncryption) {
            pageStack.replace(encryptPage);
        } else {
            root.done();
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
            root.currentPassword = first.text;
            // Letters in it: the lock screen has to open on the keyboard, or
            // the first unlock is a number pad that cannot type the password.
            identity.setUnlockWithKeyboard(!root.isPin(first.text));
            pageStack.replace(welcomePage);
        } else {
            first.text = "";
            second.text = "";
            first.forceActiveFocus();
        }
    }

    function applyAdvanced(userName, realName, hostname, advancedPassword, first, second) {
        if (working) {
            return;
        }
        root.error = "";
        const kindChanged = advancedPassword === root.isPin(root.currentPassword);
        if (first.text === "" && second.text === "" && kindChanged) {
            root.error = advancedPassword
                ? "Type the password you want. The PIN you chose has only numbers."
                : "Type the PIN you want. The password you chose is not only numbers.";
            first.forceActiveFocus();
            return;
        }
        if (first.text !== "" || second.text !== "") {
            if (!advancedPassword && !root.isPin(first.text)) {
                root.error = "A PIN is numbers only.";
                return;
            }
            if (!advancedPassword && first.text.length < 4) {
                root.error = "Use at least 4 numbers.";
                return;
            }
            if (advancedPassword && first.text.length < 6) {
                root.error = "Use at least 6 characters.";
                return;
            }
            if (first.text !== second.text) {
                root.error = "The two do not match.";
                second.text = "";
                second.forceActiveFocus();
                return;
            }
        }

        root.working = true;
        root.error = identity.apply(realName, hostname, userName);
        if (root.error === "") {
            root.restartToRename = userName.trim() !== identity.userName;
        }
        if (root.error === "" && first.text !== "") {
            root.error = passwd.changeFrom(root.currentPassword, first.text);
            if (root.error === "") {
                root.currentPassword = first.text;
            }
        }
        root.working = false;
        if (root.error !== "") {
            return;
        }
        identity.setUnlockWithKeyboard(advancedPassword);
        root.next();
    }

    function applyEncryption(first, second) {
        if (working) {
            return;
        }
        if (first.text.length < 4) {
            root.error = "Use at least 4 characters. You will type this at every start.";
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
            root.done();
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

    // ----------------------------------------------------------------- welcome
    Component {
        id: welcomePage
        Kirigami.Page {
            ColumnLayout {
                anchors.top: parent.top
                anchors.topMargin: Kirigami.Units.gridUnit * 3
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Kirigami.Units.gridUnit * 2
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "face-smile"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                    Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                }
                Kirigami.Heading {
                    text: "Welcome to Utsugi Ports"
                    level: 1
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: "Your phone is ready. If something does not work or you need "
                        + "help, visit the website:"
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.8
                    Layout.fillWidth: true
                }
                // Text, not a link: opening the browser here would put it over
                // this window, and the steps would carry on behind it unseen.
                QQC2.Label {
                    text: root.supportUrl
                    wrapMode: Text.WrapAnywhere
                    horizontalAlignment: Text.AlignHCenter
                    font.bold: true
                    Layout.fillWidth: true
                }
                Item { Layout.preferredHeight: Kirigami.Units.gridUnit }
                QQC2.Button {
                    text: "Finish"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                    onClicked: root.next()
                }
                QQC2.Button {
                    text: "Advanced setup"
                    flat: true
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                    onClicked: {
                        root.error = "";
                        pageStack.push(advancedPage);
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- advanced
    Component {
        id: advancedPage
        Kirigami.ScrollablePage {
            // Scrollable: with the keyboard up, the fields and the buttons do
            // not fit in what is left of the screen.
            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Heading {
                    text: "Advanced setup"
                    level: 1
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.gridUnit
                }

                QQC2.Label {
                    text: "User name"
                    opacity: 0.75
                    Layout.fillWidth: true
                }
                QQC2.TextField {
                    id: userNameField
                    text: identity.userName
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhLowercaseOnly | Qt.ImhNoPredictiveText
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                    onAccepted: realNameField.forceActiveFocus()
                }
                QQC2.Label {
                    text: userNameField.text.trim() !== identity.userName
                        ? "Your folder becomes /home/" + userNameField.text.trim()
                          + ". The phone restarts when you finish, to rename it."
                        : "Lowercase letters, numbers, - and _. Also the name for sudo and ssh."
                    wrapMode: Text.Wrap
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                    Layout.fillWidth: true
                }

                QQC2.Label {
                    text: "Full name"
                    opacity: 0.75
                    Layout.fillWidth: true
                }
                QQC2.TextField {
                    id: realNameField
                    text: identity.realName
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                    onAccepted: hostnameField.forceActiveFocus()
                }

                QQC2.Label {
                    text: "Phone name"
                    opacity: 0.75
                    Layout.fillWidth: true
                }
                QQC2.TextField {
                    id: hostnameField
                    text: identity.hostname
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhLowercaseOnly | Qt.ImhNoPredictiveText
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                }
                QQC2.Label {
                    text: "How the phone shows up on your network and over Bluetooth. "
                        + "Lowercase letters, numbers and hyphens."
                    wrapMode: Text.Wrap
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                    Layout.fillWidth: true
                }

                QQC2.Label {
                    text: "Unlock with"
                    opacity: 0.75
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.largeSpacing
                }
                QQC2.RadioButton {
                    id: simpleNumber
                    text: "Simple number"
                    checked: root.isPin(root.currentPassword)
                    Layout.fillWidth: true
                    onToggled: {
                        pwFirstAdv.text = "";
                        pwSecondAdv.text = "";
                    }
                }
                QQC2.RadioButton {
                    id: advancedPassword
                    text: "Advanced"
                    checked: !root.isPin(root.currentPassword)
                    Layout.fillWidth: true
                    onToggled: {
                        pwFirstAdv.text = "";
                        pwSecondAdv.text = "";
                        // Straight to the letters keyboard: that is the point
                        // of choosing a password.
                        pwFirstAdv.forceActiveFocus();
                    }
                }
                QQC2.Label {
                    text: advancedPassword.checked
                        ? "Letters, numbers and symbols, at least 6. The lock screen will open on the keyboard."
                        : "Numbers only, at least 4. The lock screen opens on the number pad."
                    wrapMode: Text.Wrap
                    opacity: 0.6
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                    Layout.fillWidth: true
                }
                QQC2.TextField {
                    id: pwFirstAdv
                    echoMode: TextInput.Password
                    placeholderText: advancedPassword.checked === !root.isPin(root.currentPassword)
                        ? "New one (empty keeps the current)" : "New one"
                    inputMethodHints: advancedPassword.checked ? Qt.ImhHiddenText | Qt.ImhNoPredictiveText
                                                               : Qt.ImhDigitsOnly
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                    onAccepted: pwSecondAdv.forceActiveFocus()
                }
                QQC2.TextField {
                    id: pwSecondAdv
                    echoMode: TextInput.Password
                    placeholderText: "Type it again"
                    inputMethodHints: pwFirstAdv.inputMethodHints
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
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
                    text: root.working ? "Saving…" : "Save and finish"
                    enabled: !root.working
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                    onClicked: root.applyAdvanced(userNameField.text, realNameField.text, hostnameField.text,
                                                  advancedPassword.checked, pwFirstAdv, pwSecondAdv)
                }
                QQC2.Button {
                    text: "Back"
                    flat: true
                    enabled: !root.working
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                    onClicked: {
                        root.error = "";
                        pageStack.pop();
                    }
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
                        + "phone is a brick with your things inside. Four characters are "
                        + "allowed; a thief with the phone can try them all, so longer is safer."
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
                    text: "\"Not now\" does not ask again here, but it is not final: "
                        + "you can encrypt later from Settings › Security & Privacy › Phone encryption."
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
