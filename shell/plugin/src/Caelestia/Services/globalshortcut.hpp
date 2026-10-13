#include <QtQml/qqmlregistration.h>
#pragma once

#include <QAction>
#include <QAtomicInt>
#include <QHash>
#include <QKeySequence>
#include <QList>
#include <QObject>
#include <QString>
#include <memory>

class GlobalShortcut;

class GlobalShortcutDispatcher : public QObject {
    Q_OBJECT

public:
    static GlobalShortcutDispatcher* instance();

    Q_INVOKABLE QString collisionForKey(const QString& portableKeyString) const;

    // Rebuilds the dispatcher's collision index from all current in-memory
    // stolen shortcuts. Called by GlobalShortcut::persistStolenShortcuts().
    void rebuildCollisionIndex();

    QHash<QString, QString> m_collisionIndex;

signals:
    void shortcutRegistered(GlobalShortcut* sc);
    void shortcutUnregistered(GlobalShortcut* sc);
    void collisionIndexChanged();
};

class GlobalShortcut : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(QString key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(QString description READ description WRITE setDescription NOTIFY descriptionChanged)

public:
    explicit GlobalShortcut(QObject* parent = nullptr);
    ~GlobalShortcut() override;

    QString name() const;
    void setName(const QString& name);

    QString key() const;
    void setKey(const QString& key);

    QString description() const;
    void setDescription(const QString& description);

    QString getCollisionName() const;
    QString getCollisionNameForKey(const QString& keyPart) const;

    int stolenCount() const { return m_stolenShortcuts.size(); }

    QString displayLabel() const;

signals:
    void nameChanged();
    void keyChanged();
    void descriptionChanged();
    void activated();

public:
    static GlobalShortcut* findByName(const QString& name);
    static QList<GlobalShortcut*> allShortcuts();
    static void rebuildCollisionIndex();

private:
    void updateShortcut();
    void persistStolenShortcuts() const;

    QString m_name;
    QString m_key;
    QString m_description;
    QAction* m_action;

    int m_registerGeneration = 0;

    static QHash<QString, GlobalShortcut*> s_registry;

    struct StolenShortcut {
        QString component;
        QString action;
        QList<QKeySequence> keys;
        QString componentFriendlyName;
        QString actionFriendlyName;
        QKeySequence triggerKey;
    };

    QList<StolenShortcut> m_stolenShortcuts;
    QList<QKeySequence> m_activeKeys;
};
