pragma Singleton
import QtQuick

QtObject {
    id: theme

    property bool configAvailable: false
    property string backgroundSource: "assets/background" // allow for different file extensions
    property bool videoActive: false
    property var videoItem: null
    property string fontFamily: "Google Sans Flex"
    property real avatarFrameSize: {
        if (theme.avatarShape === "clamshell")
            return 300;

        if (theme.avatarShape === "circle")
            return 240;

        return 250;
    }
    property real avatarInset: 19
    property string _randomAvatarShape: {
        var shapes = ["circle", "clamshell", "cookie"];
        return shapes[Math.floor(Math.random() * shapes.length)];
    }
    property string avatarShape: {
        var val = getConfig("avatarShape");
        if (val === undefined)
            return "random";

        val = val.toString().toLowerCase().trim().replace(/^"|"$/g, "");
        if (val === "random")
            return theme._randomAvatarShape;

        return val;
    }
    property real elementRadius: boundedNumber(getConfig("elementRadius"), 20, 0, 64)
    property real cardRadius: boundedNumber(getConfig("cardRadius"), 30, 0, 80)
    // Colors
    property color mPrimary: getConfig("mPrimary") || "#4cdadb"
    property color mOnPrimary: getConfig("mOnPrimary") || "#002022"
    property color mSecondary: getConfig("mSecondary") || "#95f4f5"
    property color mOnSecondary: getConfig("mOnSecondary") || "#003738"
    property color mTertiary: getConfig("mTertiary") || "#86d0ff"
    property color mOnTertiary: getConfig("mOnTertiary") || "#00344d"
    property color mError: getConfig("mError") || "#ffb4ab"
    property color mOnError: getConfig("mOnError") || "#690005"
    property color mSurface: getConfig("mSurface") || "#131313"
    property color mOnSurface: getConfig("mOnSurface") || "#e2e2e2"
    property color mSurfaceVariant: getConfig("mSurfaceVariant") || "#353535"
    property color mOnSurfaceVariant: getConfig("mOnSurfaceVariant") || "#919191"
    property color mSurfaceContainer: getConfig("mSurfaceContainer") || "#1a211d"
    property color mOutline: getConfig("mOutline") || "#7d7d7d"
    property color mShadow: getConfig("mShadow") || "#000000"
    property color mHover: getConfig("mHover") || mPrimary
    property color mOnHover: getConfig("mOnHover") || mOnPrimary
    // Welcome message
    property bool enableWelcomeMessage: toBool(getConfig("enableWelcomeMessage"), true)
    property string welcomeMessage: {
        var val = getConfig("welcomeMessage");
        if (val === undefined)
            return "Welcome $USER";

        return val.toString().replace(/^"|"$/g, "");
    }
    // Effects
    property bool dropShadows: toBool(getConfig("dropShadows"), true)
    property bool cardBorder: toBool(getConfig("cardBorder"), false)
    property bool blurEnabled: toBool(getConfig("blurEnabled"), true)
    property real blurStrength: boundedNumber(getConfig("blurStrength"), 1, 0, 1)
    property real outerCardOpacity: boundedNumber(getConfig("outerCardOpacity"), 0.75, 0.5, 1)
    property real overlayOpacity: boundedNumber(getConfig("overlayOpacity"), 0.4, 0, 1)
    property bool cardBlurEnabled: toBool(getConfig("cardBlurEnabled"), true)
    property real cardBlurStrength: boundedNumber(getConfig("cardBlurStrength"), 0.75, 0, 1)
    property real innerCardOpacity: boundedNumber(getConfig("innerCardOpacity"), 0.45, 0.15, 1)
    property real elementOpacity: boundedNumber(getConfig("elementOpacity"), 0.5, 0.1, 1)
    property int shadowRadius: 16
    property int shadowSamples: 32
    // Animations
    property int animDurationFast: 200
    property int animDurationNormal: 300
    property int animDurationSlow: 400
    // Debug
    property bool debugMode: toBool(getConfig("debugMode"), false)

    function getConfig(key) {
        if (!configAvailable)
            return undefined;

        const value = config[key];
        return value !== undefined ? value : undefined;
    }

    function toNumber(value, fallbackValue) {
        var num = Number(value);
        return isFinite(num) ? num : fallbackValue;
    }

    function boundedNumber(value, fallbackValue, minValue, maxValue) {
        var num = toNumber(value, fallbackValue);
        if (num < minValue)
            return minValue;

        if (num > maxValue)
            return maxValue;

        return num;
    }

    function toBool(value, fallbackValue) {
        if (value === undefined || value === null || value === "")
            return fallbackValue;

        var normalized = String(value).toLowerCase();
        return normalized === "true" || normalized === "1" || normalized === "yes" || normalized === "on";
    }

    function withAlpha(baseColor, alphaValue) {
        return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, alphaValue);
    }

    Component.onCompleted: {
        configAvailable = (typeof config !== 'undefined');
    }
}
