#pragma once

#include <qstring.h>
#include <qstringlist.h>

#include "../Settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

// One focus window: a name, the days it applies to and the times it covers. A window
// whose end is before its start runs overnight into the next day.
class FocusSchedule : public settings::ObjectNode {
    CONFIG_NODE(FocusSchedule, settings::ObjectNode)

    CONFIG_PROPERTY(QString, name, {})
    CONFIG_PROPERTY(QStringList, days, {})
    CONFIG_PROPERTY(QString, start, QStringLiteral("09:00"))
    CONFIG_PROPERTY(QString, end, QStringLiteral("17:00"))
};
CONFIG_LIST_TYPE(FocusSchedule, FocusScheduleList)

class NotifsConfig : public settings::ObjectNode {
    CONFIG_NODE(NotifsConfig, settings::ObjectNode)

    CONFIG_GLOBAL_PROPERTY(bool, expire, true)
    CONFIG_GLOBAL_PROPERTY(QString, fullscreen, QStringLiteral("off"))
    CONFIG_GLOBAL_PROPERTY(QString, monitor, QStringLiteral("all"))
    CONFIG_GLOBAL_PROPERTY(int, defaultExpireTimeout, 5000)
    CONFIG_GLOBAL_PROPERTY(int, fullscreenExpireTimeout, 2000)
    CONFIG_PROPERTY(qreal, clearThreshold, 0.3)
    CONFIG_PROPERTY(int, expandThreshold, 20)
    CONFIG_GLOBAL_PROPERTY(bool, actionOnClick, false)
    CONFIG_PROPERTY(int, groupPreviewNum, 3)
    CONFIG_PROPERTY(bool, openExpanded, false)
    CONFIG_GLOBAL_PROPERTY(QString, position, QStringLiteral("auto"))
    CONFIG_GLOBAL_PROPERTY(int, maxPopups, 8)
    CONFIG_GLOBAL_PROPERTY(int, maxNotifs, 50)

    // Focus sessions: Do Not Disturb that switches itself on for these windows, and
    // the apps whose notifications are still allowed through while it is on. `followCalendar`
    // adds the running calendar events as a second source of sessions.
    CONFIG_GLOBAL_PROPERTY(bool, focusEnabled, false)
    CONFIG_GLOBAL_PROPERTY(bool, focusCalendar, false)
    CONFIG_GLOBAL_LIST(FocusScheduleList, focusSchedules, {})
    CONFIG_GLOBAL_PROPERTY(QStringList, focusAllowlist, QStringList())

    // Apps whose notifications are dropped: no banner, no sound, nothing in the list and
    // nothing added to the unread count. This is the "turn off notifications for this app"
    // switch, which is a different answer from `audio.sounds.disabledNotifApps` — that one
    // still shows the notification, quietly.
    CONFIG_GLOBAL_PROPERTY(QStringList, mutedApps, QStringList())
};

} // namespace caelestia::config
