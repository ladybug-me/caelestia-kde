#include "krohnkiteconfig.hpp"

#include <KConfigGroup>
#include <KSharedConfig>
#include <QDebug>
#include <QHash>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusMessage>

namespace caelestia::services {

/// kwinrc group the Krohnkite KWin script keeps its settings in.
static const QString KROHNKITE_GROUP = QStringLiteral("Script-krohnkite");

/// Class list Krohnkite assumes when kwinrc has no ignoreClass key yet.
///
/// Kept identical to IGNORE_CLASSES in shell/services/startuptasks/02-krohnkite-setup.sh:
/// this is only the fallback for a system the startup task has not touched, but Nexus
/// shows it and writes it back on the first edit, so a short list here silently drops the
/// dialog classes for the rest of the session. test_repo_integrity.py guards the parity.
static const QString DEFAULT_IGNORE_CLASS =
    QStringLiteral("krunner,yakuake,spectacle,kded5,xwaylandvideobridge,plasmashell,ksplashqml,org.kde.plasmashell,"
                   "org.kde.polkit-kde-authentication-agent-1,quickshell,org.quickshell,org.pulseaudio.pavucontrol,"
                   "com.saivert.pwvucontrol,yad,yad-icon-browser,system-config-printer,nwg-look,org.gnome.Settings,"
                   "org.gnome.FileRoller,file-roller,blueman-manager,guifetch,wev,zenity,feh,imv,swappy");

KrohnkiteConfig::KrohnkiteConfig(QObject* parent)
    : QObject(parent) {
    refresh();
}

KrohnkiteConfig::~KrohnkiteConfig() = default;

void KrohnkiteConfig::setKWinConfig(const QString& key, const QString& value) {
    QMap<QString, QString> values;
    values.insert(key, value);
    setKWinConfig(values);
}

void KrohnkiteConfig::setKWinConfig(const QMap<QString, QString>& values) {
    // kwinrc is read and written in-process. Forking kreadconfig6/kwriteconfig6
    // blocks the QML thread for the lifetime of every child, and toggling one
    // layout checkbox used to write all twelve order keys one process at a time.
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    KConfigGroup group = config->group(KROHNKITE_GROUP);
    for (auto it = values.cbegin(); it != values.cend(); ++it) {
        group.writeEntry(it.key(), it.value());
    }
    config->sync();
}

// Table of all layout keys paired with their default order position.
// -1 = disabled by default; 1..N = enabled at that position (no duplicates).
struct LayoutDefault {
    const char* key;
    int defaultOrder;
};

static const std::initializer_list<LayoutDefault>& allLayoutDefaults() {
    // Default order when kwinrc has never been written.
    // Only enabled-by-default entries get a positive order; disabled get -1.
    static const std::initializer_list<LayoutDefault> table = {
        { "binaryTreeLayoutOrder", 1 },
        { "floatingLayoutOrder", 2 },
        { "tileLayoutOrder", 3 },
        { "monocleLayoutOrder", 4 },
        { "quarterLayoutOrder", 5 },
        { "threeColumnLayoutOrder", 6 },
        { "spreadLayoutOrder", 7 },
        { "stackedLayoutOrder", 8 },
        { "stairLayoutOrder", 9 },
        // Disabled by default:
        { "spiralLayoutOrder", -1 },
        { "columnsLayoutOrder", -1 },
        { "cascadeLayoutOrder", -1 },
    };
    return table;
}

/// Everything the tiling page shows, read out of kwinrc in a single pass.
struct KrohnkiteSettings {
    int screenGapBetween = 10;
    int screenGapBottom = 4;
    int screenGapLeft = 4;
    int screenGapRight = 4;
    int screenGapTop = 4;
    QString ignoreClass = DEFAULT_IGNORE_CLASS;
    QMap<QString, int> layoutOrders;
};

static KrohnkiteSettings readSettings() {
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals);
    // Pick up edits made outside Nexus - KWin writes kwinrc too.
    config->reparseConfiguration();
    KConfigGroup group = config->group(KROHNKITE_GROUP);

