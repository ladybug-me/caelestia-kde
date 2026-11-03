#pragma once

#include <qstring.h>

#include "../Settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

using Qt::StringLiterals::operator""_s;

class OsdConfig : public settings::ObjectNode {
    CONFIG_NODE(OsdConfig, settings::ObjectNode)

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(int, hideDelay, 2000)
    CONFIG_PROPERTY(int, hoverThickness, 10)
    CONFIG_PROPERTY(int, hoverWidth, 50)
    CONFIG_PROPERTY(bool, enableBrightness, true)
    CONFIG_PROPERTY(bool, enableMicrophone, false)
    CONFIG_PROPERTY(bool, enableVolume, true)
    CONFIG_PROPERTY(QString, style, u"default"_s)
    CONFIG_PROPERTY(QString, position, u"bottom"_s)
};

} // namespace caelestia::config
