#include "encrypt.h"
#include <QFileInfo>
#include <QProcess>

static const char *HELPER = "/usr/libexec/utsugi-surya/request-encryption";

bool Encrypt::exists(const QString &path) const
{
    return QFileInfo::exists(path);
}

static QString run(const QStringList &args, const QString &stdinText)
{
    QProcess p;
    // pkexec keeps stdin and stderr attached when the polkit rule answers YES
    // without a prompt, which it does for the phone's own user. The passphrase
    // goes over that pipe and nowhere else: not on the command line, where
    // anybody on the system could read it from /proc.
    p.start(QStringLiteral("pkexec"), QStringList{QString::fromLatin1(HELPER)} + args);
    if (!p.waitForStarted(5000)) {
        return QStringLiteral("Could not start the helper.");
    }
    if (!stdinText.isEmpty()) {
        p.write(stdinText.toUtf8());
        p.write("\n");
    }
    p.closeWriteChannel();
    // The helper's last act on success is 'systemctl reboot', so a successful
    // call may never return here. That is fine: the window dies with the
    // session.
    if (!p.waitForFinished(30000)) {
        return QString();
    }
    if (p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0) {
        return QString();
    }
    const QString err = QString::fromUtf8(p.readAllStandardError()).trimmed();
    if (p.exitCode() == 126 || p.exitCode() == 127) {
        return QStringLiteral("Not allowed to ask for encryption on this account.");
    }
    return err.isEmpty() ? QStringLiteral("The request failed.") : err.section(QLatin1Char('\n'), -1);
}

QString Encrypt::request(const QString &passphrase)
{
    return run({}, passphrase);
}

QString Encrypt::decline()
{
    return run({QStringLiteral("--decline")}, QString());
}
