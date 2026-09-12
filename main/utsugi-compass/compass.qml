// Compass -- compass and test bench for the surya's sensors.
//
// This is NOT decoration: it is the instrument you use to check whether the
// accelerometer reaches Linux. That is why its most important job is to TELL
// APART "no sensor" from "the sensor reads zero", which look alike to the eye
// and are not the same thing at all.
//
// In Qt, a sensor that cannot start leaves 'active' at false on its own. That
// is what is used here to decide each one's state, instead of watching whether
// the numbers move -- which would give a false negative with the phone still.
//
// Pure QML on purpose: it compiles nothing and installs no packages. Everything
// it uses (QtSensors and its iio-sensor-proxy backend) is already on the phone.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtSensors

ApplicationWindow {
    id: app
    visible: true
    width: 416; height: 924
    title: "Compass"
    color: "#12131a"

    readonly property color green: "#3ddc84"
    readonly property color red:  "#ff5c5c"
    readonly property color amber: "#ffb347"
    readonly property color faint: "#8a8f9e"

    // --- the sensors ---------------------------------------------------------
    // 'active: true' is a REQUEST, not a fact. If there is no backend, Qt sets
    // it back to false. That is where the diagnosis is.
    Accelerometer {
        id: accel; active: true; dataRate: 25
        property real x: 0; property real y: 0; property real z: 0
        property int  n: 0
        onReadingChanged: { x = reading.x; y = reading.y; z = reading.z; n++ }
    }
    Magnetometer {
        id: magneto; active: true; dataRate: 25
        property int n: 0
        onReadingChanged: n++
    }
    Compass {
        id: compass; active: true; dataRate: 25
        property real azimuth: 0
        property real quality: 0
        property int  n: 0
        onReadingChanged: { azimuth = reading.azimuth; quality = reading.calibrationLevel; n++ }
    }
    // Ambient light also comes from this stack, and it was not being shown. It
    // is useful here for exactly that reason: it confirms at a glance that the
    // path to the SSC is alive, without depending on moving the phone.
    AmbientLightSensor {
        id: light; active: true
        property real value: 0
        property int n: 0
        onReadingChanged: { value = reading.lightLevel; n++ }
    }
    OrientationSensor {
        id: orient; active: true
        property int value: 0
        property int n: 0
        onReadingChanged: { value = reading.orientation; n++ }
    }

    function orientationName(o) {
        switch (o) {
            case OrientationReading.TopUp:    return "portrait";
            case OrientationReading.TopDown:  return "portrait upside down";
            case OrientationReading.LeftUp:   return "landscape (left)";
            case OrientationReading.RightUp:  return "landscape (right)";
            case OrientationReading.FaceUp:   return "face up";
            case OrientationReading.FaceDown: return "face down";
            default: return "undetermined";
        }
    }

    readonly property bool haveAny: accel.active || magneto.active || compass.active || orient.active

    // --- tilt, derived from the accelerometer -------------------------------
    // With the phone flat, x and y are ~0 and z ~9.8. Tilt it and gravity gets
    // shared out. This is what moves the level's bubble.
    readonly property real tiltX: accel.active ? Math.max(-1, Math.min(1, accel.x / 9.81)) : 0
    readonly property real tiltY: accel.active ? Math.max(-1, Math.min(1, accel.y / 9.81)) : 0

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        ColumnLayout {
            width: app.width
            spacing: 14

            // ---------- header ----------
            Item { Layout.preferredHeight: 8 }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "Compass"
                color: "white"; font.pixelSize: 26; font.bold: true
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "compass and sensor test"
                color: app.faint; font.pixelSize: 13
            }

            // ---------- the warning, when there is nothing ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 14
                Layout.preferredHeight: warning.implicitHeight + 24
                visible: !app.haveAny
                color: "#2a1a1a"; border.color: app.red; border.width: 1; radius: 8
                Label {
                    id: warning
                    anchors { fill: parent; margins: 12 }
                    wrapMode: Text.WordWrap
                    color: app.red; font.pixelSize: 13
                    text: "NO SENSOR STARTS.\n\n" +
                          "It is not that they read zero: it is that Qt could not activate them, " +
                          "so there is nobody providing data.\n\n" +
                          "On this phone the accelerometer (Bosch BMI220) hangs off the SSC over SPI, " +
                          "not off a SoC bus. The path is ADSP -> libssc -> iio-sensor-proxy, " +
                          "and it fails because hexagonrpcd starts without -R and the DSP cannot find its firmware.\n\n" +
                          "The utsugi-surya-sensors package fixes it, and it comes with\n" +
                          "utsugi-surya-base.  See tasks/016."
                }
            }

            // ---------- the compass rose ----------
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 300
                Layout.preferredHeight: 300

                Rectangle {
                    anchors.centerIn: parent
                    width: 280; height: 280; radius: width / 2
                    color: "#1b1d27"
                    border.color: compass.active ? app.green : "#3a3d4a"
                    border.width: 2
                }

                // ticks every 30 degrees
                Repeater {
                    model: 12
                    Rectangle {
                        width: index % 3 === 0 ? 3 : 1
                        height: index % 3 === 0 ? 16 : 9
                        color: app.faint
                        x: parent.width / 2 - width / 2
                        y: parent.height / 2 - 140 + 12
                        transform: Rotation {
                            origin.x: width / 2; origin.y: 128
                            angle: index * 30
                        }
                    }
                }

                // the needle: turns opposite to the azimuth, like a real compass
                Item {
                    anchors.centerIn: parent
                    width: 1; height: 1
                    rotation: compass.active ? -compass.azimuth : 0
                    Behavior on rotation { RotationAnimation { duration: 180; direction: RotationAnimation.Shortest } }

                    Rectangle {   // north
                        width: 8; height: 110; radius: 4
                        color: compass.active ? app.red : "#4a4d5a"
                        x: -4; y: -110
                    }
                    Rectangle {   // south
                        width: 8; height: 110; radius: 4
                        color: compass.active ? "#e8e8ee" : "#33363f"
                        x: -4; y: 0
                    }
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: "#12131a"; border.color: app.faint; border.width: 2
                        x: -9; y: -9
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6
                    text: "N"; color: app.red; font.pixelSize: 18; font.bold: true
                }

                Label {
                    anchors.centerIn: parent
                    y: parent.height / 2 + 60
                    text: compass.active ? Math.round(compass.azimuth) + "°" : "--"
                    color: "white"; font.pixelSize: 30; font.bold: true
                }
            }

            // ---------- bubble level ----------
            Label {
                Layout.leftMargin: 18
                text: "Level"; color: "white"; font.pixelSize: 16; font.bold: true
            }
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 200; height: 200; radius: 100
                color: "#1b1d27"
                border.color: accel.active ? app.green : "#3a3d4a"; border.width: 2

                Rectangle {   // reference centre
                    anchors.centerIn: parent
                    width: 46; height: 46; radius: 23
                    color: "transparent"; border.color: app.faint; border.width: 1
                }
                Rectangle {   // the bubble
                    width: 34; height: 34; radius: 17
                    color: accel.active ? app.green : "#4a4d5a"
                    opacity: 0.85
                    x: parent.width / 2 - 17 + app.tiltX * -78
                    y: parent.height / 2 - 17 + app.tiltY *  78
                    Behavior on x { NumberAnimation { duration: 120 } }
                    Behavior on y { NumberAnimation { duration: 120 } }
                }
            }

            // ---------- each sensor's state ----------
            // (the note explaining the two greys goes right below the list)
            Label {
                Layout.leftMargin: 18
                text: "Sensors"; color: "white"; font.pixelSize: 16; font.bold: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 18; Layout.rightMargin: 18
                spacing: 6

                // THE ONES THIS PHONE CAN ACTUALLY PROVIDE, FIRST. And the raw
                // ones at the end, marked for what they are: unavailable BY
                // DESIGN.
                //
                // This was the other way round and it was misleading. This
                // device's sensors go through 'iio-sensor-proxy', which is a
                // HIGH-LEVEL daemon: it gives heading, orientation, light and
                // proximity, and NEVER the raw vectors. Its Qt connector
                // registers exactly four things --
                //
                //   iio-sensor-proxy.compass    .orientationsensor
                //   iio-sensor-proxy.lightsensor .proximitysensor
                //
                // -- and neither QAccelerometer nor QMagnetometer is among them.
                // The 'generic' connector does not give them either: its thing
                // is derivatives (als, orientation, rotation, tilt) that need a
                // real accelerometer underneath which does not exist here.
                //
                // So those two rows came out RED from day one, with the four
                // sensors working perfectly. A test bench that says something is
                // broken when it is not is worse than not having one: it sends
                // you chasing a fault that is not there.
                Repeater {
                    model: [
                        // THE ACCELEROMETER WORKS, and this row says so.
                        //
                        // It used to come out red with "does not start" and it
                        // was misleading: the sensor is alive -- it is the one
                        // that rotates the screen -- and what arrives from it
                        // through this stack is the ORIENTATION, not a vector in
                        // m/s². It shows what there is, which is what answers the
                        // question "does it work or not".
                        { n: "Accelerometer",  a: orient.active,  c: orient.n, gray: false,
                          d: orient.active
                            ? "alive -- orientation: " + app.orientationName(orient.value)
                            : "" },
                        { n: "Compass",       a: compass.active, c: compass.n, gray: false,
                          d: compass.active ? "calibration " + Math.round(compass.quality * 100) + "%" : "" },
                        { n: "Ambient light",  a: light.active,     c: light.n, gray: false,
                          d: light.active ? Math.round(light.value) + " lux" : "" },
                        // AND A SINGLE GREY ROW for what this stack does not give,
                        // instead of two red ones that look like two faults.
                        //
                        // 'iio-sensor-proxy' is a high-level daemon: its Qt
                        // connector registers compass, orientationsensor,
                        // lightsensor and proximitysensor, and NOTHING ELSE.
                        // Measured with the same API this screen uses:
                        //
                        //   Accelerometer active=false   Compass active=true
                        //   Magnetometer active=false    Orientation active=true
                        //
                        // It is not a fault and it is not fixed with code from
                        // here: it would need reading the SSC without going
                        // through that daemon.
                        { n: "Raw vector",  a: accel.active || magneto.active,
                          c: accel.n + magneto.n, gray: !(accel.active || magneto.active),
                          d: "m/s² and µT -- this layer does not provide them, not a fault" }
                    ]
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            width: 10; height: 10; radius: 5
                            // Green only if READINGS HAVE ALSO ARRIVED. An active
                            // sensor with 0 readings is amber: it started but is
                            // silent. Grey, not red, for what does not exist in
                            // this layer: red means "broken" and this is not.
                            color: modelData.gray ? app.faint
                                 : !modelData.a ? app.red
                                 : modelData.c > 0 ? app.green : app.amber
                        }
                        Label {
                            text: modelData.n; color: "white"; font.pixelSize: 14
                            Layout.preferredWidth: 110
                        }
                        Label {
                            Layout.fillWidth: true
                            // 'gray' TAKES PRECEDENCE OVER "does not start", and
                            // this order is the whole fix. Before, the inactive
                            // condition came first, so the reason written in 'd'
                            // was NEVER SEEN: it showed "does not start" in red
                            // for two sensors that on this phone do not exist by
                            // design. The explanation was there and hidden by its
                            // own row.
                            text: modelData.gray ? modelData.d
                                : !modelData.a ? "does not start"
                                : modelData.c === 0 ? "active, no readings"
                                : modelData.d
                            color: modelData.gray ? app.faint
                                 : !modelData.a ? app.red
                                 : modelData.c === 0 ? app.amber : app.faint
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ---------- what KWin would see ----------
            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 18
                Layout.preferredHeight: 66
                color: "#1b1d27"; radius: 8
                ColumnLayout {
                    anchors { fill: parent; margins: 10 }
                    spacing: 2
                    Label {
                        text: "What KWin would use to rotate the screen"
                        color: app.faint; font.pixelSize: 12
                    }
                    Label {
                        text: orient.active && orient.n > 0
                              ? app.orientationName(orient.value)
                              : "nothing: without orientation there is no automatic rotation"
                        color: orient.active && orient.n > 0 ? app.green : app.red
                        font.pixelSize: 15; font.bold: true
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.margins: 18
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: app.faint; font.pixelSize: 11
                text: "The sensors do not show up under /sys/bus/iio: they go over D-Bus.\n" +
                      "From a console:  monitor-sensor --accel"
            }
            Item { Layout.preferredHeight: 16 }
        }
    }
}
