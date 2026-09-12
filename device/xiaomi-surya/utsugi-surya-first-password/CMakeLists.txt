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

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Widgets)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS I18n Kirigami)

qt_standard_project_setup(REQUIRES 6.6)

qt_add_executable(utsugi-first-password main.cpp passwd.cpp passwd.h)

qt_add_qml_module(utsugi-first-password
	URI org.utsugi.firstpassword
	VERSION 1.0
	QML_FILES Main.qml
)

# util-linux's libutil carries forkpty. passwd(1) opens /dev/tty and refuses a
# pipe, so a real terminal is not optional here.
target_link_libraries(utsugi-first-password PRIVATE
	Qt::Core
	Qt::Gui
	Qt::Quick
	Qt::QuickControls2
	Qt::Widgets
	KF6::I18n
	util
)

install(TARGETS utsugi-first-password ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
