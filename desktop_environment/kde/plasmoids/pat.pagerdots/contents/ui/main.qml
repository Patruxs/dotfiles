import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property string activeMark: "●"      // ● shown for the current desktop
    readonly property real dimOpacity: 0.55            // other desktops
    readonly property int currentIndex: vdi.desktopIds.indexOf(vdi.currentDesktop)

    TaskManager.VirtualDesktopInfo { id: vdi }

    function switchTo(index) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin", path: "/KWin", iface: "org.kde.KWin",
            member: "setCurrentDesktop", arguments: [index + 1], signature: "i"
        });
    }
    function step(delta) {
        const n = vdi.numberOfDesktops;
        if (n < 1) return;
        switchTo((currentIndex + delta + n) % n);
    }

    preferredRepresentation: fullRepresentation

    fullRepresentation: MouseArea {
        acceptedButtons: Qt.NoButton
        implicitWidth: grid.implicitWidth
        implicitHeight: grid.implicitHeight
        Layout.minimumWidth: root.vertical ? 0 : grid.implicitWidth
        Layout.minimumHeight: root.vertical ? grid.implicitHeight : 0
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight
        onWheel: wheel => root.step(wheel.angleDelta.y < 0 ? 1 : -1)

        GridLayout {
            id: grid
            anchors.fill: parent
            rows: root.vertical ? -1 : 1
            columns: root.vertical ? 1 : -1
            rowSpacing: 0
            columnSpacing: 0

            Repeater {
                model: vdi.numberOfDesktops
                delegate: PC3.Label {
                    required property int index
                    readonly property bool isCurrent: index === root.currentIndex

                    Layout.fillHeight: !root.vertical
                    Layout.fillWidth: root.vertical
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 1.4
                    Layout.minimumHeight: Kirigami.Units.gridUnit * 1.4
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: isCurrent ? root.activeMark : (index + 1)
                    opacity: isCurrent || hover.containsMouse ? 1 : root.dimOpacity
                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.switchTo(parent.index)
                    }
                    PC3.ToolTip.text: vdi.desktopNames[index] ?? ""
                    PC3.ToolTip.visible: hover.containsMouse
                    PC3.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }
        }
    }
}
