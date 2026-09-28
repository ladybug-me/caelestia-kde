#include "kwinworkspacestate.hpp"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusReply>
#include <QDebug>
#include <QLocalServer>
#include <QLocalSocket>
#include <QStandardPaths>
#include <algorithm>

namespace caelestia::services {

QDBusArgument& operator<<(QDBusArgument& argument, const KWinDesktopData& data) {
    argument.beginStructure();
    argument << data.position << data.id << data.name;
    argument.endStructure();
    return argument;
}

const QDBusArgument& operator>>(const QDBusArgument& argument, KWinDesktopData& data) {
    argument.beginStructure();
    argument >> data.position >> data.id >> data.name;
    argument.endStructure();
    return argument;
}

static KWinWorkspaceState* s_instance = nullptr;

KWinWorkspaceState* KWinWorkspaceState::instance() {
    return s_instance;
}

int KWinWorkspaceState::indexForId(const QString& id) const {
    for (int i = 0; i < m_desktops.size(); ++i) {
        if (m_desktops[i].id == id) {
            return i + 1;
        }
    }
    return -1;
}

QString KWinWorkspaceState::uuidForIndex(int index) const {
    int pos = index - 1;
    if (pos >= 0 && pos < m_desktops.size()) {
        return m_desktops[pos].id;
    }
    return QString();
}

uint KWinWorkspaceState::rows() const {
    return m_rows;
}

double KWinWorkspaceState::swipeOffset() const {
    return m_swipeOffset;
}

QVariantMap KWinWorkspaceState::swipeOffsetByOutput() const {
    return m_swipeOffsetByOutput;
}

bool KWinWorkspaceState::showingDesktop() const {
    return m_showingDesktop;
}

KWinWorkspaceState::KWinWorkspaceState(QObject* parent)
    : QObject(parent) {
    s_instance = this;
    qDBusRegisterMetaType<KWinDesktopData>();
    qDBusRegisterMetaType<QList<KWinDesktopData>>();

    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
        QStringLiteral("org.kde.KWin.VirtualDesktopManager"), QStringLiteral("desktopCreated"), this,
        SLOT(onDesktopCreated(QString, caelestia::services::KWinDesktopData)));
    bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
        QStringLiteral("org.kde.KWin.VirtualDesktopManager"), QStringLiteral("desktopRemoved"), this,
        SLOT(onDesktopRemoved(QString)));
    bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
        QStringLiteral("org.kde.KWin.VirtualDesktopManager"), QStringLiteral("desktopDataChanged"), this,
        SLOT(onDesktopDataChanged(QString, caelestia::services::KWinDesktopData)));
    bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
        QStringLiteral("org.kde.KWin.VirtualDesktopManager"), QStringLiteral("currentChanged"), this,
        SLOT(onCurrentChanged(QString)));
    bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
        QStringLiteral("org.kde.KWin.VirtualDesktopManager"), QStringLiteral("countChanged"), this,
        SLOT(onCountChanged(uint)));
    bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
        QStringLiteral("org.kde.KWin.VirtualDesktopManager"), QStringLiteral("rowsChanged"), this,
        SLOT(onRowsChanged(uint)));

    bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"),
        QStringLiteral("showingDesktopChanged"), this, SLOT(onShowingDesktopChanged(bool)));
    bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"), this,
        SLOT(onKWinPropertiesChanged(QString, QVariantMap, QStringList)));

    fetchInitialState();
    setupTrackerServer();
}

