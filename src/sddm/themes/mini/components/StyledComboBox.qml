pragma ComponentBehavior: Bound
import "../singletons"
import QtQuick
import QtQuick.Controls

ComboBox {
    id: root

    property var onRestoreFocus: function () {}

    hoverEnabled: true
    focusPolicy: Qt.ClickFocus
    onActivated: onRestoreFocus()
    Keys.onPressed: function (event) {
        if (popup.visible) {
            if (event.key === Qt.Key_Escape) {
                popup.close();
                event.accepted = true;
                onRestoreFocus();
            }
        } else {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true;
                onRestoreFocus();
            }
        }
    }

    background: Rectangle {
        color: Theme.withAlpha(Theme.mSurface, Theme.elementOpacity)
        radius: Math.min(Theme.elementRadius, Math.min(root.width, root.height) / 2)
        border.color: (root.hovered || root.popup.visible) ? Theme.mHover : Theme.mOutline
        border.width: 2

        Behavior on border.color {
            ColorAnimation {
                duration: 200
            }
        }
    }

    contentItem: Text {
        text: root.displayText
        font: root.font
        color: Theme.mOnSurface
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Qt.AlignHCenter
        leftPadding: 0
        rightPadding: 0
        anchors.fill: parent
    }

    indicator: Canvas {
        x: root.width - 30
        y: (root.height - 6) / 2
        width: 12
        height: 6
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.moveTo(0, 0);
            ctx.lineTo(width, 0);
            ctx.lineTo(width / 2, height);
            ctx.closePath();
            ctx.fillStyle = Theme.mPrimary;
            ctx.fill();
        }
    }

    delegate: ItemDelegate {
        id: delegateItem

        required property int index
        required property var model

        width: root.width - 16
        hoverEnabled: true

        contentItem: Text {
            text: root.textRole ? delegateItem.model[root.textRole] : delegateItem.model.modelData
            font: root.font
            color: (root.highlightedIndex === delegateItem.index || delegateItem.hovered) ? Theme.mOnPrimary : Theme.mOnSurface
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Qt.AlignHCenter
            anchors.fill: parent
        }

        background: Rectangle {
            color: (root.highlightedIndex === delegateItem.index || delegateItem.hovered) ? Theme.mPrimary : "transparent"
            radius: Math.min(Theme.elementRadius, Math.min(parent.width, parent.height) / 2)
        }
    }

    popup: Popup {
        y: root.height - 1
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: root.onRestoreFocus()
        width: root.width
        implicitHeight: popupList.implicitHeight

        contentItem: ListView {
            id: popupList

            topMargin: 6
            bottomMargin: 6
            leftMargin: 2
            rightMargin: 2
            implicitHeight: Math.min(contentHeight + topMargin + bottomMargin, 250)
            model: root.delegateModel
            currentIndex: root.highlightedIndex
            clip: true

            ScrollIndicator.vertical: ScrollIndicator {}
        }

        background: Rectangle {
            color: Theme.withAlpha(Theme.mSurface, Theme.elementOpacity)
            border.color: Theme.mOutline
            border.width: 2
            radius: Math.min(Theme.elementRadius, Math.min(root.width, popupList.implicitHeight) / 2)
        }
    }
}
