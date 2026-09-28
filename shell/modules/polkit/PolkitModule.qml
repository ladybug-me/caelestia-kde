pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit 0.1
import Caelestia.Config
import qs.components

Scope {
    id: root

    PolkitAgent {
        id: agent
    }

    PolkitDialog {
        agent: agent
        screen: {
            const enabled = Quickshell.screens.filter(s => GlobalConfig.forScreen(s.name).enabled);
            return enabled.length > 0 ? enabled[0] : Quickshell.screens[0];
        }
    }
}