KWinWorkspaceState::~KWinWorkspaceState() {
    if (m_trackerServer) {
        m_trackerServer->close();
        m_trackerServer->deleteLater();
    }
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

void KWinWorkspaceState::setupTrackerServer() {
    m_trackerServer = new QLocalServer(this);
    QString socketPath = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) +
                         QStringLiteral("/caelestia-workspace-tracker");
    QLocalServer::removeServer(socketPath);

    qDebug() << "KWinWorkspaceState: Setting up tracker server at" << socketPath;

    if (m_trackerServer->listen(socketPath)) {
        connect(m_trackerServer, &QLocalServer::newConnection, this, [this]() {
            qDebug() << "KWinWorkspaceState: New connection to tracker server";
            QLocalSocket* clientSocket = m_trackerServer->nextPendingConnection();
            connect(clientSocket, &QLocalSocket::readyRead, this, [this, clientSocket]() {
                constexpr quint32 kMagic = 0x43414557;
                struct DesktopReport {
                    quint32 magic;
                    qint32 desktop;
                    float x;
                    float y;
                    char output[64];
                };
                static_assert(sizeof(DesktopReport) == 80, "must match the effect's layout byte for byte");

                struct LegacyTransition {
                    int desktop;
                    float x;
                    float y;
                };

                while (clientSocket->bytesAvailable() >= static_cast<qint64>(sizeof(LegacyTransition))) {
                    quint32 magic = 0;
                    clientSocket->peek(reinterpret_cast<char*>(&magic), sizeof(magic));

                    if (magic == kMagic) {
                        if (clientSocket->bytesAvailable() < static_cast<qint64>(sizeof(DesktopReport))) {
                            break;
                        }
                        DesktopReport report;
                        clientSocket->read(reinterpret_cast<char*>(&report), sizeof(report));
                        report.output[sizeof(report.output) - 1] = '\0';

                        const QString output = QString::fromUtf8(report.output);
                        const double offset = static_cast<double>(report.x);

                        if (!output.isEmpty()) {
                            if (report.desktop > 0) {
                                if (m_activeByOutput.value(output).toInt() != report.desktop) {
                                    m_activeByOutput.insert(output, report.desktop);
                                    emit activeByOutputChanged();
                                }
                            }
                            if (!qFuzzyCompare(m_swipeOffsetByOutput.value(output).toDouble() + 1.0, offset + 1.0)) {
                                m_swipeOffsetByOutput.insert(output, offset);
                                emit swipeOffsetByOutputChanged();
                            }
                        } else {
                            if (report.desktop > 0) {
                                const QString uuid = uuidForIndex(report.desktop);
                                if (!uuid.isEmpty() && m_currentUuid != uuid) {
                                    m_currentUuid = uuid;
                                    updateActiveId();
                                }
                            }
                            if (!qFuzzyCompare(m_swipeOffset + 1.0, offset + 1.0)) {
                                m_swipeOffset = offset;
                                emit swipeOffsetChanged();
                            }
                        }
                    } else {
                        LegacyTransition payload;
                        clientSocket->read(reinterpret_cast<char*>(&payload), sizeof(payload));
                        if (payload.desktop > 0) {
                            const QString uuid = uuidForIndex(payload.desktop);
                            if (!uuid.isEmpty() && m_currentUuid != uuid) {
                                m_currentUuid = uuid;
                                updateActiveId();
                            }
                        }
                        const double offset = static_cast<double>(payload.x);
                        if (!qFuzzyCompare(m_swipeOffset + 1.0, offset + 1.0)) {
                            m_swipeOffset = offset;
                            emit swipeOffsetChanged();
                        }
                    }
                }
            });
            connect(clientSocket, &QLocalSocket::disconnected, clientSocket, &QLocalSocket::deleteLater);
        });
    } else {
        qDebug() << "Failed to start workspace tracker server:" << m_trackerServer->errorString();
    }
}

