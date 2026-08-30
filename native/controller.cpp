#include "controller.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QStandardPaths>
#include <QDateTime>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>
#ifdef Q_OS_LINUX
#include <signal.h>
#include <unistd.h>
#endif

namespace {
constexpr auto ApiBase = "http://127.0.0.1:8742";

QJsonObject readJson(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object();
}

QString readEnvValue(const QString &path, const QString &key)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QRegularExpression pattern(QStringLiteral("^%1=([^\\r\\n]+)$").arg(QRegularExpression::escape(key)), QRegularExpression::MultilineOption);
    const QRegularExpressionMatch match = pattern.match(QString::fromUtf8(file.readAll()));
    return match.hasMatch() ? match.captured(1).trimmed().remove('"').remove('\'') : QString();
}

}

Controller::Controller(QObject *parent) : QObject(parent)
{
    m_root = findActiveRoot();
    reloadInstallations();
    m_refreshTimer.setInterval(5000);
    connect(&m_refreshTimer, &QTimer::timeout, this, &Controller::refresh);
}

QString Controller::statePath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/azeroth-control/state.json");
}

void Controller::reloadInstallations()
{
    m_installations.clear();
    for (const QJsonValue &value : readJson(statePath()).value(QStringLiteral("installations")).toArray())
        m_installations.append(value.toObject().toVariantMap());
    emit installationsChanged();
}

void Controller::start()
{
    startBackend();
    QTimer::singleShot(350, this, &Controller::refresh);
    m_refreshTimer.start();
}

QString Controller::findActiveRoot() const
{
    const QJsonObject state = readJson(statePath());
    const QString activeId = state.value(QStringLiteral("activeInstallationId")).toString();
    const QJsonArray installations = state.value(QStringLiteral("installations")).toArray();
    for (const QJsonValue &value : installations) {
        const QJsonObject item = value.toObject();
        if (item.value(QStringLiteral("id")).toString() == activeId)
            return item.value(QStringLiteral("path")).toString();
    }
    return QDir::homePath() + QStringLiteral("/.local/share/azeroth-control/servers/server-3574af7e");
}

QString Controller::findBackend() const
{
    const QString overridePath = qEnvironmentVariable("AZEROTH_CONTROL_BACKEND");
    if (!overridePath.isEmpty())
        return overridePath;
    const QString besideApp = QCoreApplication::applicationDirPath()
        + QStringLiteral("/../share/azeroth-control/backend/server.py");
    return QFile::exists(besideApp) ? QDir::cleanPath(besideApp) : QString();
}

void Controller::startBackend()
{
    const QString backendPath = findBackend();
    if (backendPath.isEmpty()) {
        setNotice(QStringLiteral("Native backend was not found."));
        return;
    }
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("AZEROTH_CONTROL_PORT"), QStringLiteral("8742"));
    environment.insert(QStringLiteral("AZEROTH_SERVER_ROOT"), m_root);
    environment.insert(QStringLiteral("AZEROTH_CONTROL_BACKUP_ROOT"),
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/backups"));
    m_backend.setProcessEnvironment(environment);
    m_backend.setProgram(QStringLiteral("python3"));
    m_backend.setArguments({backendPath});
    m_backend.setProcessChannelMode(QProcess::MergedChannels);
    m_backend.start();
}

void Controller::refresh()
{
    request(QStringLiteral("/api/status"));
}

void Controller::loadSettings(const QString &realm)
{
    request(QStringLiteral("/api/settings?realm=") + realm);
}

void Controller::saveSettings(const QVariantMap &settings, const QString &realm)
{
    setBusy(true);
    QJsonObject payload;
    payload.insert(QStringLiteral("realm"), realm.isEmpty() ? m_activeRealm : realm);
    payload.insert(QStringLiteral("settings"), QJsonObject::fromVariantMap(settings));
    request(QStringLiteral("/api/settings"), QByteArrayLiteral("POST"), payload);
}

void Controller::maintenanceAction(const QString &action)
{
    if (action != QStringLiteral("update") && action != QStringLiteral("repair"))
        return;
    setBusy(true);
    request(QStringLiteral("/api/maintenance/") + action, QByteArrayLiteral("POST"));
}

void Controller::apiGet(const QString &key, const QString &path)
{
    Q_UNUSED(key);
    request(path);
}

void Controller::apiPost(const QString &key, const QString &path, const QVariantMap &payload)
{
    Q_UNUSED(key);
    setBusy(true);
    request(path, QByteArrayLiteral("POST"), QJsonObject::fromVariantMap(payload));
}

