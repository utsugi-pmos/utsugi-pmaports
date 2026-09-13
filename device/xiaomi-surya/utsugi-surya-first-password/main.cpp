// SPDX-License-Identifier: GPL-2.0-or-later
//
// Shown once, at the first session of a phone flashed from our image, while its
// password is still the one the image shipped with. What decides "while" is not
// here: a system unit reads /etc/shadow -- which a user cannot -- and drops a
// flag in /run. This program only draws the window.

#include <QApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtQml/qqmlregistration.h>

#include <KLocalizedContext>
#include <KLocalizedString>

#include "passwd.h"
#include "encrypt.h"

int main(int argc, char *argv[])
{
    // QApplication, not QGuiApplication: Kirigami reaches for QtWidgets styles
    // and without it the controls do not match the rest of the phone.
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("utsugi-first-password"));

    // NOTHING MAY LOCK THE SCREEN WHILE THIS IS UP.
    //
    // The first boot of the image spends its first minutes on these steps,
    // and the person may well leave the phone on the table while it settles.
    // Plasma's screen locker fires on idle and then asks for a PIN -- the
    // shipped one, which the person has no reason to know and this very
    // window exists to replace. Seen on 2026-09-14 on a phone flashed
    // minutes earlier: "Enter PIN", with the assistant behind it.
    //
    // org.freedesktop.ScreenSaver.Inhibit is what a video player uses for
    // the same purpose; Plasma honours it for both the locker and the
    // display timeout. The cookie is released when the process exits, and
    // the process exits when the steps are done.
    {
        QDBusInterface saver(QStringLiteral("org.freedesktop.ScreenSaver"),
                             QStringLiteral("/org/freedesktop/ScreenSaver"),
                             QStringLiteral("org.freedesktop.ScreenSaver"),
                             QDBusConnection::sessionBus());
        if (saver.isValid()) {
            QDBusReply<uint> r = saver.call(QStringLiteral("Inhibit"),
                                            QStringLiteral("utsugi-first-password"),
                                            QStringLiteral("First-boot steps are on screen"));
            if (!r.isValid()) {
                qWarning("screen lock not inhibited: %s", qPrintable(r.error().message()));
            }
        }
    }

    qmlRegisterType<Passwd>("org.utsugi.firstpassword", 1, 0, "Passwd");
    qmlRegisterType<Encrypt>("org.utsugi.firstpassword", 1, 0, "Encrypt");

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/org/utsugi/firstpassword/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    return app.exec();
}