void KWinWorkspaceState::fetchInitialState() {
    QDBusMessage msg =
        QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
            QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    msg << QStringLiteral("org.kde.KWin.VirtualDesktopManager") << QStringLiteral("desktops");
    QDBusReply<QDBusVariant> reply = QDBusConnection::sessionBus().call(msg);

    if (reply.isValid()) {
        QVariant var = reply.value().variant();
        if (var.canConvert<QDBusArgument>()) {
            QDBusArgument arg = var.value<QDBusArgument>();
            arg >> m_desktops;
        }
    }

    QDBusMessage currentMsg =
        QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
            QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    currentMsg << QStringLiteral("org.kde.KWin.VirtualDesktopManager") << QStringLiteral("current");
    QDBusReply<QDBusVariant> currentReply = QDBusConnection::sessionBus().call(currentMsg);

    if (currentReply.isValid()) {
        m_currentUuid = currentReply.value().variant().toString();
    }

    QDBusMessage rowsMsg =
        QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
            QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    rowsMsg << QStringLiteral("org.kde.KWin.VirtualDesktopManager") << QStringLiteral("rows");
    QDBusReply<QDBusVariant> rowsReply = QDBusConnection::sessionBus().call(rowsMsg);

    if (rowsReply.isValid()) {
        const uint rows = rowsReply.value().variant().toUInt();
        if (rows > 0 && rows != m_rows) {
            m_rows = rows;
            emit rowsChanged();
        }
    }

    QDBusMessage showingMsg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    showingMsg << QStringLiteral("org.kde.KWin") << QStringLiteral("showingDesktop");
    QDBusReply<QDBusVariant> showingReply = QDBusConnection::sessionBus().call(showingMsg);
    if (showingReply.isValid()) {
        updateShowingDesktop(showingReply.value().variant().toBool());
    }

    updateActiveId();
}

void KWinWorkspaceState::onShowingDesktopChanged(bool showing) {
    updateShowingDesktop(showing);
}

void KWinWorkspaceState::onKWinPropertiesChanged(
    const QString& interface, const QVariantMap& changedProps, const QStringList& invalidatedProps) {
    Q_UNUSED(interface)
    Q_UNUSED(invalidatedProps)
    if (changedProps.contains(QStringLiteral("showingDesktop"))) {
        updateShowingDesktop(changedProps.value(QStringLiteral("showingDesktop")).toBool());
    }
}

void KWinWorkspaceState::updateShowingDesktop(bool showing) {
    if (showing != m_showingDesktop) {
        m_showingDesktop = showing;
        emit showingDesktopChanged();
    }
}

void KWinWorkspaceState::updateActiveId() {
    std::sort(m_desktops.begin(), m_desktops.end(), [](const KWinDesktopData& a, const KWinDesktopData& b) {
        return a.position < b.position;
    });

    int newActiveId = 1;
    for (int i = 0; i < m_desktops.size(); ++i) {
        if (m_desktops[i].id == m_currentUuid) {
            newActiveId = i + 1;
            break;
        }
    }

    if (m_activeId != newActiveId) {
        m_activeId = newActiveId;
        emit activeIdChanged();
    }

    emit workspacesChanged();
}

QVariantMap KWinWorkspaceState::activeByOutput() const {
    return m_activeByOutput;
}

int KWinWorkspaceState::activeId() const {
    return m_activeId;
}

QVariantList KWinWorkspaceState::workspaces() const {
    QVariantList list;
    for (int i = 0; i < m_desktops.size(); ++i) {
        const auto& d = m_desktops[i];
        if (d.id.isEmpty())
            continue;
        list.append(QVariantMap{ { QStringLiteral("id"), d.id },
            { QStringLiteral("name"), d.name.isEmpty() ? QString::number(i + 1) : d.name },
            { QStringLiteral("index"), i + 1 }, { QStringLiteral("active"), (d.id == m_currentUuid) } });
    }
    return list;
}

QString KWinWorkspaceState::resolveDesktopUuid(const QString& id) const {
    // Numeric ids select by position (Meta+N -> setDesktop(N)). Resolve those
    // before names so a desktop custom-named "3" cannot shadow the actual
    // third desktop.
    const bool numeric = id.toInt() > 0;
    for (const auto& d : m_desktops) {
        if (d.id == id) {
            return d.id;
        }
        if (numeric && QString::number(d.position + 1) == id) {
            return d.id;
        }
    }
    for (const auto& d : m_desktops) {
        if (d.name == id) {
            return d.id;
        }
    }
    return QString();
}