void Controller::installServer(const QVariantMap &input)
{
    if (m_installRunning)
        return;
    QVariantMap selection = input;
    if (!selection.contains(QStringLiteral("profile")))
        selection.insert(QStringLiteral("profile"), QStringLiteral("progression"));
    if (!selection.contains(QStringLiteral("installRoot")))
        selection.insert(QStringLiteral("installRoot"), QDir::homePath() + QStringLiteral("/.local/share/azeroth-control"));
    if (!selection.contains(QStringLiteral("serverId"))) {
        const QDir serverDirectory(selection.value(QStringLiteral("installRoot")).toString() + QStringLiteral("/servers"));
        const QFileInfoList candidates = serverDirectory.entryInfoList({QStringLiteral("native-*")}, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Time);
        for (const QFileInfo &candidate : candidates) {
            if (QFile::exists(candidate.filePath() + QStringLiteral("/.install-checkpoints/complete")))
                continue;
            const QJsonObject previous = readJson(candidate.filePath() + QStringLiteral("/install-selection.json"));
            if (previous.value(QStringLiteral("profile")).toString() == selection.value(QStringLiteral("profile")).toString()
                && previous.value(QStringLiteral("clientPath")).toString() == selection.value(QStringLiteral("clientPath")).toString()) {
                selection.insert(QStringLiteral("serverId"), candidate.fileName());
                break;
            }
        }
        if (!selection.contains(QStringLiteral("serverId")))
            selection.insert(QStringLiteral("serverId"), QStringLiteral("native-%1").arg(QDateTime::currentDateTimeUtc().toString("yyyyMMddhhmmss")));
    }
    if (!selection.contains(QStringLiteral("serverName")))
        selection.insert(QStringLiteral("serverName"), QStringLiteral("Azeroth Progression"));
    if (!selection.contains(QStringLiteral("bots")))
        selection.insert(QStringLiteral("bots"), 500);
    if (!selection.contains(QStringLiteral("modules")))
        selection.insert(QStringLiteral("modules"), QVariantList{QStringLiteral("playerbots"), QStringLiteral("dungeon-clear"), QStringLiteral("aoe-loot"), QStringLiteral("transmog"), QStringLiteral("learn-spells"), QStringLiteral("auction-house"), QStringLiteral("multibot-bridge")});

    QString installer = qEnvironmentVariable("AZEROTH_CONTROL_INSTALLER");
    if (installer.isEmpty())
        installer = QDir::cleanPath(QCoreApplication::applicationDirPath() + QStringLiteral("/../share/azeroth-control/scripts/install-server.sh"));
    if (!QFile::exists(installer)) {
        setNotice(QStringLiteral("The server installer is not bundled with this preview."));
        return;
    }
    const QString jobs = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/jobs");
    QDir().mkpath(jobs);
    const QString configPath = jobs + QStringLiteral("/install-%1.json").arg(QDateTime::currentMSecsSinceEpoch());
    QFile config(configPath);
    if (!config.open(QIODevice::WriteOnly)) {
        setNotice(QStringLiteral("Could not create the installation plan."));
        return;
    }
    config.write(QJsonDocument(QJsonObject::fromVariantMap(selection)).toJson(QJsonDocument::Indented));
    config.close();
    const QString logDirectory = selection.value(QStringLiteral("installRoot")).toString() + QStringLiteral("/logs");
    QDir().mkpath(logDirectory);
    const QString logPath = logDirectory + QStringLiteral("/install-%1.log").arg(selection.value(QStringLiteral("serverId")).toString());
    {
        QFile log(logPath);
        if (log.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
            log.write(QStringLiteral("\n=== Installation attempt %1 ===\n")
                .arg(QDateTime::currentDateTimeUtc().toString(Qt::ISODate)).toUtf8());
        }
    }

    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("AZEROTH_CATALOG"), qEnvironmentVariable("AZEROTH_CONTROL_CATALOG", installer.left(installer.lastIndexOf('/')) + QStringLiteral("/../manifests/catalog.json")));
    m_installProcess.setProcessEnvironment(environment);
    m_installProcess.setProgram(QStringLiteral("setsid"));
    m_installProcess.setArguments({QStringLiteral("bash"), installer, configPath});
    m_installProcess.setProcessChannelMode(QProcess::MergedChannels);
    m_installRunning = true;
    m_installPaused = false;
    m_installCanceled = false;
    m_installProgress = 0;
    m_installMessage = QStringLiteral("Preparing installation…");
    setBusy(true);
    emit installChanged();
    disconnect(&m_installProcess, nullptr, this, nullptr);
    connect(&m_installProcess, &QProcess::readyRead, this, [this, logPath] {
        const QByteArray rawOutput = m_installProcess.readAll();
        QFile log(logPath);
        if (log.open(QIODevice::WriteOnly | QIODevice::Append))
            log.write(rawOutput);
        const QString output = QString::fromUtf8(rawOutput).trimmed();
        if (output.isEmpty()) return;
        const QStringList lines = output.split('\n', Qt::SkipEmptyParts);
        m_installMessage = lines.constLast().trimmed();
        static const QRegularExpression stepPattern(QStringLiteral("Step\\s+(\\d+)\\s*/\\s*(\\d+)"), QRegularExpression::CaseInsensitiveOption);
        const QRegularExpressionMatch match = stepPattern.match(output);
        if (match.hasMatch())
            m_installProgress = qRound(match.captured(1).toDouble() * 100.0 / qMax(1, match.captured(2).toInt()));
        emit installChanged();
    });
    connect(&m_installProcess, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this, configPath, logPath](int code, QProcess::ExitStatus) {
            if (code == 0) {
                const QJsonObject selection = readJson(configPath);
                const QString serverRoot = QDir::cleanPath(selection.value(QStringLiteral("installRoot")).toString()
                    + QStringLiteral("/servers/") + selection.value(QStringLiteral("serverId")).toString());
                const QString stateFilePath = statePath();
                QJsonObject state = readJson(stateFilePath);
                if (state.isEmpty()) {
                    state.insert(QStringLiteral("schemaVersion"), 1);
                    state.insert(QStringLiteral("onboardingComplete"), false);
                    state.insert(QStringLiteral("installations"), QJsonArray{});
                }
                QJsonArray installations = state.value(QStringLiteral("installations")).toArray();
                const QString id = QStringLiteral("managed-") + QString::fromLatin1(QCryptographicHash::hash(serverRoot.toUtf8(), QCryptographicHash::Sha256).toHex().right(12));
                QJsonArray updated;
                for (const QJsonValue &value : installations) {
                    if (value.toObject().value(QStringLiteral("path")).toString() != serverRoot)
                        updated.append(value);
                }
                updated.append(QJsonObject{{QStringLiteral("id"), id},
                    {QStringLiteral("name"), selection.value(QStringLiteral("serverName")).toString(QStringLiteral("Azeroth Server"))},
                    {QStringLiteral("path"), serverRoot}, {QStringLiteral("provider"), QStringLiteral("azerothcore-playerbots")},
                    {QStringLiteral("imported"), false}, {QStringLiteral("createdAt"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}});
                state.insert(QStringLiteral("installations"), updated);
                state.insert(QStringLiteral("activeInstallationId"), id);
                state.insert(QStringLiteral("onboardingComplete"), true);
                QDir().mkpath(QFileInfo(stateFilePath).absolutePath());
                QFile stateFile(stateFilePath + QStringLiteral(".tmp"));
                if (stateFile.open(QIODevice::WriteOnly)) {
                    stateFile.write(QJsonDocument(state).toJson(QJsonDocument::Indented));
                    stateFile.close();
                    QFile::remove(stateFilePath);
                    QFile::rename(stateFilePath + QStringLiteral(".tmp"), stateFilePath);
                }
                m_root = serverRoot;
                // The backend receives AZEROTH_SERVER_ROOT at process start; restart it
                // so the freshly registered installation becomes the active realm.
                if (m_backend.state() != QProcess::NotRunning) {
                    m_backend.terminate();
                    if (!m_backend.waitForFinished(3000))
                        m_backend.kill();
                }
                startBackend();
                reloadInstallations();
            }
            const QString failureDetail = m_installMessage;
            m_installRunning = false;
            m_installPaused = false;
            m_installProgress = code == 0 ? 100 : m_installProgress;
            m_installMessage = code == 0
                ? QStringLiteral("Installation completed. Restart the native app to load the new server.")
                : m_installCanceled
                    ? QStringLiteral("Installation canceled. Downloaded files and checkpoints were preserved for Resume.")
                    : QStringLiteral("Installation failed: %1 · Log: %2").arg(failureDetail, logPath);
            setBusy(false);
            emit installChanged();
            setNotice(m_installMessage);
            if (code == 0)
                QFile::remove(configPath);
        });
    m_installProcess.start();
}

