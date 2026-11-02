import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

Scope {
    Component.onCompleted: {
        ConfigMigrations;
        Notifs;
    }

    Timer {
        id: deferredServices

        interval: 250
        repeat: false
        running: true

        onTriggered: {
            IdleInhibitor;
            Timers;
            GameMode;
            Players;
            Brightness;
            Weather.reload();
            WorkspaceTrackerGuard;
            PlasmaWidgets;
            TrayRegistry;

            if (GlobalConfig.utilities.vpn.enabled)
                VPN;
        }
    }
}
