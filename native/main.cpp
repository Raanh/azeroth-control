#include <QGuiApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QSocketNotifier>
#include <QTimer>
#include <QQuickWindow>

#include "controller.h"

#ifdef Q_OS_LINUX
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <cerrno>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>
#endif

#ifdef Q_OS_LINUX
static void applySteamWindowClass(QObject *rootObject)
{
    const QByteArray steamAppId = qgetenv("SteamAppId");
    bool validAppId = false;
    steamAppId.toULongLong(&validAppId);
    auto *window = qobject_cast<QQuickWindow *>(rootObject);
    if (!window || !validAppId || steamAppId.isEmpty())
        return;

    // Gamescope groups non-Steam windows primarily by their X11 WM_CLASS.
    // Keep Qt's application name unchanged so existing AppDataLocation paths
    // remain compatible, but identify this window as its actual Steam shortcut.
    const QByteArray steamWindowClass = QByteArrayLiteral("steam_app_") + steamAppId;
    Display *display = XOpenDisplay(nullptr);
    if (!display)
        return;

    XClassHint hint{};
    hint.res_name = const_cast<char *>(steamWindowClass.constData());
    hint.res_class = const_cast<char *>(steamWindowClass.constData());
    XSetClassHint(display, static_cast<Window>(window->winId()), &hint);
    XFlush(display);
    XCloseDisplay(display);
    qInfo() << "Steam window class:" << steamWindowClass;
}
#endif

#ifdef Q_OS_LINUX
class SteamGamepad final : public QObject
{
public:
    explicit SteamGamepad(Controller *controller, QObject *parent = nullptr)
        : QObject(parent), m_controller(controller)
    {
        m_probe.setInterval(1500);
        connect(&m_probe, &QTimer::timeout, this, [this] {
            if (m_fd >= 0 && (!QFile::exists(m_devicePath) || ::ioctl(m_fd, EVIOCGID, &m_deviceId) < 0))
                closeDevice();
            openDevice();
        });
        connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
            // Steam creates a new virtual XInput device for the foreground app.
            // Drop the old descriptor while WoW owns the controller and rescan
            // when Azeroth Control becomes active again.
            closeDevice();
            if (state == Qt::ApplicationActive)
                QTimer::singleShot(120, this, [this] { openDevice(); });
        });
        m_probe.start();
        openDevice();
    }

    ~SteamGamepad() override { closeDevice(); }

private:
    void openDevice()
    {
        if (m_fd >= 0)
            return;
        QDir input(QStringLiteral("/dev/input"));
        const QStringList devices = input.entryList({QStringLiteral("event*")}, QDir::System);
        for (const QString &name : devices) {
            const QByteArray path = input.filePath(name).toLocal8Bit();
            const int fd = ::open(path.constData(), O_RDONLY | O_NONBLOCK);
            if (fd < 0)
                continue;
            char deviceName[256] = {};
            if (::ioctl(fd, EVIOCGNAME(sizeof(deviceName)), deviceName) < 0) {
                ::close(fd);
                continue;
            }
            const QString label = QString::fromLocal8Bit(deviceName);
            if (!label.contains(QStringLiteral("X-Box"), Qt::CaseInsensitive)
                && !label.contains(QStringLiteral("Xbox"), Qt::CaseInsensitive)
                && !label.contains(QStringLiteral("Steam Virtual Gamepad"), Qt::CaseInsensitive)) {
                ::close(fd);
                continue;
            }
            m_fd = fd;
            m_devicePath = QString::fromLocal8Bit(path);
            ::ioctl(m_fd, EVIOCGID, &m_deviceId);
            m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
            connect(m_notifier, &QSocketNotifier::activated, this, [this] { readEvents(); });
            qInfo() << "Using gamepad input:" << label;
            return;
        }
    }

    void closeDevice()
    {
        delete m_notifier;
        m_notifier = nullptr;
        if (m_fd >= 0)
            ::close(m_fd);
        m_fd = -1;
        m_devicePath.clear();
    }

    void handleKey(quint16 code)
    {
        switch (code) {
        case BTN_DPAD_UP: m_controller->dispatchGamepad(QStringLiteral("up")); break;
        case BTN_DPAD_DOWN: m_controller->dispatchGamepad(QStringLiteral("down")); break;
        case BTN_DPAD_LEFT: m_controller->dispatchGamepad(QStringLiteral("left")); break;
        case BTN_DPAD_RIGHT: m_controller->dispatchGamepad(QStringLiteral("right")); break;
        case BTN_SOUTH: m_controller->dispatchGamepad(QStringLiteral("activate")); break; // A
        case BTN_EAST: m_controller->dispatchGamepad(QStringLiteral("back")); break; // B
        case BTN_WEST: m_controller->dispatchGamepad(QStringLiteral("keyboard")); break; // X
        case BTN_TL: m_controller->dispatchGamepad(QStringLiteral("page-up")); break;
        case BTN_TR: m_controller->dispatchGamepad(QStringLiteral("page-down")); break;
        default: break;
        }
    }

    void handleAxis(quint16 code, qint32 value)
    {
        if (code == ABS_HAT0X) {
            if (value != m_hatX && value != 0)
                m_controller->dispatchGamepad(value < 0 ? QStringLiteral("left") : QStringLiteral("right"));
            m_hatX = value;
        } else if (code == ABS_HAT0Y) {
            if (value != m_hatY && value != 0)
                m_controller->dispatchGamepad(value < 0 ? QStringLiteral("up") : QStringLiteral("down"));
            m_hatY = value;
        } else if (code == ABS_X) {
            const int direction = value < -12000 ? -1 : value > 12000 ? 1 : 0;
            if (direction != m_stickX && direction != 0)
                m_controller->dispatchGamepad(direction < 0 ? QStringLiteral("left") : QStringLiteral("right"));
            m_stickX = direction;
        } else if (code == ABS_Y) {
            const int direction = value < -12000 ? -1 : value > 12000 ? 1 : 0;
            if (direction != m_stickY && direction != 0)
                m_controller->dispatchGamepad(direction < 0 ? QStringLiteral("up") : QStringLiteral("down"));
            m_stickY = direction;
        }
    }

    void readEvents()
    {
        input_event event{};
        ssize_t bytes = 0;
        while ((bytes = ::read(m_fd, &event, sizeof(event))) == sizeof(event)) {
            if (event.type == EV_KEY && event.value == 1) {
                handleKey(event.code);
            } else if (event.type == EV_ABS) {
                handleAxis(event.code, event.value);
            }
        }
        if (bytes < 0 && errno != EAGAIN && errno != EWOULDBLOCK)
            closeDevice();
    }

    Controller *m_controller;
    int m_fd = -1;
    QString m_devicePath;
    input_id m_deviceId{};
    qint32 m_hatX = 0;
    qint32 m_hatY = 0;
    qint32 m_stickX = 0;
    qint32 m_stickY = 0;
    QSocketNotifier *m_notifier = nullptr;
    QTimer m_probe;
};
#endif

int main(int argc, char *argv[])
{
    QGuiApplication::setApplicationName(QStringLiteral("Azeroth Control"));
    QGuiApplication::setOrganizationName(QStringLiteral("Azeroth Control"));
    QGuiApplication app(argc, argv);

    Controller controller;
#ifdef Q_OS_LINUX
    SteamGamepad gamepad(&controller, &app);
#endif
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("control"), &controller);
    controller.start();
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qWarning() << "Azeroth Control QML failed to load";
        return 1;
    }
#ifdef Q_OS_LINUX
    applySteamWindowClass(engine.rootObjects().constFirst());
#endif

    return app.exec();
}
