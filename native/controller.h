#pragma once

#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

class Controller final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString serverState READ serverState NOTIFY statusChanged)
    Q_PROPERTY(QString realmName READ realmName NOTIFY statusChanged)
    Q_PROPERTY(QString uptime READ uptime NOTIFY statusChanged)
    Q_PROPERTY(QString cpu READ cpu NOTIFY statusChanged)
    Q_PROPERTY(QString memory READ memory NOTIFY statusChanged)
    Q_PROPERTY(int bots READ bots NOTIFY statusChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool gameRunning READ gameRunning NOTIFY gameRunningChanged)
    Q_PROPERTY(bool installRunning READ installRunning NOTIFY installChanged)
    Q_PROPERTY(bool installPaused READ installPaused NOTIFY installChanged)
    Q_PROPERTY(int installProgress READ installProgress NOTIFY installChanged)
    Q_PROPERTY(QString installMessage READ installMessage NOTIFY installChanged)
    Q_PROPERTY(QString notice READ notice NOTIFY noticeChanged)
    Q_PROPERTY(QString activeRealm READ activeRealm NOTIFY statusChanged)
    Q_PROPERTY(QStringList availableRealms READ availableRealms NOTIFY statusChanged)
    Q_PROPERTY(int configuredBots READ configuredBots NOTIFY settingsChanged)
    Q_PROPERTY(double xpRate READ xpRate NOTIFY settingsChanged)
    Q_PROPERTY(double dropRate READ dropRate NOTIFY settingsChanged)
    Q_PROPERTY(double spawnRate READ spawnRate NOTIFY settingsChanged)
    Q_PROPERTY(QVariantMap data READ data NOTIFY dataChanged)
    Q_PROPERTY(QVariantList installations READ installations NOTIFY installationsChanged)
    Q_PROPERTY(QString version READ version CONSTANT)

public:
    explicit Controller(QObject *parent = nullptr);
    void start();

    QString serverState() const { return m_serverState; }
    QString realmName() const { return m_realmName; }
    QString uptime() const { return m_uptime; }
    QString cpu() const { return m_cpu; }
    QString memory() const { return m_memory; }
    int bots() const { return m_bots; }
    bool busy() const { return m_busy; }
    bool gameRunning() const { return m_gameRunning; }
    bool installRunning() const { return m_installRunning; }
    bool installPaused() const { return m_installPaused; }
    int installProgress() const { return m_installProgress; }
    QString installMessage() const { return m_installMessage; }
    QString notice() const { return m_notice; }
    QString activeRealm() const { return m_activeRealm; }
    QStringList availableRealms() const { return m_availableRealms; }
    int configuredBots() const { return m_configuredBots; }
    double xpRate() const { return m_xpRate; }
    double dropRate() const { return m_dropRate; }
    double spawnRate() const { return m_spawnRate; }
    QVariantMap data() const { return m_data; }
    QVariantList installations() const { return m_installations; }
    QString version() const { return QStringLiteral("0.4.0-preview.4"); }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void serverAction(const QString &action, const QString &realm = {});
    Q_INVOKABLE void loadSettings(const QString &realm);
    Q_INVOKABLE void saveSettings(const QVariantMap &settings, const QString &realm);
    Q_INVOKABLE void maintenanceAction(const QString &action);
    Q_INVOKABLE void apiGet(const QString &key, const QString &path);
    Q_INVOKABLE void apiPost(const QString &key, const QString &path, const QVariantMap &payload = {});
    Q_INVOKABLE void installServer(const QVariantMap &selection);
    Q_INVOKABLE void pauseInstallation();
    Q_INVOKABLE void cancelInstallation();
    Q_INVOKABLE void removeInstallation(const QString &id, bool deleteFiles);
    Q_INVOKABLE void reloadInstallations();
    Q_INVOKABLE void clearNotice();
    void dispatchGamepad(const QString &command) { emit gamepadAction(command); }

signals:
    void statusChanged();
    void busyChanged();
    void gameRunningChanged();
    void noticeChanged();
    void settingsChanged();
    void dataChanged();
    void installChanged();
    void installationsChanged();
    void yieldToGame();
    void gamepadAction(const QString &command);

private:
    QString findActiveRoot() const;
    QString findBackend() const;
    void startBackend();
    void request(const QString &path, const QByteArray &method = "GET", const QJsonObject &payload = {});
    void applyStatus(const QJsonObject &payload);
    void setBusy(bool value);
    void setNotice(const QString &value);
    QString statePath() const;

    QNetworkAccessManager m_network;
    QProcess m_backend;
    QTimer m_refreshTimer;
    QString m_root;
    QString m_serverState = QStringLiteral("offline");
    QString m_realmName = QStringLiteral("AzerothCore");
    QString m_uptime = QStringLiteral("—");
    QString m_cpu = QStringLiteral("—");
    QString m_memory = QStringLiteral("—");
    QString m_activeRealm = QStringLiteral("progression");
    QStringList m_availableRealms{QStringLiteral("progression")};
    int m_bots = 0;
    int m_configuredBots = 0;
    double m_xpRate = 1.0;
    double m_dropRate = 1.0;
    double m_spawnRate = 1.0;
    QVariantMap m_data;
    bool m_busy = false;
    bool m_gameRunning = false;
    QString m_notice;
    QProcess m_installProcess;
    bool m_installRunning = false;
    bool m_installPaused = false;
    bool m_installCanceled = false;
    int m_installProgress = 0;
    QString m_installMessage;
    QVariantList m_installations;
};