void Controller::pauseInstallation()
{
#ifdef Q_OS_LINUX
    if (!m_installRunning || m_installProcess.processId() <= 0)
        return;
    const int signal = m_installPaused ? SIGCONT : SIGSTOP;
    if (::kill(-static_cast<pid_t>(m_installProcess.processId()), signal) == 0) {
        m_installPaused = !m_installPaused;
        m_installMessage = m_installPaused ? QStringLiteral("Installation paused. Resume when ready.") : QStringLiteral("Installation resumed.");
        emit installChanged();
    }
#endif
}

void Controller::cancelInstallation()
{
#ifdef Q_OS_LINUX
    if (!m_installRunning || m_installProcess.processId() <= 0)
        return;
    m_installCanceled = true;
    if (m_installPaused)
        ::kill(-static_cast<pid_t>(m_installProcess.processId()), SIGCONT);
    ::kill(-static_cast<pid_t>(m_installProcess.processId()), SIGTERM);
    QTimer::singleShot(4000, this, [this] {
        if (m_installProcess.state() != QProcess::NotRunning)
            ::kill(-static_cast<pid_t>(m_installProcess.processId()), SIGKILL);
    });
#endif
}

void Controller::removeInstallation(const QString &id, bool deleteFiles)
{
    QJsonObject state = readJson(statePath());
    const QJsonArray current = state.value(QStringLiteral("installations")).toArray();
    QJsonObject target;
    QJsonArray remaining;
    for (const QJsonValue &value : current) {
        const QJsonObject item = value.toObject();
        if (item.value(QStringLiteral("id")).toString() == id)
            target = item;
        else
            remaining.append(item);
    }
    if (target.isEmpty()) { setNotice(QStringLiteral("Server installation was not found.")); return; }
    if (deleteFiles && target.value(QStringLiteral("imported")).toBool()) { setNotice(QStringLiteral("Imported servers can only be forgotten.")); return; }
    const QString path = QDir::cleanPath(target.value(QStringLiteral("path")).toString());
    const QString managedRoot = QDir::cleanPath(QDir::homePath() + QStringLiteral("/.local/share/azeroth-control/servers")) + '/';
    if (deleteFiles && (!path.startsWith(managedRoot) || path == managedRoot.chopped(1))) { setNotice(QStringLiteral("Refusing to delete outside the managed server folder.")); return; }
    if (state.value(QStringLiteral("activeInstallationId")).toString() == id) {
        const QString control = path + QStringLiteral("/bin/server-control");
        if (QFileInfo::exists(control))
            QProcess::execute(control, {QStringLiteral("stop")});
    }
    if (deleteFiles) {
        const QString envPath = path + QStringLiteral("/install.env");
        const QString prefix = readEnvValue(envPath, QStringLiteral("CONTAINER_PREFIX"));
        if (!prefix.isEmpty()) {
            QProcess::execute(QStringLiteral("podman"), {QStringLiteral("rm"), QStringLiteral("-f"), prefix + QStringLiteral("-worldserver"), prefix + QStringLiteral("-authserver"), prefix + QStringLiteral("-database")});
            QProcess::execute(QStringLiteral("podman"), {QStringLiteral("volume"), QStringLiteral("rm"), QStringLiteral("-f"), prefix + QStringLiteral("-database-data"), prefix + QStringLiteral("-client-data")});
        }
        QStringList images;
        for (const QString &key : {QStringLiteral("WORLD_IMAGE"), QStringLiteral("AUTH_IMAGE"), QStringLiteral("IMPORT_IMAGE"), QStringLiteral("DATA_IMAGE")}) {
            const QString image = readEnvValue(envPath, key);
            if (!image.isEmpty()) images.append(image);
        }
        if (!images.isEmpty()) {
            QStringList arguments{QStringLiteral("rmi")}; arguments.append(images);
            QProcess::execute(QStringLiteral("podman"), arguments);
        }
        const int result = QProcess::execute(QStringLiteral("gio"), {QStringLiteral("trash"), path});
        if (result != 0) { setNotice(QStringLiteral("Could not move the managed server to Trash.")); return; }
    }
    state.insert(QStringLiteral("installations"), remaining);
    if (state.value(QStringLiteral("activeInstallationId")).toString() == id)
        state.insert(QStringLiteral("activeInstallationId"), remaining.isEmpty() ? QString() : remaining.first().toObject().value(QStringLiteral("id")).toString());
    QFile file(statePath() + QStringLiteral(".tmp"));
    if (file.open(QIODevice::WriteOnly)) { file.write(QJsonDocument(state).toJson(QJsonDocument::Indented)); file.close(); QFile::remove(statePath()); QFile::rename(statePath() + QStringLiteral(".tmp"), statePath()); }
    reloadInstallations();
    setNotice(deleteFiles ? QStringLiteral("Server data moved to Trash. Restart Azeroth Control to load another server.") : QStringLiteral("Server removed from Azeroth Control."));
}

