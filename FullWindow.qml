import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Full "System Monitor" as a real, movable & resizable xdg window (opened via Mod+M).
// niri floats/sizes it via a window-rule matching the title.
FloatingWindow {
  id: win
  property var pluginApi: null
  readonly property var m: pluginApi?.mainInstance

  title: "K-Monitoring"
  // Background palette + opacity come from settings (accents stay matugen).
  readonly property string bgHex: pluginApi?.pluginSettings?.fullWindowBg ?? "#0f0f13"
  readonly property string cardHex: pluginApi?.pluginSettings?.fullCardBg ?? "#1e1e25"
  readonly property real bgOpacity: pluginApi?.pluginSettings?.fullOpacity ?? 1.0
  readonly property color _bgBase: bgHex
  readonly property color _cardBase: cardHex
  readonly property color windowBg: Qt.rgba(_bgBase.r, _bgBase.g, _bgBase.b, bgOpacity)
  readonly property color cardBg: Qt.rgba(_cardBase.r, _cardBase.g, _cardBase.b, bgOpacity)
  color: win.windowBg
  implicitWidth: Math.round(960 * Style.uiScaleRatio)
  implicitHeight: Math.round(680 * Style.uiScaleRatio)
  minimumSize: Qt.size(Math.round(640 * Style.uiScaleRatio), Math.round(440 * Style.uiScaleRatio))
  visible: false

  // ---- state ----
  property string sortMode: m?.panelSortMode ?? "memory"
  property string scope: "all"
  property string query: ""
  property int currentTab: 0
  property var menuProc: null
  property real menuX: 0
  property real menuY: 0

  readonly property int procLimit: (pluginApi?.pluginSettings?.processLimit) ?? 40
  readonly property var rows: win.m ? win.m.filteredProcesses(win.sortMode, win.scope, win.query, win.procLimit) : []

  function _human(kb) { return win.m ? win.m._humanKB(kb) : "--" }
  function _spd(b) { return win.m ? win.m.formatSpeed(b) : "--" }
  function _accent(v, warn, crit) {
    if (v >= crit) return Color.mError
    if (v >= warn) return Color.mSecondary
    return Color.mPrimary
  }
  // Effective icon for a metric, honoring per-metric overrides from settings (fix #1).
  function metricIcon(key, fallback) {
    var s = pluginApi?.pluginSettings || ({})
    var o = key === "cpu" ? s.iconCpu : key === "cputemp" ? s.iconCpuTemp : key === "memory" ? s.iconMemory : key === "gpu" ? s.iconGpu : ""
    return (o && o !== "") ? o : fallback
  }

  Item {
    id: contentRoot
    anchors.fill: parent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Header — click-and-hold anywhere here (except the buttons) drags the window.
      Item {
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.SizeAllCursor
          onPressed: win.startSystemMove()
          onDoubleClicked: win.maximized = !win.maximized
        }
        RowLayout {
          id: headerRow
          anchors.fill: parent
          spacing: Style.marginS
          NIcon { icon: "device-analytics"; pointSize: Style.fontSizeXXL; color: Color.mPrimary }
          NText { Layout.fillWidth: true; text: pluginApi?.tr("full.title"); pointSize: Style.fontSizeXL; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
          NIconButton { icon: "settings"; baseSize: Style.baseWidgetSize * 0.85; tooltipText: pluginApi?.tr("context.settings"); onClicked: { if (win.pluginApi) win.pluginApi.withCurrentScreen(function (s) { BarService.openPluginSettings(s, win.pluginApi.manifest) }) } }
          NIconButton { icon: "close"; baseSize: Style.baseWidgetSize * 0.85; tooltipText: pluginApi?.tr("common.close"); onClicked: win.visible = false }
        }
      }

      // Tabs + filters/search
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS
        TabBtn { tabIndex: 0; icon: "list"; label: pluginApi?.tr("tab.processes") }
        TabBtn { tabIndex: 1; icon: "chart-line"; label: pluginApi?.tr("tab.performance") }
        TabBtn { tabIndex: 2; icon: "server-2"; label: pluginApi?.tr("tab.disks") }
        TabBtn { tabIndex: 3; icon: "device-desktop-analytics"; label: pluginApi?.tr("tab.system") }
        Item { Layout.fillWidth: true }
        Chip { visible: win.currentTab === 0; scopeKey: "all"; label: pluginApi?.tr("filter.all") }
        Chip { visible: win.currentTab === 0; scopeKey: "user"; label: pluginApi?.tr("filter.user") }
        Chip { visible: win.currentTab === 0; scopeKey: "system"; label: pluginApi?.tr("filter.system") }
        NTextInput { visible: win.currentTab === 0; Layout.preferredWidth: 220 * Style.uiScaleRatio; label: ""; description: ""; inputIconName: "search"; placeholderText: pluginApi?.tr("panel.search"); text: win.query; onTextChanged: win.query = text }
      }

      StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: win.currentTab

        // ---- 0 Processes ----
        ProcessList {
          m: win.m; rows: win.rows; sortMode: win.sortMode
          cardColor: win.cardBg; cardOpaque: true
          onRequestSort: mode => win.sortMode = mode
          onRowMenu: (proc, gx, gy) => {
            var p = contentRoot.mapFromGlobal(gx, gy)
            win.menuX = p.x; win.menuY = p.y; win.menuProc = proc
          }
        }

        // ---- 1 Performance ----
        GridLayout {
          columns: 2; rowSpacing: Style.marginM; columnSpacing: Style.marginM
          PerfCard {
            title: pluginApi?.tr("stats.cpu"); icon: win.metricIcon("cpu", "cpu-usage")
            bigValue: Math.round(win.m?.cpuUsage ?? 0) + "%"
            subText: win.m?.cpuModel || ""
            topRight: (win.m?.cpuTemp ?? 0) > 0 ? (Math.round(win.m.cpuTemp) + "°C") : ""
            topRightColor: Color.mSecondary
            values: win.m?.cpuHistory ?? []; values2: win.m?.cpuTempHistory ?? []; maxVal: 100
          }
          PerfCard {
            title: pluginApi?.tr("stats.memory"); icon: win.metricIcon("memory", "memory")
            bigValue: Math.round(win.m?.memUsage ?? 0) + "%"
            subText: win.m ? (win._human(win.m.memUsedKB) + " / " + win._human(win.m.memTotalKB)) : ""
            topRight: (win.m?.swapTotalKB ?? 0) > 0 ? (pluginApi?.tr("full.swap") + " " + win._human(win.m.swapUsedKB)) : ""
            values: win.m?.memHistory ?? []; maxVal: 100
          }
          PerfCard {
            title: pluginApi?.tr("full.network"); icon: "network"; accent: Color.mTertiary
            bigValue: "↓ " + win._spd(win.m?.rxSpeed ?? 0); subText: "↑ " + win._spd(win.m?.txSpeed ?? 0)
            values: win.m?.netRxHistory ?? []; values2: win.m?.netTxHistory ?? []; autoScale: true
          }
          PerfCard {
            title: pluginApi?.tr("full.disk"); icon: "server-2"; accent: Color.mSecondary
            bigValue: "R: " + win._spd(win.m?.diskRead ?? 0); subText: "W: " + win._spd(win.m?.diskWrite ?? 0)
            values: win.m?.diskRHistory ?? []; values2: win.m?.diskWHistory ?? []; autoScale: true
          }
        }

        // ---- 2 Disks ----
        ColumnLayout {
          spacing: Style.marginM
          NBox {
            Layout.fillWidth: true
            implicitHeight: ioRow.implicitHeight + Style.margin2M
            color: win.cardBg; forceOpaque: true
            RowLayout {
              id: ioRow
              anchors.fill: parent; anchors.margins: Style.marginM; spacing: Style.marginL
              NIcon { icon: "server-2"; pointSize: Style.fontSizeL; color: Color.mPrimary }
              NText { text: pluginApi?.tr("full.diskIo"); pointSize: Style.fontSizeM; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
              Item { Layout.fillWidth: true }
              NText { text: pluginApi?.tr("full.read") + " "; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
              NText { text: win._spd(win.m?.diskRead ?? 0); pointSize: Style.fontSizeS; font.weight: Style.fontWeightBold; color: Color.mPrimary; font.family: Settings.data.ui.fontFixed }
              NText { text: "  " + pluginApi?.tr("full.write") + " "; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
              NText { text: win._spd(win.m?.diskWrite ?? 0); pointSize: Style.fontSizeS; font.weight: Style.fontWeightBold; color: Color.mSecondary; font.family: Settings.data.ui.fontFixed }
            }
          }
          NBox {
            Layout.fillWidth: true; Layout.fillHeight: true
            color: win.cardBg; forceOpaque: true
            ColumnLayout {
              anchors.fill: parent; anchors.margins: Style.marginM; spacing: Style.marginXS
              RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NIcon { icon: "folder"; pointSize: Style.fontSizeM; color: Color.mPrimary }
                NText { text: pluginApi?.tr("full.mounts"); pointSize: Style.fontSizeM; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
              }
              NScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true
                ColumnLayout { width: parent.width; spacing: Style.marginXS; Repeater { model: win.m?.mounts ?? []; delegate: MountRow {} } }
              }
            }
          }
        }

        // ---- 3 System ----
        ColumnLayout {
          spacing: Style.marginM
          NBox {
            Layout.fillWidth: true
            implicitHeight: sysCol.implicitHeight + Style.margin2M
            color: win.cardBg; forceOpaque: true
            ColumnLayout {
              id: sysCol
              anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.marginM; spacing: Style.marginS
              RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NIcon { icon: "device-desktop-analytics"; pointSize: Style.fontSizeL; color: Color.mPrimary }
                NText { text: pluginApi?.tr("full.sysInfo"); pointSize: Style.fontSizeM; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
              }
              GridLayout {
                Layout.fillWidth: true; columns: 2; columnSpacing: Style.marginXL * 2; rowSpacing: Style.marginXS
                InfoItem { label: pluginApi?.tr("full.hostname"); value: win.m?.hostname || "—" }
                InfoItem { label: pluginApi?.tr("full.distro"); value: win.m?.distro || "—" }
                InfoItem { label: pluginApi?.tr("full.kernel"); value: win.m?.kernel || "—" }
                InfoItem { label: pluginApi?.tr("full.arch"); value: win.m?.arch || "—" }
                InfoItem { label: pluginApi?.tr("stats.cpu"); value: win.m?.cpuModel || "—" }
                InfoItem { label: pluginApi?.tr("full.ram"); value: (win.m && win.m.memTotalKB > 0) ? (win.m.ramTotalGB.toFixed(1) + " GB") : "—" }
                InfoItem { label: pluginApi?.tr("full.loadavg"); value: win.m?.loadavg || "—" }
                InfoItem { label: pluginApi?.tr("full.uptime"); value: win.m?.uptime || "—" }
                InfoItem { label: pluginApi?.tr("stats.procs"); value: (win.m?.procCount ?? 0) + (win.m?.threads ? ("  ·  " + win.m.threads + " " + pluginApi?.tr("full.threads")) : "") }
              }
            }
          }
          NBox {
            Layout.fillWidth: true; Layout.fillHeight: true
            color: win.cardBg; forceOpaque: true
            ColumnLayout {
              anchors.fill: parent; anchors.margins: Style.marginM; spacing: Style.marginS
              RowLayout {
                Layout.fillWidth: true; spacing: Style.marginS
                NIcon { icon: win.metricIcon("gpu", "device-desktop-analytics"); pointSize: Style.fontSizeM; color: Color.mPrimary }
                NText { text: pluginApi?.tr("full.gpuMon"); pointSize: Style.fontSizeM; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
              }
              Repeater { model: win.m?.gpus ?? []; delegate: GpuCard {} }
              NText { visible: !(win.m?.hasGpu ?? false); text: pluginApi?.tr("full.noGpu"); pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
              Item { Layout.fillHeight: true }
            }
          }
        }
      }

      // Footer
      RowLayout {
        Layout.fillWidth: true; spacing: Style.marginL
        NText { text: pluginApi?.tr("stats.procs") + ": "; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
        NText { text: win.m?.procCount ?? 0; pointSize: Style.fontSizeXS; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
        NText { text: pluginApi?.tr("stats.uptime") + ": "; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
        NText { text: win.m?.uptime || "—"; pointSize: Style.fontSizeXS; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
        Item { Layout.fillWidth: true }
        NIcon { icon: "network"; pointSize: Style.fontSizeS; color: Color.mTertiary }
        NText { text: "↓" + win._spd(win.m?.rxSpeed ?? 0) + " ↑" + win._spd(win.m?.txSpeed ?? 0); pointSize: Style.fontSizeXS; color: Color.mOnSurface; font.family: Settings.data.ui.fontFixed }
        NIcon { icon: "server-2"; pointSize: Style.fontSizeS; color: Color.mSecondary }
        NText { text: "↓" + win._spd(win.m?.diskRead ?? 0) + " ↑" + win._spd(win.m?.diskWrite ?? 0); pointSize: Style.fontSizeXS; color: Color.mOnSurface; font.family: Settings.data.ui.fontFixed }
        NIcon { icon: win.metricIcon("cpu", "cpu-usage"); pointSize: Style.fontSizeS; color: win._accent(win.m?.cpuUsage ?? 0, 50, 80) }
        NText { text: Math.round(win.m?.cpuUsage ?? 0) + "%"; pointSize: Style.fontSizeXS; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
        NIcon { icon: win.metricIcon("memory", "memory"); pointSize: Style.fontSizeS; color: win._accent(win.m?.memUsage ?? 0, 70, 90) }
        NText { text: win.m ? (win._human(win.m.memUsedKB) + " / " + win._human(win.m.memTotalKB)) : "—"; pointSize: Style.fontSizeXS; font.weight: Style.fontWeightBold; color: Color.mOnSurface; font.family: Settings.data.ui.fontFixed }
      }
    }

    // Right-click context menu
    MouseArea { anchors.fill: parent; visible: win.menuProc !== null; acceptedButtons: Qt.AllButtons; onPressed: win.menuProc = null; z: 50 }
    Rectangle {
      id: ctxMenu
      visible: win.menuProc !== null; z: 51
      width: 224 * Style.uiScaleRatio
      height: menuCol.implicitHeight + Style.marginS * 2
      x: Math.max(Style.marginS, Math.min(win.menuX, contentRoot.width - width - Style.marginS))
      y: Math.max(Style.marginS, Math.min(win.menuY, contentRoot.height - height - Style.marginS))
      radius: Style.radiusM; color: Qt.lighter(win.cardBg, 1.4); border.color: Color.mOutline; border.width: Style.borderS
      ColumnLayout {
        id: menuCol
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.marginS; spacing: 0
        MenuItem { icon: "hash"; label: pluginApi?.tr("ctx.copyPid");     onActivated: win.m?.copyText(win.menuProc.pid) }
        MenuItem { icon: "tag";  label: pluginApi?.tr("ctx.copyName");    onActivated: win.m?.copyText(win.menuProc.name) }
        MenuItem { icon: "code"; label: pluginApi?.tr("ctx.copyCommand"); onActivated: win.m?.copyText(win.menuProc.fullCommand || win.menuProc.name) }
        NDivider { Layout.fillWidth: true; Layout.topMargin: Style.marginXXS; Layout.bottomMargin: Style.marginXXS }
        MenuItem { icon: "x";     label: pluginApi?.tr("ctx.kill");      danger: true; onActivated: win.m?.killProcess(win.menuProc.pid, "TERM") }
        MenuItem { icon: "skull"; label: pluginApi?.tr("ctx.forceKill"); danger: true; onActivated: win.m?.killProcess(win.menuProc.pid, "KILL") }
      }
    }
  }

  // =========================== inline components ===========================

  component PerfCard: NBox {
    id: pc
    property string title: ""
    property string icon: "chart-line"
    property string bigValue: ""
    property string subText: ""
    property string topRight: ""
    property color accent: Color.mPrimary
    property color topRightColor: Color.mOnSurfaceVariant
    property var values: []
    property var values2: []
    property real maxVal: 100
    property bool autoScale: false
    Layout.fillWidth: true; Layout.fillHeight: true
    color: win.cardBg
    forceOpaque: true
    ColumnLayout {
      anchors.fill: parent; anchors.margins: Style.marginM; spacing: Style.marginXS
      RowLayout {
        Layout.fillWidth: true; spacing: Style.marginXS
        NIcon { icon: pc.icon; pointSize: Style.fontSizeM; color: pc.accent }
        NText { text: pc.title; pointSize: Style.fontSizeS; font.weight: Style.fontWeightBold; color: Color.mOnSurface }
        Item { Layout.fillWidth: true }
        NText { visible: pc.topRight !== ""; text: pc.topRight; pointSize: Style.fontSizeXS; color: pc.topRightColor; font.family: Settings.data.ui.fontFixed }
      }
      Item {
        Layout.fillWidth: true; Layout.fillHeight: true
        NGraph {
          anchors.fill: parent
          values: pc.values; values2: pc.values2
          color: pc.accent; color2: pc.autoScale ? Color.mSecondary : pc.topRightColor
          minValue: 0
          maxValue: pc.autoScale ? Math.max(1, Math.max.apply(null, [1].concat(pc.values).concat(pc.values2))) : pc.maxVal
          minValue2: 0
          maxValue2: pc.autoScale ? Math.max(1, Math.max.apply(null, [1].concat(pc.values2))) : pc.maxVal
          strokeWidth: Math.max(1, Style.uiScaleRatio); fill: true; fillOpacity: 0.15
          animateScale: pc.autoScale; updateInterval: (win.m?.refreshInterval ?? 3) * 1000
        }
        Column {
          anchors.left: parent.left; anchors.bottom: parent.bottom; spacing: 0
          NText { text: pc.bigValue; pointSize: Style.fontSizeXL; font.weight: Style.fontWeightBold; color: Color.mOnSurface; font.family: Settings.data.ui.fontFixed }
          NText { visible: pc.subText !== ""; text: pc.subText; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; elide: Text.ElideRight; width: pc.width - Style.marginM * 2 }
        }
      }
    }
  }

  component MountRow: RowLayout {
    id: mr
    required property var modelData
    Layout.fillWidth: true; spacing: Style.marginM
    NIcon { icon: mr.modelData.mount === "/" ? "home" : (mr.modelData.mount === "/home" ? "user" : "folder"); pointSize: Style.fontSizeM; color: Color.mPrimary }
    ColumnLayout {
      Layout.preferredWidth: 200 * Style.uiScaleRatio; spacing: 0
      NText { text: mr.modelData.mount; pointSize: Style.fontSizeS; color: Color.mOnSurface; elide: Text.ElideRight; Layout.fillWidth: true }
      NText { text: (mr.modelData.device || "—") + "  •  " + mr.modelData.fstype; pointSize: Style.fontSizeXXS; color: Color.mOnSurfaceVariant; elide: Text.ElideRight; Layout.fillWidth: true }
    }
    Rectangle {
      Layout.fillWidth: true; implicitHeight: 6 * Style.uiScaleRatio; radius: height / 2; color: Color.mSurfaceVariant
      Rectangle {
        height: parent.height; radius: height / 2
        width: parent.width * Math.max(0, Math.min(1, parseInt(mr.modelData.percent) / 100))
        color: parseInt(mr.modelData.percent) >= 90 ? Color.mError : (parseInt(mr.modelData.percent) >= 75 ? Color.mSecondary : Color.mPrimary)
      }
    }
    NText { text: mr.modelData.used + " / " + mr.modelData.size; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 110 * Style.uiScaleRatio }
    NText { text: mr.modelData.percent; pointSize: Style.fontSizeS; font.weight: Style.fontWeightBold; color: Color.mOnSurface; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 44 * Style.uiScaleRatio }
  }

  component InfoItem: RowLayout {
    id: ii
    property string label: ""
    property string value: ""
    Layout.fillWidth: true; spacing: Style.marginS
    NText { text: ii.label + ":"; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
    NText { Layout.fillWidth: true; text: ii.value; pointSize: Style.fontSizeXS; color: Color.mOnSurface; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
  }

  component GpuCard: NBox {
    id: gpuCard
    required property var modelData
    Layout.fillWidth: true
    implicitHeight: gcRow.implicitHeight + Style.margin2M
    color: Qt.lighter(win.cardBg, 1.35); forceOpaque: true
    RowLayout {
      id: gcRow
      anchors.fill: parent; anchors.margins: Style.marginM; spacing: Style.marginM
      NIcon { icon: win.metricIcon("gpu", "device-desktop-analytics"); pointSize: Style.fontSizeXL; color: Color.mPrimary }
      ColumnLayout {
        Layout.fillWidth: true; spacing: 0
        NText { text: gpuCard.modelData.name; pointSize: Style.fontSizeM; font.weight: Style.fontWeightBold; color: Color.mOnSurface; elide: Text.ElideRight; Layout.fillWidth: true }
        NText { text: gpuCard.modelData.vendor + (gpuCard.modelData.driver ? ("  •  " + gpuCard.modelData.driver) : ""); pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant }
        NText { visible: gpuCard.modelData.pciId !== ""; text: gpuCard.modelData.pciId; pointSize: Style.fontSizeXXS; color: Color.mOnSurfaceVariant }
      }
      Rectangle {
        visible: (gpuCard.modelData.temp || 0) > 0
        implicitWidth: gpuTempText.implicitWidth + Style.marginL
        implicitHeight: gpuTempText.implicitHeight + Style.marginXS
        radius: height / 2
        color: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.18)
        NText { id: gpuTempText; anchors.centerIn: parent; text: Math.round(gpuCard.modelData.temp) + "°C"; pointSize: Style.fontSizeS; font.weight: Style.fontWeightBold; color: Color.mSecondary }
      }
    }
  }

  component TabBtn: Rectangle {
    id: tb
    property int tabIndex: 0
    property string icon: ""
    property string label: ""
    readonly property bool active: win.currentTab === tb.tabIndex
    implicitWidth: tbRow.implicitWidth + Style.marginL * 2
    implicitHeight: Math.round(Style.baseWidgetSize * Style.uiScaleRatio)
    radius: Style.radiusM
    color: tb.active ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.15) : (tbMouse.containsMouse ? Color.mHover : "transparent")
    border.color: tb.active ? Color.mPrimary : "transparent"; border.width: Style.borderS
    RowLayout {
      id: tbRow
      anchors.centerIn: parent; spacing: Style.marginXS
      NIcon { icon: tb.icon; pointSize: Style.fontSizeM; color: tb.active ? Color.mPrimary : (tbMouse.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant) }
      NText { text: tb.label; pointSize: Style.fontSizeS; font.weight: tb.active ? Style.fontWeightBold : Style.fontWeightRegular; color: tb.active ? Color.mPrimary : (tbMouse.containsMouse ? Color.mOnHover : Color.mOnSurface) }
    }
    MouseArea { id: tbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.currentTab = tb.tabIndex }
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
    MouseArea { id: miMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { mi.activated(); win.menuProc = null } }
  }

  component Chip: Rectangle {
    id: chip
    property string scopeKey: "all"
    property string label: ""
    readonly property bool selected: win.scope === chip.scopeKey
    implicitWidth: chipText.implicitWidth + Style.marginL * 2
    implicitHeight: Math.round(Style.baseWidgetSize * 0.9 * Style.uiScaleRatio)
    radius: height / 2
    color: selected ? Color.mPrimary : Color.mSurfaceVariant
    NText { id: chipText; anchors.centerIn: parent; text: chip.label; pointSize: Style.fontSizeXS; font.weight: chip.selected ? Style.fontWeightBold : Style.fontWeightRegular; color: chip.selected ? Color.mOnPrimary : Color.mOnSurface }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.scope = chip.scopeKey }
  }

}
