// SPDX-License-Identifier: GPL-2.0-or-later

#include "identity.h"

#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QSysInfo>

#include <pwd.h>
#include <unistd.h>

static const char *HELPER = "/usr/libexec/utsugi-surya/set-identity";

QString Identity::realName() const
{
    const passwd *pw = getpwuid(getuid());
    if (!pw || !pw->pw_gecos) {
        return QString();
    }
    // GECOS is "Full Name,room,phone,...": only the first field is the name.
    return QString::fromUtf8(pw->pw_gecos).section(QLatin1Char(','), 0, 0);
}

QString Identity::hostname() const
{
    return QSysInfo::machineHostName();
}

QString Identity::userName() const
{
    const passwd *pw = getpwuid(getuid());
    return pw ? QString::fromUtf8(pw->pw_name) : QString();
}

void Identity::reboot()
{
    // logind lets the person at the phone restart it without a password.
    QProcess::startDetached(QStringLiteral("systemctl"), {QStringLiteral("reboot")});
}

QString Identity::apply(const QString &newRealName, const QString &newHostname, const QString &newUserName)
{
    QStringList args;
    if (newUserName.trimmed() != userName()) {
        args << QStringLiteral("--user-name") << newUserName.trimmed();
    }
    if (newRealName.trimmed() != realName()) {
        args << QStringLiteral("--real-name") << newRealName.trimmed();
    }
    if (newHostname.trimmed() != hostname()) {
        args << QStringLiteral("--hostname") << newHostname.trimmed();
    }
    if (args.isEmpty()) {
        return QString();
    }

    QProcess p;
    p.start(QStringLiteral("pkexec"), QStringList{QString::fromLatin1(HELPER)} + args);
    if (!p.waitForStarted(5000)) {
        return QStringLiteral("Could not start the helper.");
    }
    if (!p.waitForFinished(30000)) {
        p.kill();
        return QStringLiteral("The phone did not answer in time.");
    }
    if (p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0) {
        return QString();
    }
    if (p.exitCode() == 126 || p.exitCode() == 127) {
        return QStringLiteral("Not allowed to change the names on this account.");
    }
    const QString err = QString::fromUtf8(p.readAllStandardError()).trimmed();
    return err.isEmpty() ? QStringLiteral("The names could not be changed.") : err.section(QLatin1Char('\n'), -1);
}

void Identity::setUnlockWithKeyboard(bool keyboard)
{
    // [General] with no group call: QSettings maps its default section to a
    // plain [General], which is what the lock screen reads with Qt's Settings
    // type and no category.
    QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                           + QStringLiteral("/utsugi-lockscreenrc"),
                       QSettings::IniFormat);
    settings.setValue(QStringLiteral("startWithKeyboard"), keyboard);
    settings.sync();
}
