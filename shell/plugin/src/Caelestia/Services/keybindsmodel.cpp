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

    QString path = keybindsPath();
    QFile file(path);
    bool shouldSave = false;

    QJsonObject defaults = caelestia::config::defaultKeybinds();
    m_defaults = defaults;
    bool krohnkiteEnabled = caelestia::config::ConfigSingleton::instance()->general()->krohnkiteEnabled();

    m_keybinds.reserve(defaults.size());
    for (auto it = defaults.begin(); it != defaults.end(); ++it) {
        if (it.key().startsWith(QStringLiteral("krohnkite")) && !krohnkiteEnabled) {
            continue;
        }
        if (!it.value().toString().isEmpty()) {
            m_keybinds.insert(it.key(), it.value().toString());
        }
    }

    if (file.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
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
        shouldSave = true;
    }

    connect(GlobalShortcutDispatcher::instance(), &GlobalShortcutDispatcher::shortcutRegistered, this,
        &KeybindsModel::onShortcutRegistered);
    connect(GlobalShortcutDispatcher::instance(), &GlobalShortcutDispatcher::shortcutUnregistered, this,
        &KeybindsModel::onShortcutUnregistered);
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
    return query(QString());
}

bool KeybindsModel::initialized() const {
    return true;
}

void KeybindsModel::load() {
    emit loaded();
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
        return m_defaults.value(sc->name()).toString() != sc->key();
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
    QString defaultKey;
    if (defaults.contains(name)) {
        defaultKey = defaults.value(name).toString();
    }
    setKey(name, defaultKey);
    if (defaultKey.isEmpty()) {
        return;
    }
    // Like Replace: take the default back, clearing it from whoever holds it.
    for (GlobalShortcut* sc : GlobalShortcut::allShortcuts()) {
        if (sc->name() == name) {
            continue;
        }
        QStringList parts = sc->key().split(QStringLiteral(";"));
        bool changed = false;
        for (int i = parts.size() - 1; i >= 0; --i) {
            if (parts[i].trimmed() == defaultKey) {
                parts.removeAt(i);
                changed = true;
            }
        }
        if (changed) {
            setKey(sc->name(), parts.join(QStringLiteral("; ")));
        }
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
    QList<GlobalShortcut*> matches;
    const auto lower = searchText.toLower();

    for (GlobalShortcut* sc : m_rows) {
        if (searchText.isEmpty()) {
            matches.append(sc);
        } else {
            const QString& cached = m_lowerCache.value(sc->name());
            if (cached.contains(lower)) {
                matches.append(sc);
            }
        }
    }

    std::sort(matches.begin(), matches.end(), [](GlobalShortcut* a, GlobalShortcut* b) {
        const QString strA = a->description().isEmpty() ? a->name() : a->description();
        const QString strB = b->description().isEmpty() ? b->name() : b->description();
        return strA.localeAwareCompare(strB) < 0;
    });

    QVariantList result;
    result.reserve(matches.size());
    for (GlobalShortcut* sc : std::as_const(matches)) {
        result.append(QVariantMap{ { QStringLiteral("bind"), sc->key() }, { QStringLiteral("action"), sc->name() },
            { QStringLiteral("name"), sc->name() }, { QStringLiteral("description"), sc->description() },
            { QStringLiteral("isOverridden"), m_defaults.value(sc->name()).toString() != sc->key() } });
    }

    return result;
}

void KeybindsModel::updateLowerCache(GlobalShortcut* sc) {
    m_lowerCache.insert(sc->name(), (sc->key() + u' ' + sc->description() + u' ' + sc->name()).toLower());
}

void KeybindsModel::onShortcutRegistered(GlobalShortcut* sc) {
    if (m_rows.contains(sc))
        return;

    if (m_keybinds.contains(sc->name())) {
        sc->setKey(m_keybinds.value(sc->name()));
    }

    const int row = m_rows.size();
    beginInsertRows(QModelIndex(), row, row);
    m_rows.append(sc);
    endInsertRows();
    updateLowerCache(sc);

    if (QCoreApplication::instance()) {
        m_loadTimer->start();
    }

    connect(sc, &GlobalShortcut::keyChanged, this, [this, sc] {
        int idx = m_rows.indexOf(sc);
        if (idx >= 0) {
            updateLowerCache(sc);
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
        m_lowerCache.remove(sc->name());
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
