// SPDX-License-Identifier: GPL-2.0-or-later
//
// Shown once, at the first session of a phone flashed from our image, while its
// password is still the one the image shipped with. What decides "while" is not
// here: a system unit reads /etc/shadow -- which a user cannot -- and drops a
// flag in /run. This program only draws the window.

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtQml/qqmlregistration.h>

#include <KLocalizedContext>
#include <KLocalizedString>

#include "passwd.h"

int main(int argc, char *argv[])
{
    // QApplication, not QGuiApplication: Kirigami reaches for QtWidgets styles
    // and without it the controls do not match the rest of the phone.
    QApplication app(argc, argv);
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("utsugi-first-password"));

    qmlRegisterType<Passwd>("org.utsugi.firstpassword", 1, 0, "Passwd");

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextObject(new KLocalizedContext(&engine));
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/org/utsugi/firstpassword/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }

    return app.exec();
}
