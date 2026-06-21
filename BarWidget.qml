import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  // ---- Injected by the shell ----
  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  // ---- Settings (per-instance) ----
  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property bool showCpu: cfg.showCpu ?? defaults.showCpu ?? false
  readonly property bool showCpuTemp: cfg.showCpuTemp ?? defaults.showCpuTemp ?? false
  readonly property bool showMemory: cfg.showMemory ?? defaults.showMemory ?? true
  readonly property bool showGpu: cfg.showGpu ?? defaults.showGpu ?? false
  readonly property bool combined: cfg.combined ?? defaults.combined ?? false
  readonly property bool boldText: cfg.boldText ?? defaults.boldText ?? true
  readonly property bool showIcon: cfg.showIcon ?? defaults.showIcon ?? true
  readonly property string iconCpu: cfg.iconCpu ?? defaults.iconCpu ?? ""
  readonly property string iconCpuTemp: cfg.iconCpuTemp ?? defaults.iconCpuTemp ?? ""
  readonly property string iconMemory: cfg.iconMemory ?? defaults.iconMemory ?? ""
  readonly property string iconGpu: cfg.iconGpu ?? defaults.iconGpu ?? ""
  readonly property string iconColorKey: cfg.iconColor ?? defaults.iconColor ?? "none"
  readonly property string textColorKey: cfg.textColor ?? defaults.textColor ?? "none"

  // Ordered list of metrics to display; never empty.
  readonly property var metrics: {
    var a = []
    if (showCpu) a.push("cpu")
    if (showCpuTemp) a.push("cputemp")
    if (showMemory) a.push("memory")
    if (showGpu) a.push("gpu")
    return a.length ? a : ["memory"]
  }
  // A single metric is trivially "combined" (one capsule).
  readonly property bool asCombined: combined || metrics.length <= 1

  // ---- Bar layout awareness ----
  readonly property string screenName: screen?.name ?? ""
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

  readonly property var mainInstance: pluginApi?.mainInstance

  // ---- metric helpers ----
  function mIcon(key) {
    if (key === "cpu") return "cpu-usage"
    if (key === "cputemp") return "cpu-temperature"
    if (key === "gpu") return "gpu-temperature"
    return "memory"
  }
  function mIsTemp(key) { return key === "cputemp" || key === "gpu" }
  function mValue(key) {
    var m = root.mainInstance
    if (!m) return 0
    if (key === "cpu") return m.cpuUsage
    if (key === "cputemp") return m.cpuTemp
    if (key === "gpu") return m.gpuTemp
    return m.memUsage
  }
  function mText(key) {
    if (!root.mainInstance?.hasData) return "--"
    var v = Math.round(mValue(key))
    return mIsTemp(key) ? (v + "°") : (v + "%")
  }
  // Process column the panel should sort by when this metric is clicked.
  function mSort(key) { return key === "memory" ? "memory" : "cpu" }
  function mDynamicColor(key) {
    var v = mValue(key)
    if (mIsTemp(key)) {
      if (v >= 85) return Color.mError
      if (v >= 70) return Color.mSecondary
      return Color.mOnSurface
    }
    if (v >= 90) return Color.mError
    if (v >= 70) return Color.mSecondary
    return Color.mOnSurface
  }
  function mTextColor(key, hovered) {
    if (hovered) return Color.mOnHover
    if (textColorKey !== "none") return Color.resolveColorKey(textColorKey)
    return mDynamicColor(key)
  }
  function mIconColor(key, hovered) {
    if (hovered) return Color.mOnHover
    if (iconColorKey !== "none") return Color.resolveColorKey(iconColorKey)
    return mDynamicColor(key)
  }
  function iconOverrideFor(key) {
    if (key === "cpu") return iconCpu
    if (key === "cputemp") return iconCpuTemp
    if (key === "gpu") return iconGpu
    return iconMemory
  }
  function effIcon(key) {
    var o = iconOverrideFor(key)
    return o !== "" ? o : mIcon(key)
  }

  // Open the compact panel sorted by the clicked metric (per-metric sort, #5).
  function activate(key) {
    if (root.mainInstance) root.mainInstance.panelSortMode = mSort(key)
    if (pluginApi) pluginApi.togglePanel(root.screen, root)
  }
  function showMenu() { PanelService.showContextMenu(contextMenu, root, screen) }
  function showTip() {
    var m = root.mainInstance
    if (!m || !m.hasData) {
      TooltipService.show(root, pluginApi?.tr("widget.loading"), BarService.getTooltipDirection())
      return
    }
    var tip = pluginApi?.tr("stats.cpu") + ": " + Math.round(m.cpuUsage) + "%"
    if (m.cpuTemp > 0) tip += "  " + Math.round(m.cpuTemp) + "°"
    tip += "\n" + pluginApi?.tr("stats.memory") + ": " + Math.round(m.memUsage) + "%"
    tip += "  (" + m._humanKB(m.memUsedKB) + " / " + m._humanKB(m.memTotalKB) + ")"
    if (m.hasGpu) tip += "\n" + pluginApi?.tr("stats.gpu") + ": " + Math.round(m.gpuTemp) + "°"
    tip += "\n" + pluginApi?.tr("stats.procs") + ": " + m.procCount
    if (m.uptime) tip += "\n" + pluginApi?.tr("stats.uptime") + ": " + m.uptime
    TooltipService.show(root, tip, BarService.getTooltipDirection())
  }

  // ---- sizing ----
  implicitWidth: barRow.implicitWidth
  implicitHeight: capsuleHeight

  // ---- Right-click context menu (shared) ----
  NPopupContextMenu {
    id: contextMenu
    model: [
      { "label": pluginApi?.tr("context.refresh"),  "action": "refresh",  "icon": "refresh" },
      { "label": pluginApi?.tr("context.settings"), "action": "settings", "icon": "settings" }
    ]
    onTriggered: action => {
      contextMenu.close()
      PanelService.closeContextMenu(screen)
      if (action === "refresh") root.mainInstance?.refresh()
      else if (action === "settings" && pluginApi) BarService.openPluginSettings(screen, pluginApi.manifest)
    }
  }

  Row {
    id: barRow
    anchors.centerIn: parent
    spacing: root.asCombined ? 0 : Style.marginXS

    // --- combined: a single capsule holding every metric ---
    Rectangle {
      id: combinedCapsule
      visible: root.asCombined
      width: combinedRow.implicitWidth + Style.marginM * 2
      height: root.capsuleHeight
      radius: Style.radiusL
      color: Style.capsuleColor
      border.color: Style.capsuleBorderColor
      border.width: Style.capsuleBorderWidth

      RowLayout {
        id: combinedRow
        anchors.centerIn: parent
        spacing: Style.marginM
        Repeater {
          model: root.asCombined ? root.metrics : []
          delegate: Cell { mkey: modelData }
        }
      }
    }

    // --- separate: one capsule per metric ---
    Repeater {
      model: root.asCombined ? [] : root.metrics
      delegate: Rectangle {
        width: sepCell.implicitWidth + Style.marginM * 2
        height: root.capsuleHeight
        radius: Style.radiusL
        color: sepCell.hovered ? Color.mHover : Style.capsuleColor
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth
        Cell { id: sepCell; anchors.centerIn: parent; mkey: modelData }
      }
    }
  }

  // One metric: icon + value, with its own click/hover handling.
  component Cell: Item {
    id: cell
    property string mkey: "memory"
    property alias hovered: cellMouse.containsMouse
    implicitWidth: cellRow.implicitWidth
    implicitHeight: root.capsuleHeight

    RowLayout {
      id: cellRow
      anchors.centerIn: parent
      spacing: Style.marginXS

      NIcon {
        visible: root.showIcon
        icon: root.effIcon(cell.mkey)
        color: root.mIconColor(cell.mkey, cellMouse.containsMouse)
        applyUiScale: true
      }
      NText {
        text: root.mText(cell.mkey)
        color: root.mTextColor(cell.mkey, cellMouse.containsMouse)
        pointSize: root.barFontSize
        applyUiScale: false
        font.weight: root.boldText ? Font.Bold : Font.Normal
      }
    }

    MouseArea {
      id: cellMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: mouse => {
        if (mouse.button === Qt.LeftButton) root.activate(cell.mkey)
        else if (mouse.button === Qt.RightButton) root.showMenu()
        else if (mouse.button === Qt.MiddleButton) root.mainInstance?.refresh()
      }
      onEntered: root.showTip()
      onExited: TooltipService.hide()
    }
  }
}
