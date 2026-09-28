// SPDX-License-Identifier: GPL-3.0-only
#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QList>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariant>

#include "globalshortcut.hpp"

namespace caelestia::services {

class KeybindsModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        KeyRole,
        DescriptionRole,
        IsOverriddenRole,
    };

    Q_PROPERTY(QVariantList keybinds READ keybinds NOTIFY keybindsChanged)
    Q_PROPERTY(bool initialized READ initialized NOTIFY initializedChanged)

    explicit KeybindsModel(QObject* parent = nullptr);

    [[nodiscard]] QVariantList keybinds() const;
    [[nodiscard]] bool initialized() const;

    Q_INVOKABLE void load();

    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void setKey(const QString& name, const QString& newKey);
    Q_INVOKABLE void resetKey(const QString& name);
    Q_INVOKABLE QString getKey(const QString& name) const;
    Q_INVOKABLE QVariantList query(const QString& searchText) const;
    Q_INVOKABLE QString getKeyCollision(const QString& actionName) const;
    Q_INVOKABLE QString getKeyCollisionForPart(const QString& actionName, const QString& keyPart) const;

signals:
    void keybindsChanged();
    void initializedChanged();
    void loaded();

private slots:
    void onShortcutRegistered(GlobalShortcut* sc);
    void onShortcutUnregistered(GlobalShortcut* sc);
    void flushOverridesToDisk();

private:
    QList<GlobalShortcut*> m_rows;
    QHash<QString, QString> m_keybinds;
    QTimer* m_saveTimer = nullptr;
    QTimer* m_loadTimer = nullptr;

    QString keybindsPath() const;
    void saveKeybinds();
};

} // namespace caelestia::services