void KWinWorkspaceState::switchTo(const QString& id, const QString& output) {
    const QString targetUuid = resolveDesktopUuid(id);

    if (!targetUuid.isEmpty()) {
        if (!output.isEmpty()) {
            if (m_perOutputSwitchAvailable == -1) {
                QDBusMessage probe = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
                    QStringLiteral("/Caelestia/Workspaces"), QStringLiteral("org.freedesktop.DBus.Introspectable"),
                    QStringLiteral("Introspect"));
                const QDBusMessage reply = QDBusConnection::sessionBus().call(probe, QDBus::Block, 1000);
                m_perOutputSwitchAvailable =
                    (reply.type() == QDBusMessage::ReplyMessage &&
                        reply.arguments().value(0).toString().contains(QStringLiteral("SetDesktop")))
                        ? 1
                        : 0;
                if (!m_perOutputSwitchAvailable) {
                    qWarning() << "KWinWorkspaceState: workspace-tracker effect has no SetDesktop; "
                                  "falling back to switching the active output's desktop";
                }
            }

            if (m_perOutputSwitchAvailable == 1) {
                QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
                    QStringLiteral("/Caelestia/Workspaces"), QStringLiteral("org.caelestia.Workspaces"),
                    QStringLiteral("SetDesktop"));
                msg << output << indexForId(targetUuid);
                QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
                return;
            }
        }

        QDBusMessage msg =
            QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
                QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
        msg << QStringLiteral("org.kde.KWin.VirtualDesktopManager") << QStringLiteral("current")
            << QVariant::fromValue(QDBusVariant(targetUuid));
        QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
    }
}

void KWinWorkspaceState::setDesktop(int desktopId) {
    switchTo(QString::number(desktopId));
}

void KWinWorkspaceState::nextDesktop() {
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
        QStringLiteral("org.kde.KWin"), QStringLiteral("nextDesktop"));
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void KWinWorkspaceState::previousDesktop() {
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
        QStringLiteral("org.kde.KWin"), QStringLiteral("previousDesktop"));
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void KWinWorkspaceState::setShowingDesktop(bool showing) {
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
        QStringLiteral("org.kde.KWin"), QStringLiteral("showDesktop"));
    msg << showing;
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void KWinWorkspaceState::createWorkspace(const QString& name) {
    QDBusMessage msg =
        QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
            QStringLiteral("org.kde.KWin.VirtualDesktopManager"), QStringLiteral("createDesktop"));
    msg << std::numeric_limits<uint32_t>::max() << name;
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void KWinWorkspaceState::removeWorkspace(const QString& id) {
    const QString targetUuid = resolveDesktopUuid(id);

    if (!targetUuid.isEmpty()) {
        QDBusMessage msg =
            QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/VirtualDesktopManager"),
                QStringLiteral("org.kde.KWin.VirtualDesktopManager"), QStringLiteral("removeDesktop"));
        msg << targetUuid;
        QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
    }
}

void KWinWorkspaceState::onDesktopCreated(const QString& id, const caelestia::services::KWinDesktopData& desktopData) {
    bool exists = false;
    for (auto& d : m_desktops) {
        if (d.id == id) {
            d = desktopData;
            exists = true;
            break;
        }
    }
    if (!exists) {
        m_desktops.append(desktopData);
    }
    updateActiveId();
}

void KWinWorkspaceState::onDesktopRemoved(const QString& id) {
    for (int i = 0; i < m_desktops.size(); ++i) {
        if (m_desktops[i].id == id) {
            m_desktops.removeAt(i);
            break;
        }
    }
    updateActiveId();
}

void KWinWorkspaceState::onDesktopDataChanged(
    const QString& id, const caelestia::services::KWinDesktopData& desktopData) {
    for (auto& d : m_desktops) {
        if (d.id == id) {
            d = desktopData;
            break;
        }
    }
    updateActiveId();
}

void KWinWorkspaceState::onCurrentChanged(const QString& id) {
    m_currentUuid = id;
    updateActiveId();
}

void KWinWorkspaceState::onCountChanged(uint count) {}

void KWinWorkspaceState::onRowsChanged(uint rows) {
    if (rows > 0 && rows != m_rows) {
        m_rows = rows;
        emit rowsChanged();
    }
}

} // namespace caelestia::services
