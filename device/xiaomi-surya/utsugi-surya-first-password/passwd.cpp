// SPDX-License-Identifier: GPL-2.0-or-later

#include "passwd.h"

#include <QDebug>

#include <cerrno>
#include <csignal>
#include <cstring>
#include <poll.h>
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
//
// AND IT HAS TO BE ANSWERED PROMPT BY PROMPT. Writing the three replies one
// after another does not work: passwd flushes pending terminal input before
// each question, precisely so a password typed ahead cannot be swallowed. The
// first reply vanished that way and every answer landed one question late --
//
//     147147                       <- written before it asked, discarded
//     Changing password for user.
//     Current password:
//     1111                         <- the NEW password answering the OLD prompt
//     passwd: Authentication failure
//
// -- which is measured, from the phone, on 2026-09-12. So: read until it asks,
// then answer, three times.
bool talkToPasswd(const QByteArray &newPassword, QByteArray *transcript)
{
    int master = -1;
    const pid_t pid = forkpty(&master, nullptr, nullptr, nullptr);
    if (pid < 0) {
        return false;
    }

    if (pid == 0) {
        // Untranslated prompts: the strings below are what we wait for.
        setenv("LC_ALL", "C", 1);
        execlp("passwd", "passwd", nullptr);
        _exit(127);
    }

    // What it asks, in order, and what to say to each.
    struct Step {
        const char *marker;
        QByteArray reply;
    };
    const Step steps[] = {
        { "urrent password", QByteArray(kShipped) },   // also "Old password"
        { "ew password",     newPassword },
        { "etype",           newPassword },
    };
    const int stepCount = int(sizeof(steps) / sizeof(steps[0]));

    int step = 0;
    int answeredUpTo = 0;   // how much of the transcript is already accounted for
    const int deadlineMs = 15000;
    int waitedMs = 0;

    while (step < stepCount && waitedMs < deadlineMs) {
        struct pollfd p = { master, POLLIN, 0 };
        const int ready = poll(&p, 1, 200);
        waitedMs += 200;
        if (ready <= 0) {
            continue;
        }

        char buf[512];
        const ssize_t n = read(master, buf, sizeof(buf));
        if (n <= 0) {
            break;
        }
        transcript->append(buf, static_cast<int>(n));

        // "Old password" appears in passwd's own echo of what we typed, so only
        // look at the part that arrived after the last answer.
        const QByteArray fresh = transcript->mid(answeredUpTo);
        if (fresh.contains(steps[step].marker)) {
            const QByteArray line = steps[step].reply + "\n";
            if (write(master, line.constData(), line.size()) < 0) {
                break;
            }
            answeredUpTo = transcript->size();
            ++step;
            waitedMs = 0;
        }
    }

    // Whatever it says afterwards -- the failure, or nothing at all.
    for (int i = 0; i < 10; ++i) {
        struct pollfd p = { master, POLLIN, 0 };
        if (poll(&p, 1, 200) <= 0) {
            continue;
        }
        char buf[512];
        const ssize_t n = read(master, buf, sizeof(buf));
        if (n <= 0) {
            break;
        }
        transcript->append(buf, static_cast<int>(n));
    }
    close(master);

    // Reap it WITHOUT blocking, and kill it if it is still there.
    //
    // When passwd refuses the new password it does not exit: it prints "The
    // password has not been changed." and asks again, up to three times. With a
    // blocking waitpid that is a dialog frozen on "Changing…" for ever, waiting
    // for a process that is waiting for us. Measured on the phone on
    // 2026-09-12 by feeding it a password it rejects.
    int status = 0;
    bool exited = false;
    for (int i = 0; i < 20; ++i) {          // two seconds
        if (waitpid(pid, &status, WNOHANG) == pid) {
            exited = true;
            break;
        }
        usleep(100 * 1000);
    }
    if (!exited) {
        kill(pid, SIGKILL);
        waitpid(pid, &status, 0);
        return false;                        // it never accepted what we sent
    }

    return step == stepCount && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

} // namespace

QString Passwd::change(const QString &newPassword)
{
    // Four, not six. Six is a desktop habit: a phone is unlocked dozens of
    // times a day with a thumb, and the thing people actually use is a 4-digit
    // PIN. Refusing that does not produce a longer password, it produces one
    // written on something. The system imposes no minimum of its own here --
    // no PASS_MIN_LEN in login.defs, no quality module wired into pam.d -- so
    // this number was ours and arbitrary.
    if (newPassword.length() < 4) {
        return QStringLiteral("Use at least 4 characters.");
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
    if (out.contains(QLatin1String("has not been changed"), Qt::CaseInsensitive)) {
        return QStringLiteral("It refused that one. Try a different password.");
    }
    qWarning("passwd refused: %s", qPrintable(out.trimmed()));
    return QStringLiteral("It could not be changed. Try a longer one.");
}
