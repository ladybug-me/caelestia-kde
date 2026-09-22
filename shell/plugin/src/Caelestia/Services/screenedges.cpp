// SPDX-License-Identifier: GPL-3.0-only
#include "screenedges.hpp"

#include <KConfigGroup>
#include <KSharedConfig>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTextStream>

namespace caelestia::services {

namespace {

constexpr auto kwinService = "org.kde.KWin";

QString stolenEdgesPath() {
    return QDir::homePath() + QStringLiteral("/.config/caelestia/stolen-screen-edges.json");
}

/// The [ElectricBorders] key that names a corner, or empty if not a corner.
QString electricBorderKey(int corner) {
    switch (corner) {
    case ScreenEdges::TopLeft:
        return QStringLiteral("TopLeft");
    case ScreenEdges::TopRight:
        return QStringLiteral("TopRight");
    case ScreenEdges::BottomLeft:
        return QStringLiteral("BottomLeft");
    case ScreenEdges::BottomRight:
        return QStringLiteral("BottomRight");
    default:
        return {};
    }
}

/// Groups whose BorderActivate-ish keys reserve an edge. Effects and scripts
/// each get their own group, and the task switcher has a fixed one.
bool ownsEdges(const QString& group) {
    return group.startsWith(QStringLiteral("Effect-")) || group.startsWith(QStringLiteral("Script-")) ||
           group == QStringLiteral("TabBox") || group == QStringLiteral("TabBoxAlternative");
}

/// Every key shape KWin reads an edge int-list out of, pointer and touch
/// alike: BorderActivate, GridBorderActivate, BorderActivateAll,
/// BorderAlternativeActivate, TouchBorderActivate, GridTouchBorderActivate,
/// TouchBorderAlternativeActivate, ...
///
/// The separate [TouchEdges] group needs no handling: it only has Top/Right/
/// Bottom/Left keys, so a corner cannot be bound there in the first place.
bool isEdgeListKey(const QString& key) {
    return key.contains(QStringLiteral("BorderActivate")) || key.contains(QStringLiteral("BorderAlternativeActivate"));
}

/// KWin writes these lists as comma-separated ints; ElectricNone is 9.
QList<int> parseEdgeList(const QString& raw) {
    QList<int> out;
    const auto parts = raw.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString& part : parts) {
        bool ok = false;
        const int v = part.trimmed().toInt(&ok);
        if (ok) {
            out.append(v);
        }
    }
    return out;
}

QString formatEdgeList(const QList<int>& edges) {
    QStringList parts;
    for (int e : edges) {
        parts.append(QString::number(e));
    }
    // An empty list must still be written as an explicit ElectricNone rather
    // than an empty value, or KConfig falls back to the compiled-in default —
    // which for [Effect-overview] BorderActivate is top-left, the very corner
    // we are trying to take.
    return parts.isEmpty() ? QStringLiteral("9") : parts.join(QLatin1Char(','));
}

/// Keys whose compiled-in default reserves an edge even when absent from
/// kwinrc, so a stock install still has to be written over explicitly.
const QHash<QString, QList<int>>& implicitDefaults() {
    static const QHash<QString, QList<int>> defaults{
        // src/plugins/overview/overviewconfig.kcfg: <default>ElectricTopLeft</default>
        { QStringLiteral("Effect-overview/BorderActivate"), { ScreenEdges::TopLeft } },
    };
    return defaults;
}

/// org.kde.KWin.reconfigure() is not enough on its own. It reloads the
/// built-in edge actions, but an effect that has already reserved an edge can
/// keep that reservation across it — KWin then goes on firing the effect from
/// a corner its own config says is free, which is exactly the "KDE's overview
/// opens too" symptom. Effect::reconfigure() is what unreserves and re-reserves
/// from freshly-read config, and the only way to force it per effect is the
/// Effects interface.
void reconfigureEffect(const QString& effect) {
    QDBusMessage msg = QDBusMessage::createMethodCall(QLatin1String(kwinService), QStringLiteral("/Effects"),
        QStringLiteral("org.kde.kwin.Effects"), QStringLiteral("reconfigureEffect"));
    msg << effect;
    // NoBlock, not asyncCall: this also runs from aboutToQuit, where nothing
    // is left to deliver a reply to, but the message still has to reach the
    // socket before the process goes away.
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

/// Every effect that has any edge key in kwinrc, whether or not we touched it
/// — a stale reservation has to be flushed even when the value on disk was
/// already harmless.
QStringList effectsOwningEdges() {
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    QStringList effects;
    const QStringList groups = config->groupList();
    for (const QString& groupName : groups) {
        static const QString prefix = QStringLiteral("Effect-");
        if (!groupName.startsWith(prefix)) {
            continue;
        }
        const QStringList keys = config->group(groupName).keyList();
        for (const QString& key : keys) {
            if (isEdgeListKey(key)) {
                effects.append(groupName.mid(prefix.size()));
                break;
            }
        }
    }
    return effects;
}

void applyToKwin() {
    QDBusConnection::sessionBus().call(
        QDBusMessage::createMethodCall(QLatin1String(kwinService), QStringLiteral("/KWin"), QLatin1String(kwinService),
            QStringLiteral("reconfigure")),
        QDBus::NoBlock);
    const QStringList effects = effectsOwningEdges();
    for (const QString& effect : effects) {
        reconfigureEffect(effect);
    }
}

} // namespace

ScreenEdges::ScreenEdges(QObject* parent)
    : QObject(parent)
    , m_reconfigureTimer(new QTimer(this)) {
    // Claiming four corners in a row is four config writes but only needs one
    // reconfigure, and each one is a full KWin settings reload.
    m_reconfigureTimer->setSingleShot(true);
    m_reconfigureTimer->setInterval(50);
    connect(m_reconfigureTimer, &QTimer::timeout, this, [] {
        applyToKwin();
    });

    recoverFromCrash();

    if (QCoreApplication::instance()) {
        connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, [this] {
            restoreAll();
        });
    }
}

