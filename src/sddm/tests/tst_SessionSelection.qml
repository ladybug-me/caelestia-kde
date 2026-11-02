import QtQuick
import QtTest
import "../themes/full/components" as Theme

TestCase {
    id: testCase
    name: "SessionSelection"
    property var config: ({
            subComponents: "black",
            primary: "white",
            text: "white",
            onPrimary: "black",
            outline: "grey",
            inverseOnSurface: "white"
        })
    // SDDM's SessionModel reports lastIndex as a constant that starts at 0 and
    // only ever moves to a matching row, so it is all the saved state there is.
    property var sessionModel: ListModel {
        property int lastIndex: 0
    }
    Component {
        id: pickerComponent
        Theme.SessionPicker {}
    }

    function populate(names, savedIndex) {
        sessionModel.clear();
        for (const name of names)
            sessionModel.append({
                name: name
            });
        sessionModel.lastIndex = savedIndex;
    }

    function test_initialSelection_data() {
        return [
            {
                tag: "saved-first",
                names: ["Plasma (Wayland)", "Other desktop"],
                saved: 0,
                expected: 0
            },
            {
                tag: "saved-other-desktop",
                names: ["Plasma (Wayland)", "Other desktop"],
                saved: 1,
                expected: 1
            },
            {
                tag: "single-session",
                names: ["Plasma (Wayland)"],
                saved: 0,
                expected: 0
            },
            {
                tag: "no-sessions",
                names: [],
                saved: 0,
                expected: 0
            }
        ];
    }
    function test_initialSelection(data) {
        populate(data.names, data.saved);
        const picker = createTemporaryObject(pickerComponent, testCase);
        verify(picker !== null);
        compare(picker.count, data.names.length);
        compare(picker.selectedIndex, data.expected);
        compare(picker.currentText, data.names[data.expected] ?? "");
    }
    function test_switchingSessionUpdatesLabel() {
        populate(["Plasma (Wayland)", "Other desktop"], 1);
        const picker = createTemporaryObject(pickerComponent, testCase);
        verify(picker !== null);
        for (let i = 0; i < picker.count; ++i) {
            picker.selectedIndex = i;
            compare(picker.currentText, picker.items[i]);
        }
    }
}
