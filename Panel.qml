import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Compact bar-attached panel (opened by clicking the bar widget).
// The full-screen monitor lives in FullWindow.qml (opened via Mod+M).
Item {
  id: root
  property var pluginApi: null

  readonly property var geometryPlaceholder: panelContainer
  readonly property bool allowAttach: true
  property real contentPreferredWidth: 520 * Style.uiScaleRatio
  property real contentPreferredHeight: 560 * Style.uiScaleRatio

  readonly property var m: pluginApi?.mainInstance

  property string sortMode: m?.panelSortMode ?? "memory"
  property string scope: "all"
  property string query: ""
  property int expandedPid: -1

  property var menuProc: null
  property real menuX: 0
  property real menuY: 0

  Connections {
    target: root.m
    function onPanelSortModeChanged() { root.sortMode = root.m.panelSortMode }
  }

  readonly property int procLimit: (pluginApi?.pluginSettings?.processLimit) ?? 40
  readonly property bool showFilters: (pluginApi?.pluginSettings?.showFilters) ?? true
  readonly property var rows: root.m ? root.m.filteredProcesses(root.sortMode, root.scope, root.query, root.procLimit) : []

  anchors.fill: parent

  function _human(kb) { return root.m ? root.m._humanKB(kb) : "--" }
  function _accent(v, warn, crit) {
    if (v >= crit) return Color.mError
    if (v >= warn) return Color.mSecondary
    return Color.mPrimary
  }
  function _openSettings() {
    if (!pluginApi) return
    BarService.openPluginSettings(pluginApi.panelOpenScreen, pluginApi.manifest)
    pluginApi.closePanel(pluginApi.panelOpenScreen)
  }
  function _close() { if (pluginApi) pluginApi.closePanel(pluginApi.panelOpenScreen) }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        NIcon { icon: "device-analytics"; pointSize: Style.fontSizeXL; color: Color.mPrimary }
        NText { Layout.fillWidth: true; text: pluginApi?.tr("panel.title"); pointSize: Style.fontSizeL; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
        NIconButton { icon: "settings"; baseSize: Style.baseWidgetSize * 0.8; tooltipText: pluginApi?.tr("context.settings"); onClicked: root._openSettings() }
        NIconButton { icon: "close"; baseSize: Style.baseWidgetSize * 0.8; tooltipText: pluginApi?.tr("common.close"); onClicked: root._close() }
      }

      NBox {
        Layout.fillWidth: true
        implicitHeight: cHeaderRow.implicitHeight + Style.margin2M
        RowLayout {
          id: cHeaderRow
          anchors.fill: parent; anchors.margins: Style.marginM; spacing: Style.marginM
          ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            NText { Layout.fillWidth: true; text: root.m?.hostname || "localhost"; pointSize: Style.fontSizeL; font.weight: Style.fontWeightBold; color: Color.mOnSurface; elide: Text.ElideRight }
            NText {
              Layout.fillWidth: true
              text: {
                var parts = []
                if (root.m?.distro) parts.push(root.m.distro)
                parts.push((root.m?.procCount ?? 0) + " " + pluginApi?.tr("stats.procs"))
                if (root.m?.uptime) parts.push(pluginApi?.tr("stats.uptime") + " " + root.m.uptime)
                return parts.join("  •  ")
              }
              pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; elide: Text.ElideRight
            }
          }
          CircleGauge { value: (root.m?.cpuUsage ?? 0) / 100; label: Math.round(root.m?.cpuUsage ?? 0) + "%"; sublabel: pluginApi?.tr("stats.cpu"); detail: (root.m?.cpuTemp ?? 0) > 0 ? (Math.round(root.m.cpuTemp) + "°") : ""; accent: root._accent(root.m?.cpuUsage ?? 0, 50, 80) }
          CircleGauge { value: (root.m?.memUsage ?? 0) / 100; label: Math.round(root.m?.memUsage ?? 0) + "%"; sublabel: pluginApi?.tr("stats.memory"); detail: root.m ? root._human(root.m.memUsedKB) : ""; accent: root._accent(root.m?.memUsage ?? 0, 70, 90) }
          CircleGauge { visible: root.m?.hasGpu ?? false; value: Math.min(1, (root.m?.gpuTemp ?? 0) / 100); label: (root.m?.gpuTemp ?? 0) > 0 ? (Math.round(root.m.gpuTemp) + "°") : "--"; sublabel: pluginApi?.tr("stats.gpu"); detail: ""; accent: root._accent(root.m?.gpuTemp ?? 0, 70, 85) }
        }
      }

      RowLayout {
        Layout.fillWidth: true; visible: root.showFilters; spacing: Style.marginS
        Chip { scopeKey: "all"; label: pluginApi?.tr("filter.all") }
        Chip { scopeKey: "user"; label: pluginApi?.tr("filter.user") }
        Chip { scopeKey: "system"; label: pluginApi?.tr("filter.system") }
        NTextInput { Layout.fillWidth: true; label: ""; description: ""; inputIconName: "search"; placeholderText: pluginApi?.tr("panel.search"); text: root.query; onTextChanged: root.query = text }
      }

      ProcessTable { Layout.fillWidth: true; Layout.fillHeight: true }
    }

    // Right-click context menu
    MouseArea { anchors.fill: parent; visible: root.menuProc !== null; acceptedButtons: Qt.AllButtons; onPressed: root.menuProc = null; z: 50 }
    Rectangle {
      id: ctxMenu
      visible: root.menuProc !== null; z: 51
      width: 224 * Style.uiScaleRatio
      height: menuCol.implicitHeight + Style.marginS * 2
      x: Math.max(Style.marginS, Math.min(root.menuX, panelContainer.width - width - Style.marginS))
      y: Math.max(Style.marginS, Math.min(root.menuY, panelContainer.height - height - Style.marginS))
      radius: Style.radiusM; color: Color.mSurface; border.color: Color.mOutline; border.width: Style.borderS
      ColumnLayout {
        id: menuCol
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.marginS; spacing: 0
        MenuItem { icon: "hash"; label: pluginApi?.tr("ctx.copyPid");     onActivated: root.m?.copyText(root.menuProc.pid) }
        MenuItem { icon: "tag";  label: pluginApi?.tr("ctx.copyName");    onActivated: root.m?.copyText(root.menuProc.name) }
        MenuItem { icon: "code"; label: pluginApi?.tr("ctx.copyCommand"); onActivated: root.m?.copyText(root.menuProc.fullCommand || root.menuProc.name) }
        NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXXS; Layout.bottomMargin: Style.marginXXS }
        MenuItem { icon: "x";     label: pluginApi?.tr("ctx.kill");      danger: true; onActivated: root.m?.killProcess(root.menuProc.pid, "TERM") }
        MenuItem { icon: "skull"; label: pluginApi?.tr("ctx.forceKill"); danger: true; onActivated: root.m?.killProcess(root.menuProc.pid, "KILL") }
      }
    }
  }

  // =========================== inline components ===========================

  component ProcessTable: ColumnLayout {
    spacing: Style.marginXS
    RowLayout {
      Layout.fillWidth: true; Layout.leftMargin: Style.marginS; Layout.rightMargin: Style.marginS; spacing: Style.marginS
      Item { Layout.preferredWidth: 22 * Style.uiScaleRatio }
      NText { Layout.fillWidth: true; text: pluginApi?.tr("col.name"); pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
      ColumnHeader { Layout.preferredWidth: 62 * Style.uiScaleRatio; modeKey: "cpu"; label: pluginApi?.tr("col.cpu") }
      ColumnHeader { Layout.preferredWidth: 84 * Style.uiScaleRatio; modeKey: "memory"; label: pluginApi?.tr("col.memory") }
      NText { Layout.preferredWidth: 52 * Style.uiScaleRatio; horizontalAlignment: Text.AlignRight; text: pluginApi?.tr("col.pid"); pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
      Item { Layout.preferredWidth: 24 * Style.uiScaleRatio }
    }
    NBox {
      Layout.fillWidth: true; Layout.fillHeight: true
      ListView {
        anchors.fill: parent; anchors.margins: Style.marginXS
        model: root.rows; spacing: 1; clip: true; cacheBuffer: 400; boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
          id: rowDelegate
          required property var modelData
          readonly property bool expanded: root.expandedPid === rowDelegate.modelData.pid
          readonly property real rowH: 32 * Style.uiScaleRatio
          readonly property real detailH: 58 * Style.uiScaleRatio
          width: ListView.view.width
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
                NText { Layout.fillWidth: true; text: rowDelegate.modelData.name; elide: Text.ElideRight; pointSize: Style.fontSizeS; color: rowMouse.containsMouse ? Color.mOnHover : Color.mOnSurface }
                MetricPill { Layout.preferredWidth: 62 * Style.uiScaleRatio; active: root.sortMode === "cpu"; text: rowDelegate.modelData.cpu.toFixed(1) + "%" }
                MetricPill { Layout.preferredWidth: 84 * Style.uiScaleRatio; active: root.sortMode === "memory"; text: root._human(rowDelegate.modelData.rss) }
                NText { Layout.preferredWidth: 52 * Style.uiScaleRatio; horizontalAlignment: Text.AlignRight; text: rowDelegate.modelData.pid; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
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
                    var pt = mapToItem(panelContainer, mouse.x, mouse.y)
                    root.menuX = pt.x; root.menuY = pt.y; root.menuProc = rowDelegate.modelData
                  } else {
                    root.expandedPid = rowDelegate.expanded ? -1 : rowDelegate.modelData.pid
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
                  NText { text: pluginApi?.tr("detail.command"); pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                  NText { Layout.fillWidth: true; text: rowDelegate.modelData.fullCommand || rowDelegate.modelData.name; pointSize: Style.fontSizeXS; color: Color.mOnSurface; elide: Text.ElideRight; font.family: Settings.data.ui.fontFixed }
                  NIconButton { baseSize: Style.baseWidgetSize * 0.62; icon: "copy"; tooltipText: pluginApi?.tr("ctx.copyCommand"); onClicked: root.m?.copyText(rowDelegate.modelData.fullCommand || rowDelegate.modelData.name) }
                }
                RowLayout {
                  Layout.fillWidth: true; spacing: Style.marginS
                  NText { text: pluginApi?.tr("detail.ppid"); pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                  NText { text: rowDelegate.modelData.ppid; pointSize: Style.fontSizeXS; color: Color.mOnSurface }
                  Item { Layout.preferredWidth: Style.marginL }
                  NText { text: pluginApi?.tr("detail.mem"); pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                  NText { text: (rowDelegate.modelData.mem || 0).toFixed(1) + "%"; pointSize: Style.fontSizeXS; color: Color.mOnSurface }
                  Item { Layout.fillWidth: true }
                  NText { text: rowDelegate.modelData.username; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
                }
              }
            }
          }
        }
      }
    }
  }

  component MenuItem: Rectangle {
    id: mi
    property string icon: ""
    property string label: ""
    property bool danger: false
    signal activated()
    Layout.fillWidth: true
    Layout.preferredHeight: Math.round(Style.baseWidgetSize * 0.95 * Style.uiScaleRatio)
    radius: Style.radiusS
    color: miMouse.containsMouse ? Color.mHover : "transparent"
    RowLayout {
      anchors.fill: parent; anchors.leftMargin: Style.marginS; anchors.rightMargin: Style.marginS; spacing: Style.marginS
      NIcon { icon: mi.icon; pointSize: Style.fontSizeM; color: miMouse.containsMouse ? Color.mOnHover : (mi.danger ? Color.mError : Color.mOnSurfaceVariant) }
      NText { Layout.fillWidth: true; text: mi.label; pointSize: Style.fontSizeS; color: miMouse.containsMouse ? Color.mOnHover : (mi.danger ? Color.mError : Color.mOnSurface) }
    }
    MouseArea { id: miMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { mi.activated(); root.menuProc = null } }
  }

  component Chip: Rectangle {
    id: chip
    property string scopeKey: "all"
    property string label: ""
    readonly property bool selected: root.scope === chip.scopeKey
    implicitWidth: chipText.implicitWidth + Style.marginL * 2
    implicitHeight: Math.round(Style.baseWidgetSize * 0.9 * Style.uiScaleRatio)
    radius: height / 2
    color: selected ? Color.mPrimary : Color.mSurfaceVariant
    NText { id: chipText; anchors.centerIn: parent; text: chip.label; pointSize: Style.fontSizeXS; font.weight: chip.selected ? Style.fontWeightBold : Style.fontWeightRegular; color: chip.selected ? Color.mOnPrimary : Color.mOnSurface }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.scope = chip.scopeKey }
  }

  component ColumnHeader: Item {
    id: ch
    property string modeKey: "cpu"
    property string label: ""
    readonly property bool active: root.sortMode === ch.modeKey
    implicitHeight: chRow.implicitHeight
    RowLayout {
      id: chRow
      anchors.right: parent.right; spacing: 2
      NText { text: ch.label; pointSize: Style.fontSizeXS; font.weight: ch.active ? Style.fontWeightBold : Style.fontWeightRegular; color: ch.active ? Color.mPrimary : Color.mOnSurfaceVariant }
      NIcon { visible: ch.active; icon: "caret-down"; pointSize: Style.fontSizeXS; color: Color.mPrimary }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.sortMode = ch.modeKey }
  }

  component MetricPill: Item {
    id: pill
    property string text: ""
    property bool active: false
    implicitHeight: 20 * Style.uiScaleRatio
    Rectangle {
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      width: pillText.implicitWidth + Style.marginM; height: parent.height; radius: height / 2
      color: pill.active ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18) : Color.mSurface
      NText { id: pillText; anchors.centerIn: parent; text: pill.text; pointSize: Style.fontSizeXS; font.weight: pill.active ? Style.fontWeightBold : Style.fontWeightRegular; color: pill.active ? Color.mPrimary : Color.mOnSurfaceVariant }
    }
  }

  component CircleGauge: Item {
    id: gauge
    property real value: 0
    property string label: ""
    property string sublabel: ""
    property string detail: ""
    property color accent: Color.mPrimary
    implicitWidth: 80 * Style.uiScaleRatio
    implicitHeight: 80 * Style.uiScaleRatio
    onValueChanged: cv.requestPaint()
    onAccentChanged: cv.requestPaint()
    Canvas {
      id: cv
      anchors.fill: parent
      onPaint: {
        var ctx = getContext("2d"); ctx.reset()
        var cx = width / 2, cy = height / 2
        var r = Math.min(width, height) / 2 - 6
        var s = -Math.PI / 2, e = Math.PI * 1.5
        ctx.lineCap = "round"; ctx.lineWidth = 6
        ctx.beginPath(); ctx.arc(cx, cy, r, s, e)
        ctx.strokeStyle = Qt.rgba(gauge.accent.r, gauge.accent.g, gauge.accent.b, 0.15); ctx.stroke()
        var v = Math.max(0, Math.min(1, gauge.value))
        if (v > 0) { ctx.beginPath(); ctx.arc(cx, cy, r, s, s + (e - s) * v); ctx.strokeStyle = gauge.accent; ctx.stroke() }
      }
    }
    Column {
      anchors.centerIn: parent; width: gauge.width - 16; spacing: 0
      NText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: gauge.label; pointSize: Style.fontSizeM; font.weight: Style.fontWeightBold; color: Color.mOnSurface; elide: Text.ElideRight }
      NText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: gauge.sublabel; pointSize: Style.fontSizeXXS; color: gauge.accent; elide: Text.ElideRight }
      NText { visible: gauge.detail.length > 0; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: gauge.detail; pointSize: Style.fontSizeXXS; color: Color.mOnSurfaceVariant; elide: Text.ElideRight }
    }
  }
}
