#pragma once
#include <QObject>
#include <QString>

/*
 * The encryption half of the first-boot step. It does nothing itself: it asks
 * root, through pkexec, to write the passphrase where the initramfs will find
 * it and to reboot. The work happens at the next boot, before the root
 * filesystem is mounted, which is the only time it can happen.
 *
 * exists() is here so the QML can ask which of the two steps to show without
 * a second helper type: the flags in /run are what the system half decided.
 */
class Encrypt : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE bool exists(const QString &path) const;
    /* Empty string on success; otherwise a sentence for the screen. */
    Q_INVOKABLE QString request(const QString &passphrase);
    Q_INVOKABLE QString decline();
};
