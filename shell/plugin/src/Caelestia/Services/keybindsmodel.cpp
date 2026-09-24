#include "keybindsmodel.hpp"

#include <KGlobalAccel>
#include <KGlobalShortcutInfo>
#include <QCoreApplication>
#include <QDBusInterface>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>

#include "../Config/generalconfig.hpp"
#include "../Config/keybindsdefaults.hpp"
#include "../Config/rootnodes.hpp"

Q_LOGGING_CATEGORY(lcKeybinds, "caelestia.services.keybindsmodel", QtInfoMsg)

namespace caelestia::services {

KeybindsModel::KeybindsModel(QObject* parent)
    : QAbstractListModel(parent) {

    // Load keybinds JSON or populate defaults
    QString path = keybindsPath();
    QFile file(path);
    bool shouldSave = false;

    // Start with defaults
    QJsonObject defaults = caelestia::config::defaultKeybinds();
    bool krohnkiteEnabled = caelestia::config::ConfigSingleton::instance()->general()->krohnkiteEnabled();

    for (auto it = defaults.begin(); it != defaults.end(); ++it) {
        if (it.key().startsWith(QStringLiteral("krohnkite")) && !krohnkiteEnabled) {
            continue;
        }
        // Don't inject empty defaults into m_keybinds to allow QML to set the initial key
        if (!it.value().toString().isEmpty()) {
            m_keybinds.insert(it.key(), it.value().toString());
        }
    }

    if (file.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
            // Merge user JSON over defaults
            for (auto it = obj.begin(); it != obj.end(); ++it) {
                if (it.key().startsWith(QStringLiteral("krohnkite")) && !krohnkiteEnabled) {
                    continue;
                }
                if (it.value().isString()) {
                    m_keybinds.insert(it.key(), it.value().toString());
                }
            }
        }
    } else {
        shouldSave = true; // file didn't exist, save the generated defaults
    }

    connect(GlobalShortcutDispatcher::instance(), &GlobalShortcutDispatcher::shortcutRegistered, this,
        &KeybindsModel::onShortcutRegistered);
    connect(GlobalShortcutDispatcher::instance(), &GlobalShortcutDispatcher::shortcutUnregistered, this,
        &KeybindsModel::onShortcutUnregistered);
    // Re-evaluate blinker state whenever the collision index is rebuilt
    connect(GlobalShortcutDispatcher::instance(), &GlobalShortcutDispatcher::collisionIndexChanged, this,
        &KeybindsModel::keybindsChanged);

    m_saveTimer = new QTimer(this);
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(300);
    connect(m_saveTimer, &QTimer::timeout, this, &KeybindsModel::flushOverridesToDisk);

    m_loadTimer = new QTimer(this);
    m_loadTimer->setSingleShot(true);
    m_loadTimer->setInterval(10);
    connect(m_loadTimer, &QTimer::timeout, this, [this] {
        emit keybindsChanged();
        emit loaded();
    });

    for (GlobalShortcut* sc : GlobalShortcut::allShortcuts()) {
        onShortcutRegistered(sc);
    }

    if (shouldSave) {
        saveKeybinds();
    }
}

QVariantList KeybindsModel::keybinds() const {
    // The launcher service guards its load with keybinds.length and re-loads
    // whenever it reads an empty list, so the dummy kept it loading on every
    // startup and hid the data from anything else reading the property.
    // query() with no filter is the same map shape that path already uses.
    return query(QString());
}

bool KeybindsModel::initialized() const {
    return true; // We are initialized synchronously
}

void KeybindsModel::load() {
    emit loaded(); // Signal that we are loaded so QML can proceed
}

int KeybindsModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid())
        return 0;
    return m_rows.size();
}

QVariant KeybindsModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() >= m_rows.size())
        return QVariant();

    GlobalShortcut* sc = m_rows.at(index.row());

    switch (role) {
    case NameRole:
        return sc->name();
    case KeyRole:
        return sc->key();
    case DescriptionRole:
        return sc->description();
    case IsOverriddenRole: {
        QJsonObject defaults = caelestia::config::defaultKeybinds();
        return defaults.value(sc->name()).toString() != sc->key();
    }
    }
    return QVariant();
}

QHash<int, QByteArray> KeybindsModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[NameRole] = "name";
    roles[KeyRole] = "key";
    roles[DescriptionRole] = "description";
    roles[IsOverriddenRole] = "isOverridden";
    return roles;
}

void KeybindsModel::setKey(const QString& name, const QString& newKey) {
    GlobalShortcut* sc = GlobalShortcut::findByName(name);
    if (!sc)
        return;

    sc->setKey(newKey);
    m_keybinds.insert(name, newKey);

    m_saveTimer->start();
    emit keybindsChanged();
}

