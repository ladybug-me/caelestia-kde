#pragma once

#include <QtQml/qqmlregistration.h>

#include <QObject>
#include <QSortFilterProxyModel>

class AudioDeviceFilterModel : public QSortFilterProxyModel {
    Q_OBJECT
    Q_PROPERTY(bool showInactiveDevices READ showInactiveDevices WRITE setShowInactiveDevices NOTIFY
            showInactiveDevicesChanged)

public:
    explicit AudioDeviceFilterModel(QObject* parent = nullptr);

    bool showInactiveDevices() const;
    void setShowInactiveDevices(bool show);

Q_SIGNALS:
    void showInactiveDevicesChanged();

protected:
    bool filterAcceptsRow(int source_row, const QModelIndex& source_parent) const override;

private:
    bool m_showInactiveDevices = false;
};

class CardFilterModel : public QSortFilterProxyModel {
    Q_OBJECT

public:
    enum CardRoles {
        DescriptionRole = Qt::UserRole + 100,
    };
    Q_ENUM(CardRoles)

    explicit CardFilterModel(QObject* parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
};

class AudioBackend : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool showInactiveDevices READ showInactiveDevices WRITE setShowInactiveDevices NOTIFY
            showInactiveDevicesChanged)
    Q_PROPERTY(QAbstractItemModel* sinks READ sinks CONSTANT)
    Q_PROPERTY(QAbstractItemModel* sources READ sources CONSTANT)
    Q_PROPERTY(QAbstractItemModel* cards READ cards CONSTANT)

public:
    explicit AudioBackend(QObject* parent = nullptr);
    ~AudioBackend() override;

    bool showInactiveDevices() const;
    void setShowInactiveDevices(bool show);

    QAbstractItemModel* sinks() const;
    QAbstractItemModel* sources() const;
    QAbstractItemModel* cards() const;

    Q_INVOKABLE bool isSinkInactive(const QString& name);
    Q_INVOKABLE bool isSourceInactive(const QString& name);
    Q_INVOKABLE QString cardDescription(QObject* card) const;

Q_SIGNALS:
    void showInactiveDevicesChanged();
    void devicesChanged();

private:
    void registerSink(QObject* sink);
    void registerSource(QObject* source);
    void registerCard(QObject* card);

private Q_SLOTS:
    void onSinkChanged();
    void onSourceChanged();
    void onCardChanged();

private:
    AudioDeviceFilterModel* m_sinksFilter;
    AudioDeviceFilterModel* m_sourcesFilter;
    CardFilterModel* m_cardModel;
    bool m_showInactiveDevices = false;
};
