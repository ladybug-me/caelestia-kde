import QtQuick

Item {
    id: topLeftRect

    property string welcomeString
    property string username

    function getPhase() {
        var now = new Date();
        var hour = now.getHours();
        if (hour >= 20 || hour < 4)
            welcomeString = qsTr("Good night");
        else if (hour >= 4 && hour < 10)
            welcomeString = qsTr("Good morning");
        else
            welcomeString = qsTr("Good afternoon");
    }

    Component.onCompleted: getPhase()

    Text {
        renderType: Text.NativeRendering
        width: 370
        text: "<span style='color:" + config.text + ";'>" + topLeftRect.welcomeString + " </span>" + "<span style='color:" + config.primary + ";'>" + topLeftRect.username + "</span>"
        textFormat: Text.RichText
        wrapMode: Text.WordWrap
        anchors.centerIn: parent
        font.family: "Rubik"
        font.bold: false
        font.pixelSize: 40
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Timer {
        interval: 60000
        running: true
        onTriggered: topLeftRect.getPhase()
        repeat: true
    }
}
