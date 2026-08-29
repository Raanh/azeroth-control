QT += core gui qml quick quickcontrols2 network
CONFIG += c++17 release
TEMPLATE = app
TARGET = azeroth-control-native

SOURCES += \
    main.cpp \
    controller.cpp

HEADERS += controller.h
RESOURCES += qml.qrc

QMAKE_CXXFLAGS_RELEASE += -O2

unix:LIBS += -lX11
