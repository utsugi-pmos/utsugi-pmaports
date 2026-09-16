// SPDX-License-Identifier: GPL-2.0-or-later
//
// Phone encryption, in Settings › Security & Privacy. The same assistant the first-boot step
// shows, for anyone who chose "Not now" then and wants it now. It drives the
// same Encrypt backend (kcm.encrypt), so the pkexec-to-initramfs path is
// identical -- on "Encrypt and restart" the phone reboots and encrypts itself
// in place before the root is mounted.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
	id: root

	property bool working: false
	property string error: ""

	// The system half writes this every boot while the disk is NOT encrypted
	// (utsugi-surya-encrypt's is-the-disk-encrypted.service), and removes it once
	// it is. So it is a live answer, not just a first-boot flag.
	readonly property bool notEncrypted: kcm.encrypt.exists("/run/utsugi-surya/disk-is-not-encrypted")

	function applyEncryption(first, second) {
		if (working)
			return;
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
		root.error = kcm.encrypt.request(first.text);
		root.working = false;
		if (root.error !== "") {
			first.text = "";
			second.text = "";
			first.forceActiveFocus();
		}
	}

	// Already encrypted: nothing to do, say so plainly.
	ColumnLayout {
		anchors.centerIn: parent
		width: parent.width - Kirigami.Units.gridUnit * 2
		spacing: Kirigami.Units.largeSpacing
		visible: !root.notEncrypted

		Kirigami.Icon {
			source: "object-locked"
			Layout.alignment: Qt.AlignHCenter
			Layout.preferredWidth: Kirigami.Units.iconSizes.large
			Layout.preferredHeight: Kirigami.Units.iconSizes.large
		}
		Kirigami.Heading {
			text: "This phone is encrypted"
			level: 2
			horizontalAlignment: Text.AlignHCenter
			Layout.fillWidth: true
		}
		QQC2.Label {
			text: "Its storage is unreadable without the passphrase you set. "
			    + "Change that passphrase from a terminal with cryptsetup."
			wrapMode: Text.Wrap
			horizontalAlignment: Text.AlignHCenter
			opacity: 0.7
			Layout.fillWidth: true
		}
	}

	// Not encrypted: the assistant.
	ColumnLayout {
		anchors.top: parent.top
		anchors.topMargin: Kirigami.Units.gridUnit
		anchors.horizontalCenter: parent.horizontalCenter
		width: parent.width - Kirigami.Units.gridUnit * 2
		spacing: Kirigami.Units.largeSpacing
		visible: root.notEncrypted

		Kirigami.Icon {
			source: "object-unlocked"
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
	}
}