void KeybindsModel::resetKey(const QString& name) {
    QJsonObject defaults = caelestia::config::defaultKeybinds();
    if (defaults.contains(name)) {
        setKey(name, defaults.value(name).toString());
    } else {
        setKey(name, QStringLiteral(""));
    }
}

QString KeybindsModel::getKey(const QString& name) const {
    if (auto* sc = GlobalShortcut::findByName(name)) {
        return sc->key();
    }
    if (m_keybinds.contains(name)) {
        return m_keybinds.value(name);
    }
    QJsonObject defaults = caelestia::config::defaultKeybinds();
    return defaults.value(name).toString();
}

QVariantList KeybindsModel::query(const QString& searchText) const {
    QVariantList result;
    const auto lower = searchText.toLower();

    for (GlobalShortcut* sc : m_rows) {
        if (searchText.isEmpty() || sc->key().toLower().contains(lower) ||
            sc->description().toLower().contains(lower) || sc->name().toLower().contains(lower)) {

            QJsonObject defaults = caelestia::config::defaultKeybinds();
            result.append(QVariantMap{ { QStringLiteral("bind"), sc->key() }, { QStringLiteral("action"), sc->name() },
                { QStringLiteral("name"), sc->name() }, { QStringLiteral("description"), sc->description() },
                { QStringLiteral("isOverridden"), defaults.value(sc->name()).toString() != sc->key() } });
        }
    }
    return result;
}

void KeybindsModel::onShortcutRegistered(GlobalShortcut* sc) {
    if (m_rows.contains(sc))
        return;

    // Directly assign the key from our single source of truth
    if (m_keybinds.contains(sc->name())) {
        sc->setKey(m_keybinds.value(sc->name()));
    }

    const int row = m_rows.size();
    beginInsertRows(QModelIndex(), row, row);
    m_rows.append(sc);
    endInsertRows();

    if (QCoreApplication::instance()) {
        m_loadTimer->start();
    }

    connect(sc, &GlobalShortcut::keyChanged, this, [this, sc] {
        int idx = m_rows.indexOf(sc);
        if (idx >= 0) {
            emit dataChanged(index(idx), index(idx), { KeyRole, IsOverriddenRole });
            if (QCoreApplication::instance()) {
                m_loadTimer->start();
            }
        }
    });
}

QString KeybindsModel::getKeyCollision(const QString& actionName) const {
    if (actionName.isEmpty())
        return QString();

    GlobalShortcut* sc = GlobalShortcut::findByName(actionName);
    if (!sc) {
        qDebug() << "[Caelestia] getKeyCollision: no shortcut found for" << actionName;
        return QString();
    }
    QString result = sc->getCollisionName();
    if (!result.isEmpty()) {
        qDebug() << "[Caelestia] getKeyCollision(" << actionName << ") = " << result;
    } else {
        qDebug() << "[Caelestia] getKeyCollision(" << actionName << ") = (empty) stolenCount=" << sc->stolenCount();
    }
    return result;
}

QString KeybindsModel::getKeyCollisionForPart(const QString& actionName, const QString& keyPart) const {
    if (actionName.isEmpty() || keyPart.isEmpty())
        return QString();

    // Query the central collision index which is backed by stolen-shortcuts.json.
    // Using a portable key string as the lookup key matches what the dispatcher stores.
    QKeySequence seq(keyPart.trimmed());
    if (seq.isEmpty())
        return QString();

    return GlobalShortcutDispatcher::instance()->collisionForKey(seq.toString(QKeySequence::PortableText));
}

void KeybindsModel::onShortcutUnregistered(GlobalShortcut* sc) {
    int idx = m_rows.indexOf(sc);
    if (idx >= 0) {
        beginRemoveRows(QModelIndex(), idx, idx);
        m_rows.removeAt(idx);
        endRemoveRows();
        if (QCoreApplication::instance()) {
            m_loadTimer->start();
        }
    }
}

QString KeybindsModel::keybindsPath() const {
    return QDir::homePath() + QStringLiteral("/.config/caelestia/keybinds.json");
}

void KeybindsModel::saveKeybinds() {
    QString path = keybindsPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning(lcKeybinds) << "Failed to save keybinds to" << path;
        return;
    }

    QJsonObject obj;
    for (auto it = m_keybinds.begin(); it != m_keybinds.end(); ++it) {
        obj.insert(it.key(), it.value());
    }

    QJsonDocument doc(obj);
    file.write(doc.toJson());
}

void KeybindsModel::flushOverridesToDisk() {
    saveKeybinds();
}

} // namespace caelestia::services