ScreenEdges::~ScreenEdges() {
    restoreAll();
}

bool ScreenEdges::available() const {
    auto* iface = QDBusConnection::sessionBus().interface();
    return iface && iface->isServiceRegistered(QLatin1String(kwinService));
}

bool ScreenEdges::holds(int corner) const {
    return m_stolen.contains(corner);
}

void ScreenEdges::recoverFromCrash() {
    QFile file(stolenEdgesPath());
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    bool restored = false;
    if (doc.isArray()) {
        const QJsonArray entries = doc.array();
        for (const QJsonValue& val : entries) {
            const StolenEdge stolen = fromJson(val.toObject());
            if (stolen.corner != 0) {
                qDebug() << "[Caelestia] Crash recovery: restoring screen corner" << stolen.corner;
                restoreCorner(stolen);
                restored = true;
            }
        }
    }
    QFile::remove(stolenEdgesPath());

    // restoreCorner() only rewrites kwinrc, and KWin does not re-read that on
    // its own, so the corners the previous run reserved would stay reserved
    // until something else happened to reconfigure. The recovery file is gone
    // by the time we reach here, so this push is the last chance to apply it.
    if (restored) {
        scheduleReconfigure();
    }
}

void ScreenEdges::claim(int corner) {
    if (electricBorderKey(corner).isEmpty() || m_stolen.contains(corner)) {
        return;
    }
    stealCorner(corner);
    persist();
    scheduleReconfigure();
}

void ScreenEdges::release(int corner) {
    const auto it = m_stolen.constFind(corner);
    if (it == m_stolen.constEnd()) {
        return;
    }
    restoreCorner(*it);
    m_stolen.remove(corner);
    persist();
    scheduleReconfigure();
}

