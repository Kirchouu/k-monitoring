import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  // Edit copies
  property bool editShowCpu: cfg.showCpu ?? defaults.showCpu ?? false
  property bool editShowCpuTemp: cfg.showCpuTemp ?? defaults.showCpuTemp ?? false
  property bool editShowMemory: cfg.showMemory ?? defaults.showMemory ?? true
  property bool editShowGpu: cfg.showGpu ?? defaults.showGpu ?? false
  property bool editCombined: cfg.combined ?? defaults.combined ?? false
  property bool editShowIcon: cfg.showIcon ?? defaults.showIcon ?? true
  property bool editBoldText: cfg.boldText ?? defaults.boldText ?? true
  property string editIconCpu: cfg.iconCpu ?? defaults.iconCpu ?? ""
  property string editIconCpuTemp: cfg.iconCpuTemp ?? defaults.iconCpuTemp ?? ""
  property string editIconMemory: cfg.iconMemory ?? defaults.iconMemory ?? ""
  property string editIconGpu: cfg.iconGpu ?? defaults.iconGpu ?? ""
  property string pickingKey: ""
  property string editIconColor: cfg.iconColor ?? defaults.iconColor ?? "none"
  property string editTextColor: cfg.textColor ?? defaults.textColor ?? "none"
  property bool editShowFilters: cfg.showFilters ?? defaults.showFilters ?? true
  property int editRefreshInterval: cfg.refreshInterval ?? defaults.refreshInterval ?? 3
  property int editProcessLimit: cfg.processLimit ?? defaults.processLimit ?? 40
  property string editFullWindowBg: cfg.fullWindowBg ?? defaults.fullWindowBg ?? "#0f0f13"
  property string editFullCardBg: cfg.fullCardBg ?? defaults.fullCardBg ?? "#1e1e25"
  property real editFullOpacity: cfg.fullOpacity ?? defaults.fullOpacity ?? 1.0

  readonly property int metricCount: (editShowCpu ? 1 : 0) + (editShowCpuTemp ? 1 : 0) + (editShowMemory ? 1 : 0) + (editShowGpu ? 1 : 0)

  // Selected metrics, in display order (never empty).
  readonly property var selectedMetrics: {
    var a = []
    if (editShowCpu) a.push("cpu")
    if (editShowCpuTemp) a.push("cputemp")
    if (editShowMemory) a.push("memory")
    if (editShowGpu) a.push("gpu")
    return a.length ? a : ["memory"]
  }
  function defaultIconFor(key) {
    if (key === "cpu") return "cpu-usage"
    if (key === "cputemp") return "cpu-temperature"
    if (key === "gpu") return "gpu-temperature"
    return "memory"
  }
  function metricLabel(key) {
    if (key === "cpu") return pluginApi?.tr("stats.cpu")
    if (key === "cputemp") return pluginApi?.tr("stats.cputemp")
    if (key === "gpu") return pluginApi?.tr("stats.gpu")
    return pluginApi?.tr("stats.memory")
  }
  function iconOverrideFor(key) {
    if (key === "cpu") return editIconCpu
    if (key === "cputemp") return editIconCpuTemp
    if (key === "gpu") return editIconGpu
    return editIconMemory
  }
  function setIconOverride(key, name) {
    if (key === "cpu") editIconCpu = name
    else if (key === "cputemp") editIconCpuTemp = name
    else if (key === "gpu") editIconGpu = name
    else editIconMemory = name
  }
  function effIconFor(key) {
    var o = iconOverrideFor(key)
    return o !== "" ? o : defaultIconFor(key)
  }

  spacing: Style.marginM

  // ===================== Metrics =====================
  NText {
    text: pluginApi?.tr("settings.metricsTitle")
    pointSize: Style.fontSizeM
    font.weight: Style.fontWeightBold
    color: Color.mOnSurface
  }
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.showCpu")
    description: pluginApi?.tr("settings.showCpuDesc")
    checked: root.editShowCpu
    onToggled: checked => root.editShowCpu = checked
  }
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.showCpuTemp")
    description: pluginApi?.tr("settings.showCpuTempDesc")
    checked: root.editShowCpuTemp
    onToggled: checked => root.editShowCpuTemp = checked
  }
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.showMemory")
    description: pluginApi?.tr("settings.showMemoryDesc")
    checked: root.editShowMemory
    onToggled: checked => root.editShowMemory = checked
  }
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.showGpu")
    description: pluginApi?.tr("settings.showGpuDesc")
    checked: root.editShowGpu
    onToggled: checked => root.editShowGpu = checked
  }
  NToggle {
    Layout.fillWidth: true
    visible: root.metricCount >= 2
    label: pluginApi?.tr("settings.combined")
    description: pluginApi?.tr("settings.combinedDesc")
    checked: root.editCombined
    onToggled: checked => root.editCombined = checked
  }

  NDivider { Layout.fillWidth: true }

  // ===================== Appearance =====================
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.showIcon")
    description: pluginApi?.tr("settings.showIconDesc")
    checked: root.editShowIcon
    onToggled: checked => root.editShowIcon = checked
  }
  // Per-metric icon: one row per selected metric, each with its current icon.
  ColumnLayout {
    Layout.fillWidth: true
    visible: root.editShowIcon
    spacing: Style.marginXS

    NText {
      text: pluginApi?.tr("settings.iconsTitle")
      pointSize: Style.fontSizeM
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
    }

    Repeater {
      model: root.selectedMetrics
      delegate: RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NIcon {
          icon: root.effIconFor(modelData)
          pointSize: Style.fontSizeL
          color: Color.mPrimary
        }
        NText {
          Layout.fillWidth: true
          text: root.metricLabel(modelData)
          pointSize: Style.fontSizeM
          color: Color.mOnSurface
        }
        NText {
          text: root.iconOverrideFor(modelData) !== "" ? root.iconOverrideFor(modelData) : pluginApi?.tr("settings.defaultIcon")
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
        NButton {
          text: pluginApi?.tr("settings.change")
          onClicked: {
            root.pickingKey = modelData
            iconPicker.initialIcon = root.effIconFor(modelData)
            iconPicker.open()
          }
        }
        NIconButton {
          icon: "x"
          baseSize: Style.baseWidgetSize * 0.7
          visible: root.iconOverrideFor(modelData) !== ""
          tooltipText: pluginApi?.tr("settings.resetIcon")
          onClicked: root.setIconOverride(modelData, "")
        }
      }
    }
  }
  NColorChoice {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.iconColor")
    currentKey: root.editIconColor
    defaultValue: root.defaults.iconColor
    onSelected: key => root.editIconColor = key
  }
  NColorChoice {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.textColor")
    currentKey: root.editTextColor
    defaultValue: root.defaults.textColor
    onSelected: key => root.editTextColor = key
  }
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.boldText")
    description: pluginApi?.tr("settings.boldTextDesc")
    checked: root.editBoldText
    onToggled: checked => root.editBoldText = checked
  }

  NDivider { Layout.fillWidth: true }

  // ===================== Panel =====================
  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.showFilters")
    description: pluginApi?.tr("settings.showFiltersDesc")
    checked: root.editShowFilters
    onToggled: checked => root.editShowFilters = checked
  }
  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.refreshInterval")
    description: pluginApi?.tr("settings.refreshIntervalDesc")
    model: [
      { key: "1",  name: "1 s" },
      { key: "2",  name: "2 s" },
      { key: "3",  name: "3 s" },
      { key: "5",  name: "5 s" },
      { key: "10", name: "10 s" }
    ]
    currentKey: String(root.editRefreshInterval)
    onSelected: key => root.editRefreshInterval = parseInt(key)
  }
  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.processLimit")
    description: pluginApi?.tr("settings.processLimitDesc")
    model: [
      { key: "20",  name: "20" },
      { key: "40",  name: "40" },
      { key: "60",  name: "60" },
      { key: "100", name: "100" }
    ]
    currentKey: String(root.editProcessLimit)
    onSelected: key => root.editProcessLimit = parseInt(key)
  }

  NDivider { Layout.fillWidth: true }

  // ===================== Full-screen window appearance =====================
  NText {
    text: pluginApi?.tr("settings.fullTitle")
    pointSize: Style.fontSizeM; font.weight: Style.fontWeightBold; color: Color.mOnSurface
  }
  RowLayout {
    Layout.fillWidth: true; spacing: Style.marginM
    NTextInput {
      Layout.fillWidth: true
      label: pluginApi?.tr("settings.windowBg"); description: ""
      placeholderText: "#0f0f13"; text: root.editFullWindowBg
      onTextChanged: root.editFullWindowBg = text
    }
    Rectangle { Layout.alignment: Qt.AlignVCenter; Layout.preferredWidth: Style.baseWidgetSize; Layout.preferredHeight: Style.baseWidgetSize; radius: Style.radiusS; color: root.editFullWindowBg; border.color: Color.mOutline; border.width: Style.borderS }
  }
  RowLayout {
    Layout.fillWidth: true; spacing: Style.marginM
    NTextInput {
      Layout.fillWidth: true
      label: pluginApi?.tr("settings.cardBg"); description: ""
      placeholderText: "#1e1e25"; text: root.editFullCardBg
      onTextChanged: root.editFullCardBg = text
    }
    Rectangle { Layout.alignment: Qt.AlignVCenter; Layout.preferredWidth: Style.baseWidgetSize; Layout.preferredHeight: Style.baseWidgetSize; radius: Style.radiusS; color: root.editFullCardBg; border.color: Color.mOutline; border.width: Style.borderS }
  }
  NValueSlider {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.opacity"); description: pluginApi?.tr("settings.opacityDesc")
    from: 0.4; to: 1.0; stepSize: 0.01
    value: root.editFullOpacity
    onMoved: value => root.editFullOpacity = value
    text: Math.round(root.editFullOpacity * 100) + "%"
  }

  // Full icon browser, shared by all per-metric rows (pickingKey selects target).
  NIconPicker {
    id: iconPicker
    onIconSelected: iconName => root.setIconOverride(root.pickingKey, iconName)
  }

  // Required — called by the shell when the user saves.
  function saveSettings() {
    if (!pluginApi) return
    pluginApi.pluginSettings.showCpu = root.editShowCpu
    pluginApi.pluginSettings.showCpuTemp = root.editShowCpuTemp
    pluginApi.pluginSettings.showMemory = root.editShowMemory
    pluginApi.pluginSettings.showGpu = root.editShowGpu
    pluginApi.pluginSettings.combined = root.editCombined
    pluginApi.pluginSettings.showIcon = root.editShowIcon
    pluginApi.pluginSettings.boldText = root.editBoldText
    pluginApi.pluginSettings.iconCpu = root.editIconCpu
    pluginApi.pluginSettings.iconCpuTemp = root.editIconCpuTemp
    pluginApi.pluginSettings.iconMemory = root.editIconMemory
    pluginApi.pluginSettings.iconGpu = root.editIconGpu
    pluginApi.pluginSettings.iconColor = root.editIconColor
    pluginApi.pluginSettings.textColor = root.editTextColor
    pluginApi.pluginSettings.showFilters = root.editShowFilters
    pluginApi.pluginSettings.refreshInterval = root.editRefreshInterval
    pluginApi.pluginSettings.processLimit = root.editProcessLimit
    pluginApi.pluginSettings.fullWindowBg = root.editFullWindowBg
    pluginApi.pluginSettings.fullCardBg = root.editFullCardBg
    pluginApi.pluginSettings.fullOpacity = root.editFullOpacity
    pluginApi.saveSettings()
  }
}
