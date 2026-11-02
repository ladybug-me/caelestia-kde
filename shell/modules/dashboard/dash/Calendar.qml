pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

/// The dashboard's month: the same view the bar popout shows, so only where the date
/// lives differs. The wheel and the middle click belong here; the grid is shared.
CustomMouseArea {
    id: root

    required property ScreenState screenState

    property date currentDate: screenState.dashboardDate
    readonly property int currMonth: currentDate.getMonth()
    readonly property int currYear: currentDate.getFullYear()

    function shiftMonth(delta: int): void {
        root.screenState.dashboardDate = new Date(root.currYear, root.currMonth + delta, 1);
    }

    function goToToday(): void {
        root.screenState.dashboardDate = new Date();
    }

    function onWheel(event: WheelEvent): void {
        if (event.angleDelta.y > 0)
            shiftMonth(-1);
        else if (event.angleDelta.y < 0)
            shiftMonth(1);
    }

    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: calendar.implicitHeight + Tokens.padding.large * 2

    acceptedButtons: Qt.MiddleButton
    onClicked: root.goToToday()

    CalendarMonth {
        id: calendar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large

        viewDate: root.currentDate

        onMonthShifted: delta => root.shiftMonth(delta)
        onTodayRequested: root.goToToday()
    }
}
