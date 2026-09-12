// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QObject>
#include <QString>

/*
 * Changes this account's password, with no privilege of any kind.
 *
 * It can do that because of WHEN it runs: only while the password is still the
 * one the image shipped with, which this program knows. So it drives passwd(1)
 * as the user, answering the old-password prompt itself. Nothing is setuid,
 * there is no polkit action, and no helper runs as root -- the whole mechanism
 * stops working the moment the password is no longer the shipped one, which is
 * exactly when this program should stop existing anyway.
 */
class Passwd : public QObject
{
    Q_OBJECT

public:
    using QObject::QObject;

    // Empty on success, otherwise a sentence to put on screen. Never returns
    // passwd's raw output: it is written for a terminal and says things like
    // "BAD PASSWORD: it is too simplistic" in the middle of a phone screen.
    Q_INVOKABLE QString change(const QString &newPassword);
};