void ScreenEdges::stealCorner(int corner) {
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    StolenEdge stolen;
    stolen.corner = corner;

    // 1. The built-in action, if any.
    const QString borderKey = electricBorderKey(corner);
    KConfigGroup electric = config->group(QStringLiteral("ElectricBorders"));
    const QString action = electric.readEntry(borderKey, QString());
    if (!action.isEmpty() && action != QStringLiteral("None")) {
        stolen.entries[QStringLiteral("ElectricBorders")][borderKey] = action;
        electric.writeEntry(borderKey, QStringLiteral("None"));
    }

    // 2. Every effect/script/switcher that reserved this edge.
    const QStringList groups = config->groupList();
    QSet<QString> visited;
    for (const QString& groupName : groups) {
        if (!ownsEdges(groupName)) {
            continue;
        }
        visited.insert(groupName);
        KConfigGroup group = config->group(groupName);
        const QStringList keys = group.keyList();
        for (const QString& key : keys) {
            if (!isEdgeListKey(key)) {
                continue;
            }
            const QString raw = group.readEntry(key, QString());
            QList<int> edges = parseEdgeList(raw);
            if (!edges.contains(corner)) {
                continue;
            }
            stolen.entries[groupName][key] = raw;
            edges.removeAll(corner);
            group.writeEntry(key, formatEdgeList(edges));
        }
    }

    // 3. Keys that reserve this edge purely by compiled-in default, i.e. the
    // group or key isn't in kwinrc at all yet. A null stashed value records
    // "was absent", so restoring deletes the key rather than writing a value
    // the user never had.
    for (auto it = implicitDefaults().constBegin(); it != implicitDefaults().constEnd(); ++it) {
        if (!it.value().contains(corner)) {
            continue;
        }
        const QString groupName = it.key().section(QLatin1Char('/'), 0, 0);
        const QString key = it.key().section(QLatin1Char('/'), 1);
        KConfigGroup group = config->group(groupName);
        if (group.hasKey(key)) {
            continue; // already handled above from its real value
        }
        stolen.entries[groupName][key] = QString();
        group.writeEntry(key, QStringLiteral("9"));
    }

    config->sync();
    m_stolen.insert(corner, stolen);
}

void ScreenEdges::restoreCorner(const StolenEdge& stolen) {
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    for (auto git = stolen.entries.constBegin(); git != stolen.entries.constEnd(); ++git) {
        KConfigGroup group = config->group(git.key());
        const auto& keys = git.value();
        for (auto kit = keys.constBegin(); kit != keys.constEnd(); ++kit) {
            if (kit.value().isNull()) {
                group.deleteEntry(kit.key());
            } else {
                group.writeEntry(kit.key(), kit.value());
            }
        }
    }
    config->sync();
}

void ScreenEdges::restoreAll() {
    if (m_restored) {
        return;
    }
    m_restored = true;

    for (const StolenEdge& stolen : std::as_const(m_stolen)) {
        restoreCorner(stolen);
    }
    m_stolen.clear();
    QFile::remove(stolenEdgesPath());

    // Exit path: the coalescing timer will never fire, so push it out now.
    applyToKwin();
}

QJsonObject ScreenEdges::toJson(const StolenEdge& stolen) const {
    QJsonObject groups;
    for (auto git = stolen.entries.constBegin(); git != stolen.entries.constEnd(); ++git) {
        QJsonObject keys;
        for (auto kit = git.value().constBegin(); kit != git.value().constEnd(); ++kit) {
            // null -> JSON null, meaning "delete this key on restore"
            keys.insert(kit.key(), kit.value().isNull() ? QJsonValue() : QJsonValue(kit.value()));
        }
        groups.insert(git.key(), keys);
    }
    return QJsonObject{ { QStringLiteral("corner"), stolen.corner }, { QStringLiteral("entries"), groups } };
}

ScreenEdges::StolenEdge ScreenEdges::fromJson(const QJsonObject& obj) const {
    StolenEdge stolen;
    stolen.corner = obj.value(QStringLiteral("corner")).toInt();
    const QJsonObject groups = obj.value(QStringLiteral("entries")).toObject();
    for (auto git = groups.constBegin(); git != groups.constEnd(); ++git) {
        const QJsonObject keys = git.value().toObject();
        for (auto kit = keys.constBegin(); kit != keys.constEnd(); ++kit) {
            stolen.entries[git.key()][kit.key()] = kit.value().isNull() ? QString() : kit.value().toString();
        }
    }
    return stolen;
}

void ScreenEdges::persist() const {
    const QString path = stolenEdgesPath();
    if (m_stolen.isEmpty()) {
        QFile::remove(path);
        return;
    }

    QJsonArray entries;
    for (const StolenEdge& stolen : std::as_const(m_stolen)) {
        entries.append(toJson(stolen));
    }

    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(entries).toJson(QJsonDocument::Indented));
        file.close();
    }
}

void ScreenEdges::scheduleReconfigure() {
    m_reconfigureTimer->start();
}

} // namespace caelestia::services
