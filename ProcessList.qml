import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Shared process table used by both the compact Panel and the full window.
// Backed by a persistent ListModel reconciled in place (matched by pid) so rows
// glide to their new position on each refresh instead of the whole list being
// rebuilt and snapping around. Header click → requestSort; row right-click →
// rowMenu(proc, globalX, globalY) so the parent can position its own menu.
ColumnLayout {
  id: pl
  spacing: Style.marginXS

  property var m: null
  property var rows: []
  property string sortMode: "memory"
  property color cardColor: Color.mSurfaceVariant   // Panel uses NBox default; full window overrides
  property bool cardOpaque: false
  property int expandedPid: -1

  signal requestSort(string mode)
  signal rowMenu(var proc, real gx, real gy)

  function _human(kb) { return pl.m ? pl.m._humanKB(kb) : "--" }

  // Reconcile procModel to match `arr` (already filtered/sorted/limited) by pid.
  // ponytail: O(n*m) scan, fine for <=100 rows; switch to a pid->index map if it grows.
  function syncModel(arr) {
    arr = arr || []
    var i, j
    for (i = procModel.count - 1; i >= 0; i--) {
      var pid = procModel.get(i).pid
      var keep = false
      for (j = 0; j < arr.length; j++) if (arr[j].pid === pid) { keep = true; break }
      if (!keep) procModel.remove(i)
    }
    for (i = 0; i < arr.length; i++) {
      var p = arr[i]
      var cur = -1
      for (j = i; j < procModel.count; j++) if (procModel.get(j).pid === p.pid) { cur = j; break }
      if (cur === -1) procModel.insert(i, p)
      else { if (cur !== i) procModel.move(cur, i, 1); procModel.set(i, p) }
    }
  }
  onRowsChanged: syncModel(rows)
  Component.onCompleted: syncModel(rows)

  // ---- header ----
  RowLayout {
    Layout.fillWidth: true; Layout.leftMargin: Style.marginS; Layout.rightMargin: Style.marginS; spacing: Style.marginS
    Item { Layout.preferredWidth: 22 * Style.uiScaleRatio }
    NText { Layout.fillWidth: true; text: pl.m?.pluginApi?.tr("col.name") ?? "Name"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
    ColumnHeader { Layout.preferredWidth: 62 * Style.uiScaleRatio; modeKey: "cpu"; label: pl.m?.pluginApi?.tr("col.cpu") ?? "CPU" }
    ColumnHeader { Layout.preferredWidth: 84 * Style.uiScaleRatio; modeKey: "memory"; label: pl.m?.pluginApi?.tr("col.memory") ?? "Mem" }
    NText { Layout.preferredWidth: 52 * Style.uiScaleRatio; horizontalAlignment: Text.AlignRight; text: pl.m?.pluginApi?.tr("col.pid") ?? "PID"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
    Item { Layout.preferredWidth: 24 * Style.uiScaleRatio }
  }

  // ---- list ----
  NBox {
    Layout.fillWidth: true; Layout.fillHeight: true
    color: pl.cardColor; forceOpaque: pl.cardOpaque
    ListView {
      anchors.fill: parent; anchors.margins: Style.marginXS
      model: ListModel { id: procModel }
      spacing: 1; clip: true; cacheBuffer: 400; boundsBehavior: Flickable.StopAtBounds
      move: Transition { NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic } }
      displaced: Transition { NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic } }
      add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 } }
      remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 150 } }

      delegate: Rectangle {
        id: rowDelegate
        readonly property bool expanded: pl.expandedPid === model.pid
        readonly property real rowH: 32 * Style.uiScaleRatio
        readonly property real detailH: 58 * Style.uiScaleRatio
        width: ListView.view ? ListView.view.width : 0
        height: expanded ? rowH + detailH : rowH
        radius: Style.radiusS
        color: (rowMouse.containsMouse || expanded) ? Color.mHover : "transparent"
        clip: true
        Behavior on height { NumberAnimation { duration: Style.animationFast; easing.type: Easing.OutCubic } }
        Column {
          anchors.fill: parent; spacing: 0
          Item {
            width: parent.width; height: rowDelegate.rowH
            RowLayout {
              anchors.fill: parent; anchors.leftMargin: Style.marginS; anchors.rightMargin: Style.marginS; spacing: Style.marginS
              NIcon { Layout.preferredWidth: 22 * Style.uiScaleRatio; icon: "cpu"; pointSize: Style.fontSizeM; color: rowMouse.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant }
              NText { Layout.fillWidth: true; text: model.name; elide: Text.ElideRight; pointSize: Style.fontSizeS; color: rowMouse.containsMouse ? Color.mOnHover : Color.mOnSurface }
              MetricPill { Layout.preferredWidth: 62 * Style.uiScaleRatio; active: pl.sortMode === "cpu"; text: (model.cpu || 0).toFixed(1) + "%" }
              MetricPill { Layout.preferredWidth: 84 * Style.uiScaleRatio; active: pl.sortMode === "memory"; text: pl._human(model.rss) }
              NText { Layout.preferredWidth: 52 * Style.uiScaleRatio; horizontalAlignment: Text.AlignRight; text: model.pid; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
              NIcon {
                Layout.preferredWidth: 24 * Style.uiScaleRatio; icon: "chevron-down"; pointSize: Style.fontSizeM
                color: rowMouse.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
                rotation: rowDelegate.expanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Style.animationFast } }
              }
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                  var g = mapToGlobal(mouse.x, mouse.y)
                  pl.rowMenu({ pid: model.pid, ppid: model.ppid, name: model.name, fullCommand: model.fullCommand, cpu: model.cpu, mem: model.mem, rss: model.rss, username: model.username }, g.x, g.y)
                } else {
                  pl.expandedPid = rowDelegate.expanded ? -1 : model.pid
                }
              }
            }
          }
          Rectangle {
            width: parent.width; height: rowDelegate.detailH; visible: rowDelegate.expanded; color: "transparent"
            ColumnLayout {
              anchors.fill: parent; anchors.leftMargin: Style.marginL; anchors.rightMargin: Style.marginS; anchors.bottomMargin: Style.marginXS; spacing: Style.marginXS
              RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NText { text: pl.m?.pluginApi?.tr("detail.command") ?? "Command"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                NText { Layout.fillWidth: true; text: model.fullCommand || model.name; pointSize: Style.fontSizeXS; color: Color.mOnSurface; elide: Text.ElideRight; font.family: Settings.data.ui.fontFixed }
                NIconButton { baseSize: Style.baseWidgetSize * 0.62; icon: "copy"; tooltipText: pl.m?.pluginApi?.tr("ctx.copyCommand"); onClicked: pl.m?.copyText(model.fullCommand || model.name) }
              }
              RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NText { text: pl.m?.pluginApi?.tr("detail.ppid") ?? "PPID"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                NText { text: model.ppid; pointSize: Style.fontSizeXS; color: Color.mOnSurface }
                Item { Layout.preferredWidth: Style.marginL }
                NText { text: pl.m?.pluginApi?.tr("detail.mem") ?? "Mem"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                NText { text: (model.mem || 0).toFixed(1) + "%"; pointSize: Style.fontSizeXS; color: Color.mOnSurface }
                Item { Layout.fillWidth: true }
                NText { text: model.username; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
              }
            }
          }
        }
      }
    }
  }

  // ---- inline sub-components (table-only) ----
  component ColumnHeader: Item {
    id: ch
    property string modeKey: "cpu"
    property string label: ""
    readonly property bool active: pl.sortMode === ch.modeKey
    implicitHeight: chRow.implicitHeight
    RowLayout {
      id: chRow
      anchors.right: parent.right; spacing: 2
      NText { text: ch.label; pointSize: Style.fontSizeXS; font.weight: ch.active ? Style.fontWeightBold : Style.fontWeightRegular; color: ch.active ? Color.mPrimary : Color.mOnSurfaceVariant }
      NIcon { visible: ch.active; icon: "caret-down"; pointSize: Style.fontSizeXS; color: Color.mPrimary }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pl.requestSort(ch.modeKey) }
  }

  component MetricPill: Item {
    id: pill
    property string text: ""
    property bool active: false
    implicitHeight: 20 * Style.uiScaleRatio
    Rectangle {
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      width: pillText.implicitWidth + Style.marginM; height: parent.height; radius: height / 2
      color: pill.active ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
      NText { id: pillText; anchors.centerIn: parent; text: pill.text; pointSize: Style.fontSizeXS; font.weight: pill.active ? Style.fontWeightBold : Style.fontWeightRegular; color: pill.active ? Color.mPrimary : Color.mOnSurfaceVariant }
    }
  }
}
