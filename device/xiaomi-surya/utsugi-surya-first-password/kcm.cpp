// SPDX-License-Identifier: GPL-2.0-or-later
//
// The System Settings module. It is the same encryption assistant the first-boot
// step offers, reachable again for anyone who chose "Not now" then: it exposes
// the same Encrypt backend the standalone app uses, so the two front-ends run
// exactly the same pkexec-to-initramfs path and cannot drift.
//
// There is no save() and no needsSave: encrypting is a one-shot action the user
// takes with a button, not a form, so the KCM shows no Apply button.

#include "encrypt.h"

#include <KPluginFactory>
#include <KQuickConfigModule>

class KCMPhoneEncryption : public KQuickConfigModule
{
	Q_OBJECT

	Q_PROPERTY(Encrypt *encrypt READ encrypt CONSTANT)

public:
	KCMPhoneEncryption(QObject *parent, const KPluginMetaData &data)
	    : KQuickConfigModule(parent, data)
	    , m_encrypt(new Encrypt(this))
	{
	}

	Encrypt *encrypt() const { return m_encrypt; }

private:
	Encrypt *const m_encrypt;
};

K_PLUGIN_CLASS_WITH_JSON(KCMPhoneEncryption, "kcm_phone_encryption.json")

#include "kcm.moc"