void Controller::serverAction(const QString &action, const QString &realm)
{
    setBusy(true);
    request(QStringLiteral("/api/action"), QByteArrayLiteral("POST"), {
        {QStringLiteral("action"), action},
        {QStringLiteral("realm"), realm.isEmpty() ? m_activeRealm : realm},
    });
}

void Controller::request(const QString &path, const QByteArray &method, const QJsonObject &payload)
{
    QNetworkRequest request(QUrl(QString::fromLatin1(ApiBase) + path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = method == QByteArrayLiteral("POST")
        ? m_network.post(request, QJsonDocument(payload).toJson(QJsonDocument::Compact))
        : m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, path] {
        const QByteArray body = reply->readAll();
        const QJsonObject data = QJsonDocument::fromJson(body).object();
        if (reply->error() != QNetworkReply::NoError) {
            if (path != QStringLiteral("/api/status"))
                setNotice(data.value(QStringLiteral("error")).toString(reply->errorString()));
        } else if (path == QStringLiteral("/api/status")) {
            applyStatus(data);
        } else if (path.startsWith(QStringLiteral("/api/settings"))) {
            const QJsonObject settings = data.value(QStringLiteral("settings")).toObject().isEmpty()
                ? data : data.value(QStringLiteral("settings")).toObject();
            m_configuredBots = settings.value(QStringLiteral("botCount")).toInt(m_configuredBots);
            m_xpRate = settings.value(QStringLiteral("xpRate")).toDouble(m_xpRate);
            m_dropRate = settings.value(QStringLiteral("dropRate")).toDouble(m_dropRate);
            m_spawnRate = settings.value(QStringLiteral("spawnRate")).toDouble(m_spawnRate);
            m_data.insert(path, data.toVariantMap());
            emit settingsChanged();
            emit dataChanged();
            setNotice(QStringLiteral("Settings saved."));
        } else {
            m_data.insert(path, data.toVariantMap());
            emit dataChanged();
            setNotice(data.value(QStringLiteral("message")).toString(QStringLiteral("Action accepted.")));
            QTimer::singleShot(500, this, &Controller::refresh);
        }
        if (path != QStringLiteral("/api/status"))
            setBusy(false);
        reply->deleteLater();
    });
}

