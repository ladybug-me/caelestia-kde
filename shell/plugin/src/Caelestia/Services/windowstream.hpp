#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>

namespace caelestia::services {

class WindowStream : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString address READ address WRITE setAddress NOTIFY addressChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(quint32 nodeId READ nodeId NOTIFY streamChanged)
    Q_PROPERTY(quint64 objectSerial READ objectSerial NOTIFY streamChanged)
    Q_PROPERTY(bool available READ available NOTIFY streamChanged)
    QML_ELEMENT

public:
    explicit WindowStream(QObject* parent = nullptr);
    ~WindowStream() override;

    QString address() const;
    void setAddress(const QString& address);

    bool active() const;
    void setActive(bool active);

    quint32 nodeId() const;
    quint64 objectSerial() const;
    bool available() const;

Q_SIGNALS:
    void addressChanged();
    void activeChanged();
    void streamChanged();

private:
    void acquire();
    void release();

    QString m_address;
    QString m_held;
    bool m_active = true;
};

} // namespace caelestia::services
