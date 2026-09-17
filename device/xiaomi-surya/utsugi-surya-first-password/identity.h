// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QObject>
#include <QString>

/*
 * The Advanced setup's half that is not the password: the owner's full name,
 * the phone's name, and which keyboard the lock screen starts on.
 *
 * Names need root, so they go through pkexec to set-identity, like the
 * encryption request. The keyboard is the user's own setting and is written
 * here.
 */
class Identity : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString realName READ realName CONSTANT)
    Q_PROPERTY(QString hostname READ hostname CONSTANT)
    Q_PROPERTY(QString userName READ userName CONSTANT)

public:
    using QObject::QObject;

    QString realName() const;
    QString hostname() const;
    QString userName() const;

    /* Only what differs from the current values is sent. Empty string on
     * success; otherwise a sentence for the screen. A new user name is only
     * requested: it is applied at the next boot, see reboot(). */
    Q_INVOKABLE QString apply(const QString &realName, const QString &hostname, const QString &userName);

    /* The account is renamed before the session starts, so the phone has to
     * restart for it. */
    Q_INVOKABLE void reboot();

    /* true: the lock screen opens on the letters keyboard, for a password;
     * false: on the number pad, for a PIN. Read by the lock screen from
     * ~/.config/utsugi-lockscreenrc. */
    Q_INVOKABLE void setUnlockWithKeyboard(bool keyboard);
};