void Controller::applyStatus(const QJsonObject &payload)
{
    m_serverState = payload.value(QStringLiteral("state")).toString(QStringLiteral("offline"));
    m_realmName = payload.value(QStringLiteral("realmName")).toString(QStringLiteral("AzerothCore"));
    m_uptime = payload.value(QStringLiteral("uptime")).toString(QStringLiteral("—"));
    m_cpu = payload.value(QStringLiteral("cpu")).toString(QStringLiteral("—"));
    m_memory = payload.value(QStringLiteral("memory")).toString(QStringLiteral("—"));
    m_bots = payload.value(QStringLiteral("bots")).toInt();
    m_activeRealm = payload.value(QStringLiteral("realm")).toString(QStringLiteral("progression"));
    m_availableRealms.clear();
    for (const QJsonValue &realm : payload.value(QStringLiteral("availableRealms")).toArray())
        m_availableRealms.append(realm.toString());
    if (m_availableRealms.isEmpty())
        m_availableRealms.append(m_activeRealm);
    const QJsonObject job = payload.value(QStringLiteral("job")).toObject();
    setBusy(job.value(QStringLiteral("running")).toBool());
    if (!job.value(QStringLiteral("message")).toString().isEmpty())
        setNotice(job.value(QStringLiteral("message")).toString());
    emit statusChanged();
}

void Controller::setBusy(bool value)
{
    if (m_busy == value)
        return;
    m_busy = value;
    emit busyChanged();
}

void Controller::setNotice(const QString &value)
{
    QString normalized = value;
    static const QRegularExpression ansiPattern(QStringLiteral("\\x1b\\[[0-?]*[ -/]*[@-~]"));
    normalized.remove(ansiPattern);
    normalized.replace('\r', '\n');
    QStringList lines;
    for (const QString &line : normalized.split('\n', Qt::SkipEmptyParts)) {
        const QString trimmed = line.trimmed();
        if (!trimmed.isEmpty())
            lines.append(trimmed);
    }
    if (lines.size() > 4)
        lines = lines.sliced(lines.size() - 4);
    normalized = lines.join('\n');
    if (normalized.size() > 700)
        normalized = QStringLiteral("…") + normalized.right(699);
    if (m_notice == normalized)
        return;
    m_notice = normalized;
    emit noticeChanged();
}

void Controller::clearNotice()
{
    setNotice({});
}
