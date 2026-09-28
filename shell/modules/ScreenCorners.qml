import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Services

Scope {
    id: root

    readonly property bool overviewOn: Config.overview.enabled
    readonly property bool wantTopLeft: overviewOn && Config.overview.hoverTopLeft
    readonly property bool wantTopRight: overviewOn && Config.overview.hoverTopRight
    readonly property bool wantBottomLeft: overviewOn && Config.overview.hoverBottomLeft
    readonly property bool wantBottomRight: overviewOn && Config.overview.hoverBottomRight

    function sync(corner: int, wanted: bool): void {
        if (wanted)
            ScreenEdges.claim(corner);
        else
            ScreenEdges.release(corner);
    }

    onWantTopLeftChanged: sync(ScreenEdges.TopLeft, wantTopLeft)
    onWantTopRightChanged: sync(ScreenEdges.TopRight, wantTopRight)
    onWantBottomLeftChanged: sync(ScreenEdges.BottomLeft, wantBottomLeft)
    onWantBottomRightChanged: sync(ScreenEdges.BottomRight, wantBottomRight)

    Component.onCompleted: {
        sync(ScreenEdges.TopLeft, wantTopLeft);
        sync(ScreenEdges.TopRight, wantTopRight);
        sync(ScreenEdges.BottomLeft, wantBottomLeft);
        sync(ScreenEdges.BottomRight, wantBottomRight);
    }
}
