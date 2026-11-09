#pragma once

#include "../Settings/objectnode.hpp"
#include "common.hpp"

namespace caelestia::config {

class NexusConfig : public settings::ObjectNode {
    CONFIG_NODE(NexusConfig, settings::ObjectNode)

    CONFIG_PROPERTY(int, wallpapersPerRow, 4)

    // Show a section's subcategories in their own pane, between the section
    // list and the page. Off by default, so a section opens on its own list;
    // turning it on restores the three-pane layout.
    CONFIG_GLOBAL_PROPERTY(bool, sidePane, false)
    CONFIG_GLOBAL_PROPERTY(int, networkRescanInterval, 15000)
    CONFIG_PROPERTY(int, maxNetworksShown, 5)
};

} // namespace caelestia::config
