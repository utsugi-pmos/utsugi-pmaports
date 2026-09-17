# The full-screen step that makes somebody choose a password before using a
# phone flashed from our image. See main.cpp for why it exists and passwd.cpp
# for why it needs no privilege.
cmake_minimum_required(VERSION 3.20)
project(utsugi-first-password VERSION 1.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

set(KF_MIN_VERSION 6.0)
set(QT_MIN_VERSION 6.6)

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core DBus Gui Qml Quick QuickControls2 Widgets)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS I18n Kirigami KCMUtils)

qt_standard_project_setup(REQUIRES 6.6)

qt_add_executable(utsugi-first-password main.cpp passwd.cpp passwd.h encrypt.cpp encrypt.h identity.cpp identity.h)

qt_add_qml_module(utsugi-first-password
	URI org.utsugi.firstpassword
	VERSION 1.0
	QML_FILES Main.qml
)

# util-linux's libutil carries forkpty. passwd(1) opens /dev/tty and refuses a
# pipe, so a real terminal is not optional here.
target_link_libraries(utsugi-first-password PRIVATE
	Qt::Core
	Qt::DBus
	Qt::Gui
	Qt::Quick
	Qt::QuickControls2
	Qt::Widgets
	KF6::I18n
	util
)

install(TARGETS utsugi-first-password ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})

# The System Settings module: the same encryption assistant, reachable again for
# anyone who chose "Not now" at first boot. kcmutils_add_qml_kcm() GLOBs ui/, so
# ui/main.qml becomes the KCM's QML. It reuses encrypt.cpp so the standalone step
# and the module drive one and the same Encrypt backend and cannot drift. The
# plugin installs itself; it is not named in an install() below.
kcmutils_add_qml_kcm(kcm_phone_encryption SOURCES kcm.cpp encrypt.cpp encrypt.h)
target_link_libraries(kcm_phone_encryption PRIVATE
	Qt::Core
	KF6::I18n
	KF6::KCMUtils
	KF6::KCMUtilsQuick
)
