#pragma once

#include <QMap>
#include <QObject>
#include <QQmlEngine>
#include <QVariantMap>

namespace caelestia::services {

class KrohnkiteConfig : public QObject {
    Q_OBJECT
    Q_PROPERTY(int screenGapBetween READ screenGapBetween WRITE setScreenGapBetween NOTIFY gapsChanged)
    Q_PROPERTY(int screenGapBottom READ screenGapBottom WRITE setScreenGapBottom NOTIFY gapsChanged)
    Q_PROPERTY(int screenGapLeft READ screenGapLeft WRITE setScreenGapLeft NOTIFY gapsChanged)
    Q_PROPERTY(int screenGapRight READ screenGapRight WRITE setScreenGapRight NOTIFY gapsChanged)
    Q_PROPERTY(int screenGapTop READ screenGapTop WRITE setScreenGapTop NOTIFY gapsChanged)

    Q_PROPERTY(QString ignoreClass READ ignoreClass WRITE setIgnoreClass NOTIFY ignoreClassChanged)

    Q_PROPERTY(bool binaryTreeLayoutEnabled READ binaryTreeLayoutEnabled WRITE setBinaryTreeLayoutEnabled NOTIFY
            layoutsChanged)
    Q_PROPERTY(bool cascadeLayoutEnabled READ cascadeLayoutEnabled WRITE setCascadeLayoutEnabled NOTIFY layoutsChanged)
    Q_PROPERTY(bool columnsLayoutEnabled READ columnsLayoutEnabled WRITE setColumnsLayoutEnabled NOTIFY layoutsChanged)
    Q_PROPERTY(
        bool floatingLayoutEnabled READ floatingLayoutEnabled WRITE setFloatingLayoutEnabled NOTIFY layoutsChanged)
    Q_PROPERTY(bool monocleLayoutEnabled READ monocleLayoutEnabled WRITE setMonocleLayoutEnabled NOTIFY layoutsChanged)
    Q_PROPERTY(bool quarterLayoutEnabled READ quarterLayoutEnabled WRITE setQuarterLayoutEnabled NOTIFY layoutsChanged)
    Q_PROPERTY(bool spiralLayoutEnabled READ spiralLayoutEnabled WRITE setSpiralLayoutEnabled NOTIFY layoutsChanged)
    Q_PROPERTY(bool spreadLayoutEnabled READ spreadLayoutEnabled WRITE setSpreadLayoutEnabled NOTIFY layoutsChanged)
    Q_PROPERTY(bool stackedLayoutEnabled READ stackedLayoutEnabled WRITE setStackedLayoutEnabled NOTIFY layoutsChanged)
    Q_PROPERTY(bool stairLayoutEnabled READ stairLayoutEnabled WRITE setStairLayoutEnabled NOTIFY layoutsChanged)
    Q_PROPERTY(bool threeColumnLayoutEnabled READ threeColumnLayoutEnabled WRITE setThreeColumnLayoutEnabled NOTIFY
            layoutsChanged)
    Q_PROPERTY(bool tileLayoutEnabled READ tileLayoutEnabled WRITE setTileLayoutEnabled NOTIFY layoutsChanged)

    QML_ELEMENT
    QML_SINGLETON

public:
    explicit KrohnkiteConfig(QObject* parent = nullptr);
    ~KrohnkiteConfig() override;

    int screenGapBetween() const { return m_screenGapBetween; }

    void setScreenGapBetween(int gap);

    int screenGapBottom() const { return m_screenGapBottom; }

    void setScreenGapBottom(int gap);

    int screenGapLeft() const { return m_screenGapLeft; }

    void setScreenGapLeft(int gap);

    int screenGapRight() const { return m_screenGapRight; }

    void setScreenGapRight(int gap);

    int screenGapTop() const { return m_screenGapTop; }

    void setScreenGapTop(int gap);

    QString ignoreClass() const { return m_ignoreClass; }

    void setIgnoreClass(const QString& classes);

    bool binaryTreeLayoutEnabled() const { return m_binaryTreeLayoutEnabled; }

    void setBinaryTreeLayoutEnabled(bool enabled);

    bool cascadeLayoutEnabled() const { return m_cascadeLayoutEnabled; }

    void setCascadeLayoutEnabled(bool enabled);

    bool columnsLayoutEnabled() const { return m_columnsLayoutEnabled; }

    void setColumnsLayoutEnabled(bool enabled);

    bool floatingLayoutEnabled() const { return m_floatingLayoutEnabled; }

    void setFloatingLayoutEnabled(bool enabled);

    bool monocleLayoutEnabled() const { return m_monocleLayoutEnabled; }

    void setMonocleLayoutEnabled(bool enabled);

    bool quarterLayoutEnabled() const { return m_quarterLayoutEnabled; }

    void setQuarterLayoutEnabled(bool enabled);

    bool spiralLayoutEnabled() const { return m_spiralLayoutEnabled; }

    void setSpiralLayoutEnabled(bool enabled);

    bool spreadLayoutEnabled() const { return m_spreadLayoutEnabled; }

    void setSpreadLayoutEnabled(bool enabled);

    bool stackedLayoutEnabled() const { return m_stackedLayoutEnabled; }

    void setStackedLayoutEnabled(bool enabled);

    bool stairLayoutEnabled() const { return m_stairLayoutEnabled; }

    void setStairLayoutEnabled(bool enabled);

    bool threeColumnLayoutEnabled() const { return m_threeColumnLayoutEnabled; }

    void setThreeColumnLayoutEnabled(bool enabled);

    bool tileLayoutEnabled() const { return m_tileLayoutEnabled; }

    void setTileLayoutEnabled(bool enabled);

    Q_INVOKABLE void apply();
    Q_INVOKABLE void refresh();

signals:
    void gapsChanged();
    void ignoreClassChanged();
    void layoutsChanged();

private:
    void setKWinConfig(const QString& key, const QString& value);
    void setKWinConfig(const QMap<QString, QString>& values);
    void setLayoutEnabled(const QString& key, bool enabled);

    int m_screenGapBetween = 0;
    int m_screenGapBottom = 0;
    int m_screenGapLeft = 0;
    int m_screenGapRight = 0;
    int m_screenGapTop = 0;

    QString m_ignoreClass;

    bool m_binaryTreeLayoutEnabled = false;
    bool m_cascadeLayoutEnabled = false;
    bool m_columnsLayoutEnabled = false;
    bool m_floatingLayoutEnabled = false;
    bool m_monocleLayoutEnabled = false;
    bool m_quarterLayoutEnabled = false;
    bool m_spiralLayoutEnabled = false;
    bool m_spreadLayoutEnabled = false;
    bool m_stackedLayoutEnabled = false;
    bool m_stairLayoutEnabled = false;
    bool m_threeColumnLayoutEnabled = false;
    bool m_tileLayoutEnabled = false;
};

} // namespace caelestia::services