    KrohnkiteSettings settings;
    settings.screenGapBetween = group.readEntry(QStringLiteral("screenGapBetween"), settings.screenGapBetween);
    settings.screenGapBottom = group.readEntry(QStringLiteral("screenGapBottom"), settings.screenGapBottom);
    settings.screenGapLeft = group.readEntry(QStringLiteral("screenGapLeft"), settings.screenGapLeft);
    settings.screenGapRight = group.readEntry(QStringLiteral("screenGapRight"), settings.screenGapRight);
    settings.screenGapTop = group.readEntry(QStringLiteral("screenGapTop"), settings.screenGapTop);
    settings.ignoreClass = group.readEntry(QStringLiteral("ignoreClass"), settings.ignoreClass);

    for (const auto& entry : allLayoutDefaults()) {
        const QString key = QString::fromLatin1(entry.key);
        // -1 means disabled, a positive value is the layout's position.
        const int order = group.readEntry(key, entry.defaultOrder);
        settings.layoutOrders.insert(key, order >= 1 ? order : -1);
    }
    return settings;
}

void KrohnkiteConfig::setLayoutEnabled(const QString& key, bool enabled) {
    // Read current order values for all layouts, seeding from defaults where missing.
    QMap<QString, int> orders = readSettings().layoutOrders;

    if (enabled) {
        if (orders[key] >= 1)
            return; // already enabled, nothing to do
        // Shift every currently-enabled layout's order up by 1 to make room at position 1.
        for (auto it = orders.begin(); it != orders.end(); ++it) {
            if (it.value() >= 1) {
                it.value() += 1;
            }
        }
        orders[key] = 1;
    } else {
        int removedOrder = orders[key];
        if (removedOrder < 1)
            return; // already disabled, nothing to do
        orders[key] = -1;
        // Compact: shift down any layout that was positioned after the removed one.
        for (auto it = orders.begin(); it != orders.end(); ++it) {
            if (it.value() > removedOrder) {
                it.value() -= 1;
            }
        }
    }

    // One kwinrc write for all twelve orders, not one child process per key.
    QMap<QString, QString> values;
    for (auto it = orders.cbegin(); it != orders.cend(); ++it) {
        values.insert(it.key(), QString::number(it.value()));
    }
    setKWinConfig(values);
}

void KrohnkiteConfig::refresh() {
    const KrohnkiteSettings settings = readSettings();

    m_screenGapBetween = settings.screenGapBetween;
    m_screenGapBottom = settings.screenGapBottom;
    m_screenGapLeft = settings.screenGapLeft;
    m_screenGapRight = settings.screenGapRight;
    m_screenGapTop = settings.screenGapTop;
    emit gapsChanged();

    m_ignoreClass = settings.ignoreClass;
    emit ignoreClassChanged();

    const QHash<QString, bool*> layoutFlags{
        { QStringLiteral("binaryTreeLayoutOrder"), &m_binaryTreeLayoutEnabled },
        { QStringLiteral("cascadeLayoutOrder"), &m_cascadeLayoutEnabled },
        { QStringLiteral("columnsLayoutOrder"), &m_columnsLayoutEnabled },
        { QStringLiteral("floatingLayoutOrder"), &m_floatingLayoutEnabled },
        { QStringLiteral("monocleLayoutOrder"), &m_monocleLayoutEnabled },
        { QStringLiteral("quarterLayoutOrder"), &m_quarterLayoutEnabled },
        { QStringLiteral("spiralLayoutOrder"), &m_spiralLayoutEnabled },
        { QStringLiteral("spreadLayoutOrder"), &m_spreadLayoutEnabled },
        { QStringLiteral("stackedLayoutOrder"), &m_stackedLayoutEnabled },
        { QStringLiteral("stairLayoutOrder"), &m_stairLayoutEnabled },
        { QStringLiteral("threeColumnLayoutOrder"), &m_threeColumnLayoutEnabled },
        { QStringLiteral("tileLayoutOrder"), &m_tileLayoutEnabled },
    };
    for (auto it = layoutFlags.cbegin(); it != layoutFlags.cend(); ++it) {
        *it.value() = settings.layoutOrders.value(it.key()) >= 1;
    }
    emit layoutsChanged();
}

