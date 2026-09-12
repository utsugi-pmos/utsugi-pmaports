// SPDX-License-Identifier: GPL-2.0-or-later

#include "passwd.h"

#include <QDebug>

#include <cerrno>
#include <csignal>
#include <cstring>
#include <pty.h>
#include <sys/wait.h>
#include <unistd.h>

// The password the image ships with. It is on the install page too: this file
// is not where the secret lives, it is where the program learns what to answer
// the prompt with so the user does not have to type a password they were given
// rather than chose.
static const char *kShipped = "147147";

namespace
{

// passwd(1) refuses to read from a pipe -- it opens /dev/tty and would fail
// with "Authentication token manipulation error" -- so it gets a real terminal.
bool talkToPasswd(const QByteArray &newPassword, QByteArray *transcript)
{
    int master = -1;
    const pid_t pid = forkpty(&master, nullptr, nullptr, nullptr);
    if (pid < 0) {
        return false;
    }

    if (pid == 0) {
        // The child must not inherit a locale that translates the prompts: the
        // reply is timed against them only loosely, but a failure message is
        // easier to read in one language.
        setenv("LC_ALL", "C", 1);
        execlp("passwd", "passwd", nullptr);
        _exit(127);
    }

    // Answer every prompt in order: the old one first, then the new one twice.
    // passwd asks in that order and does not continue until each is answered,
    // so writing them one after another is enough; it echoes nothing back.
    const QByteArray replies[] = { QByteArray(kShipped), newPassword, newPassword };
    for (const QByteArray &reply : replies) {
        QByteArray line = reply + "\n";
        if (write(master, line.constData(), line.size()) < 0) {
            break;
        }
        // Give it a moment to consume the line and print the next prompt.
        usleep(200 * 1000);
    }

    char buf[512];
    ssize_t n;
    while ((n = read(master, buf, sizeof(buf))) > 0) {
        transcript->append(buf, static_cast<int>(n));
    }
    close(master);

    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

} // namespace

QString Passwd::change(const QString &newPassword)
{
    if (newPassword.length() < 6) {
        return QStringLiteral("Use at least 6 characters.");
    }
    if (newPassword == QLatin1String(kShipped)) {
        return QStringLiteral("That is the password it came with. Pick another one.");
    }

    QByteArray transcript;
    if (talkToPasswd(newPassword.toUtf8(), &transcript)) {
        return QString();
    }

    // passwd's own complaints are written for a terminal. Translate the two
    // that a person actually hits and keep the rest generic rather than
    // printing a wall of it on a phone screen.
    const QString out = QString::fromUtf8(transcript);
    if (out.contains(QLatin1String("too simplistic"), Qt::CaseInsensitive)
        || out.contains(QLatin1String("BAD PASSWORD"), Qt::CaseInsensitive)) {
        return QStringLiteral("Too simple: it is close to a dictionary word or a pattern.");
    }
    if (out.contains(QLatin1String("too short"), Qt::CaseInsensitive)) {
        return QStringLiteral("Too short.");
    }
    qWarning("passwd refused: %s", qPrintable(out.trimmed()));
    return QStringLiteral("It could not be changed. Try a longer one.");
}
