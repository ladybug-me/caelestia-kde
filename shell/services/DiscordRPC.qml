pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.services
import qs.utils

Item {
    id: root

    property bool active: GlobalConfig.services.arpcEnabled
    property string clientId: GlobalConfig.services.arpcClientId || "1126685412586733678"

    property string steamGridDbKey: ""

    onSteamGridDbKeyChanged: {
        if (root.currentSteamAppId !== "") {
            root.currentSteamData = null;
            root.updatePresence();
        }
    }

    property Process readTokenProc: Process {
        command: ["secret-tool", "lookup", "service", "caelestia-shell", "account", "steamgriddb"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.steamGridDbKey = text.trim();
            }
        }
    }
    onActiveChanged: {
        if (active) {
            readTokenProc.running = true;
            DiscordIpc.connectIpc(root.clientId);
        } else {
            DiscordIpc.disconnectIpc();
        }
    }

    Component.onCompleted: {
        if (root.active) {
            readTokenProc.running = true;
            DiscordIpc.connectIpc(root.clientId);
        }
    }

    property real shellStartTime: Date.now() / 1000

    /// Rich presence is meant to say what you are doing now, not what you were
    /// doing before you walked away. Uses the Wayland idle protocol rather than
    /// a focus-change heuristic, so it also covers sitting and reading.
    readonly property int idleTimeout: GlobalConfig.services.arpcIdleTimeout

    property bool userIdle: false

    onUserIdleChanged: {
        if (!root.active || !DiscordIpc.connected)
            return;

        if (root.userIdle)
            DiscordIpc.clearActivity();
        else
            root.updatePresence();
    }

    IdleMonitor {
        // A timeout of 0 means the feature is off, and IdleMonitor would treat
        // it as "idle immediately".
        enabled: root.active && root.idleTimeout > 0
        timeout: root.idleTimeout
        onIsIdleChanged: root.userIdle = isIdle

        // Turning the feature off while idle must not strand the presence in
        // the cleared state.
        onEnabledChanged: if (!enabled)
            root.userIdle = false
    }

    Connections {
        target: DiscordIpc

        function onConnectedChanged() {
            if (DiscordIpc.connected) {
                Logger.log("Discord ARPC connected");
                root.updatePresence();
            }
        }

        function onErrorOccurred(errorString) {
            Logger.log("Discord ARPC error: " + errorString);
        }
    }

    Connections {
        target: Kwin
        enabled: root.active
        ignoreUnknownSignals: true

        function onWindowListChanged() { root.updatePresence(); }

        function onActiveWindowChanged() { root.updatePresence(); }
    }

    Connections {
        target: GlobalConfig.services
        enabled: root.active

        function onArpcSteamAutoDetectChanged() { root.updatePresence(); }

        function onArpcTargetWindowsChanged() { root.updatePresence(); }

        function onArpcTargetWindowLabelsChanged() { root.updatePresence(); }

        function onArpcCaelestiaInfoChanged() { root.updatePresence(); }

        function onArpcSteamBlacklistChanged() { root.updatePresence(); }

        function onArpcAppNameChanged() { root.updatePresence(); }

        function onArpcDetailsChanged() { root.updatePresence(); }

        function onArpcStateChanged() { root.updatePresence(); }

        function onArpcLargeImageChanged() { root.updatePresence(); }

        function onArpcSmallImageChanged() { root.updatePresence(); }

        function onArpcManualOverrideChanged() { root.updatePresence(); }
    }

    Connections {
        target: Colours
        enabled: root.active

        function onSchemeChanged() { root.updatePresence(); }

        function onLightChanged() { root.updatePresence(); }

        function onVariantChanged() { root.updatePresence(); }
    }

    property string currentSteamAppId: ""

    property var currentSteamData: null

    property bool fetchingSteam: false

    function updatePresence() {
        if (!active || !DiscordIpc.connected) return;
        if (fetchingSteam) return; // Prevent loop during async fetch
        // Any of the triggers below can fire while away; none of them should
        // put the presence back until the user actually returns.
        if (userIdle) return;

        // Priority 0: Manual Override
        if (GlobalConfig.services.arpcManualOverride && (GlobalConfig.services.arpcAppName || GlobalConfig.services.arpcDetails || GlobalConfig.services.arpcState)) {
            root.currentSteamAppId = "";
            root.sendActivity({
                details: GlobalConfig.services.arpcDetails,
                state: GlobalConfig.services.arpcState,
                large_image: GlobalConfig.services.arpcLargeImage,
                small_image: GlobalConfig.services.arpcSmallImage,
                startTimestamp: root.shellStartTime
            });
            return;
        }

        let topSteamClass = "";
        let topSteamTitle = "";
        let topTargetClass = "";
        let topTargetTitle = "";
        let topTargetMatchIdx = -1;

        // Priority 2 prefers the focused window: a background app that happens
        // to match the regex shouldn't describe you better than what you're
        // actually looking at. Seeding the values here means the scan below
        // only fills them in when nothing focused matched.
        const activeClass = Kwin.activeWindow.class ?? "";
        if (activeClass !== "") {
            const activeIdx = Strings.findMatchingIndex(GlobalConfig.services.arpcTargetWindows, activeClass);
            if (activeIdx >= 0) {
                topTargetClass = activeClass;
                topTargetTitle = Kwin.activeWindow.title ?? "";
                topTargetMatchIdx = activeIdx;
            }
        }

        for (const toplevel of Kwin.windowList) {
            let winClass = toplevel.class ?? "";
            let winTitle = toplevel.title ?? "";

            if (GlobalConfig.services.arpcSteamAutoDetect && winClass.startsWith("steam_app_")) {
                let appId = winClass.replace("steam_app_", "");
                let isBlacklisted = Strings.testRegexList(GlobalConfig.services.arpcSteamBlacklist, appId) || Strings.testRegexList(GlobalConfig.services.arpcSteamBlacklist, "steam_app_" + appId);
                if (!isBlacklisted) {
                    topSteamClass = winClass;
                    topSteamTitle = winTitle;
                    break;
                }
            }

            if (topTargetClass === "") {
                let matchIdx = Strings.findMatchingIndex(GlobalConfig.services.arpcTargetWindows, winClass);
                if (matchIdx >= 0) {
                    topTargetClass = winClass;
                    topTargetTitle = winTitle;
                    topTargetMatchIdx = matchIdx;
                }
            }
        }

        // Priority 1: Steam Games
        if (topSteamClass !== "") {
            let appId = topSteamClass.replace("steam_app_", "");
            if (appId !== root.currentSteamAppId || !root.currentSteamData) {
                root.currentSteamAppId = appId;
                root.fetchSteamData(appId);
                return; 
            }
            if (root.currentSteamData) {
                root.sendActivity({
                    details: root.currentSteamData.name,
                    state: root.currentSteamData.state || "Playing via Steam",
                    large_image: root.currentSteamData.icon || "steam",
                    small_image: "",
                    startTimestamp: root.shellStartTime
                });
                return;
            }
        } else {
            root.currentSteamAppId = "";
        }

        // Priority 2: Custom Apps (Target Windows)
        if (topTargetClass !== "") {
            let displayDetails = topTargetTitle;
            let labels = GlobalConfig.services.arpcTargetWindowLabels;
            if (labels && topTargetMatchIdx >= 0 && topTargetMatchIdx < labels.length) {
                let label = labels[topTargetMatchIdx];
                if (label && label !== "") {
                    displayDetails = label
                        .replace(/\{class\}/g, topTargetClass)
                        .replace(/\{title\}/g, topTargetTitle);
                }
            }
            root.sendActivity({
                details: displayDetails,
                state: "Using " + topTargetClass,
                large_image: topTargetClass,
                small_image: "",
                startTimestamp: root.shellStartTime
            });
            return;
        }

        // Priority 3: Caelestia Info
        if (GlobalConfig.services.arpcCaelestiaInfo) {
            let os = SysInfo.osPrettyName || SysInfo.osName || "Linux";
            let kernel = SysInfo.kernel ? SysInfo.kernel : "";
            let qsVersion = CUtils.version ? " (v" + CUtils.version + ")" : "";
            
            let detailsStr = os;
            if (kernel) detailsStr += " • " + kernel;

            let schemeName = Colours.scheme || (Colours.light ? "Light Mode" : "Dark Mode");
            let stateStr = "Scheme: " + schemeName;
            if (Colours.variant) stateStr += " | Variant: " + Colours.variant;

            root.sendActivity({
                name: "Caelestia Shell" + qsVersion,
                details: detailsStr,
                state: stateStr,
                large_image: "https://avatars.githubusercontent.com/u/195541893",
                small_image: "",
                startTimestamp: root.shellStartTime,
                buttons: [
                    { label: "Website", url: "https://caelestiashell.com" },
                    { label: "GitHub", url: "https://github.com/caelestia-dots/" }
                ]
            });
            return;
        }

        root.clearActivity();
    }

    function fetchSteamData(appId) {
        root.fetchingSteam = true;
        Requests.get("https://store.steampowered.com/api/appdetails?appids=" + appId, function(steamRes) {
            let steamData = JSON.parse(steamRes);
            let gameName = "Unknown Steam Game (" + appId + ")";
            if (steamData && steamData[appId] && steamData[appId].success) {
                gameName = steamData[appId].data.name;
            }
                
            Requests.get("https://store.steampowered.com/appreviews/" + appId + "?json=1", function(revRes) {
                let revData = null;
                try { revData = JSON.parse(revRes); } catch(e) {}
                let reviewText = "Playing via Steam";
                if (revData && revData.query_summary && revData.query_summary.total_reviews > 0) {
                    let score = Math.round((revData.query_summary.total_positive / revData.query_summary.total_reviews) * 100);
                    let desc = revData.query_summary.review_score_desc || "Mixed";
                    reviewText = desc + " - " + score + "%";
                }

                if (root.steamGridDbKey !== "" && steamData && steamData[appId] && steamData[appId].success) {
                    let headers = { "Authorization": "Bearer " + root.steamGridDbKey };
                    Requests.get("https://www.steamgriddb.com/api/v2/games/steam/" + appId, function(dbRes) {
                        let dbData = null;
                        try { dbData = JSON.parse(dbRes); } catch(e) {}
                        if (dbData && dbData.success && dbData.data && dbData.data.id) {
                            let sgdbId = dbData.data.id;
                            Requests.get("https://www.steamgriddb.com/api/v2/icons/game/" + sgdbId, function(iconRes) {
                                let iconData = null;
                                try { iconData = JSON.parse(iconRes); } catch(e) {}
                                let iconUrl = "";
                                if (iconData && iconData.success && iconData.data && iconData.data.length > 0) {
                                    for (let i = 0; i < iconData.data.length; i++) {
                                        if (iconData.data[i].mime !== "image/x-icon" && iconData.data[i].mime !== "image/vnd.microsoft.icon") {
                                            iconUrl = iconData.data[i].url;
                                            break;
                                        }
                                    }
                                    if (iconUrl === "") iconUrl = iconData.data[0].url;
                                }
                                root.currentSteamData = { name: gameName, icon: iconUrl, state: reviewText };
                                root.fetchingSteam = false;
                                root.updatePresence();
                            }, function() {
                                root.currentSteamData = { name: gameName, icon: "", state: reviewText };
                                root.fetchingSteam = false;
                                root.updatePresence();
                            }, headers);
                        } else {
                            root.currentSteamData = { name: gameName, icon: "", state: reviewText };
                            root.fetchingSteam = false;
                            root.updatePresence();
                        }
                    }, function() {
                        root.currentSteamData = { name: gameName, icon: "", state: reviewText };
                        root.fetchingSteam = false;
                        root.updatePresence();
                    }, headers);
                } else {
                    root.currentSteamData = { name: gameName, icon: "", state: reviewText };
                    root.fetchingSteam = false;
                    root.updatePresence();
                }
            }, function() {
                root.currentSteamData = { name: gameName, icon: "", state: "Playing via Steam" };
                root.fetchingSteam = false;
                root.updatePresence();
            });
        }, function() {
            root.fetchingSteam = false;
        });
    }

    function sendActivity(data) {
        if (!DiscordIpc.connected) return;

        const activity = {};
        if (data.name && data.name !== "") activity.name = data.name;
        if (data.state && data.state !== "") activity.state = data.state;
        if (data.details && data.details !== "") activity.details = data.details;
        
        const assets = {};
        if (data.large_image && data.large_image !== "") assets.large_image = data.large_image;
        if (data.large_text && data.large_text !== "") assets.large_text = data.large_text;
        if (data.small_image && data.small_image !== "") assets.small_image = data.small_image;
        if (Object.keys(assets).length > 0) activity.assets = assets;

        if (data.buttons && data.buttons.length > 0) {
            activity.buttons = data.buttons;
        }

        if (data.startTimestamp) {
            activity.timestamps = {
                start: Math.floor(data.startTimestamp)
            };
        }
        DiscordIpc.sendActivity(activity);
    }

    function clearActivity() {
        if (!DiscordIpc.connected) return;
        DiscordIpc.clearActivity();
    }

}