void KrohnkiteConfig::apply() {
    // Notify KWin to reconfigure
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"),
        QStringLiteral("org.kde.KWin"), QStringLiteral("reconfigure"));
    QDBusConnection::sessionBus().call(msg, QDBus::NoBlock);
}

void KrohnkiteConfig::setScreenGapBetween(int gap) {
    if (m_screenGapBetween != gap) {
        m_screenGapBetween = gap;
        setKWinConfig(QStringLiteral("screenGapBetween"), QString::number(gap));
        emit gapsChanged();
    }
}

void KrohnkiteConfig::setScreenGapBottom(int gap) {
    if (m_screenGapBottom != gap) {
        m_screenGapBottom = gap;
        setKWinConfig(QStringLiteral("screenGapBottom"), QString::number(gap));
        emit gapsChanged();
    }
}

void KrohnkiteConfig::setScreenGapLeft(int gap) {
    if (m_screenGapLeft != gap) {
        m_screenGapLeft = gap;
        setKWinConfig(QStringLiteral("screenGapLeft"), QString::number(gap));
        emit gapsChanged();
    }
}

void KrohnkiteConfig::setScreenGapRight(int gap) {
    if (m_screenGapRight != gap) {
        m_screenGapRight = gap;
        setKWinConfig(QStringLiteral("screenGapRight"), QString::number(gap));
        emit gapsChanged();
    }
}

void KrohnkiteConfig::setScreenGapTop(int gap) {
    if (m_screenGapTop != gap) {
        m_screenGapTop = gap;
        setKWinConfig(QStringLiteral("screenGapTop"), QString::number(gap));
        emit gapsChanged();
    }
}

void KrohnkiteConfig::setIgnoreClass(const QString& classes) {
    if (m_ignoreClass != classes) {
        m_ignoreClass = classes;
        setKWinConfig(QStringLiteral("ignoreClass"), classes);
        emit ignoreClassChanged();
    }
}

void KrohnkiteConfig::setBinaryTreeLayoutEnabled(bool enabled) {
    if (m_binaryTreeLayoutEnabled != enabled) {
        m_binaryTreeLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("binaryTreeLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setCascadeLayoutEnabled(bool enabled) {
    if (m_cascadeLayoutEnabled != enabled) {
        m_cascadeLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("cascadeLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setColumnsLayoutEnabled(bool enabled) {
    if (m_columnsLayoutEnabled != enabled) {
        m_columnsLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("columnsLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setFloatingLayoutEnabled(bool enabled) {
    if (m_floatingLayoutEnabled != enabled) {
        m_floatingLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("floatingLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setMonocleLayoutEnabled(bool enabled) {
    if (m_monocleLayoutEnabled != enabled) {
        m_monocleLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("monocleLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setQuarterLayoutEnabled(bool enabled) {
    if (m_quarterLayoutEnabled != enabled) {
        m_quarterLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("quarterLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setSpiralLayoutEnabled(bool enabled) {
    if (m_spiralLayoutEnabled != enabled) {
        m_spiralLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("spiralLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setSpreadLayoutEnabled(bool enabled) {
    if (m_spreadLayoutEnabled != enabled) {
        m_spreadLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("spreadLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setStackedLayoutEnabled(bool enabled) {
    if (m_stackedLayoutEnabled != enabled) {
        m_stackedLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("stackedLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setStairLayoutEnabled(bool enabled) {
    if (m_stairLayoutEnabled != enabled) {
        m_stairLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("stairLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setThreeColumnLayoutEnabled(bool enabled) {
    if (m_threeColumnLayoutEnabled != enabled) {
        m_threeColumnLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("threeColumnLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

void KrohnkiteConfig::setTileLayoutEnabled(bool enabled) {
    if (m_tileLayoutEnabled != enabled) {
        m_tileLayoutEnabled = enabled;
        setLayoutEnabled(QStringLiteral("tileLayoutOrder"), enabled);
        emit layoutsChanged();
    }
}

} // namespace caelestia::services
