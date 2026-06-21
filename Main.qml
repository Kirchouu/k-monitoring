import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Shared state + data collection. One instance per plugin, consumed by every
// BarWidget instance and by the Panel via pluginApi.mainInstance.
//
// Primary backend: dgop (https://github.com/AvengeMedia/dgop) — same tool DMS
// uses. Gives CPU/GPU temps, per-core, accurate per-process CPU via cursors.
// Fallback: direct /proc + ps when dgop is not installed.
Item {
  id: root
  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property int refreshInterval: cfg.refreshInterval ?? defaults.refreshInterval ?? 3
  readonly property int processLimit: cfg.processLimit ?? defaults.processLimit ?? 40

  // ---- Capabilities ----
  property bool dgopAvailable: false
  property bool hasData: false

  // ---- CPU ----
  property real cpuUsage: 0       // 0..100
  property real cpuTemp: 0        // °C (0 if unknown)
  property real cpuFreq: 0        // MHz
  property string cpuModel: ""
  property int  cpuCores: 0
  property var  coreUsage: []     // [%, ...]

  // ---- Memory ----
  property real memUsage: 0       // 0..100
  property int  memTotalKB: 0
  property int  memUsedKB: 0
  property int  swapTotalKB: 0
  property int  swapUsedKB: 0

  // ---- GPU ----
  property var  gpus: []          // [{name, vendor, temp, pciId}]
  property string _gpuPciIds: ""
  readonly property bool hasGpu: gpus.length > 0
  readonly property real gpuTemp: gpus.length > 0 ? (gpus[0].temp || 0) : 0
  readonly property string gpuName: gpus.length > 0 ? (gpus[0].name || "GPU") : ""

  // ---- Host ----
  property string hostname: ""
  property string kernel: ""
  property string distro: ""
  property string arch: ""
  property string loadavg: ""     // "1.0 2.0 3.0"
  property string uptime: ""
  property int  procCount: 0
  property int  threads: 0
  readonly property string currentUser: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
  readonly property real ramTotalGB: memTotalKB / 1048576

  // ---- Network / Disk rates (bytes/s) ----
  property real rxSpeed: 0
  property real txSpeed: 0
  property real diskRead: 0
  property real diskWrite: 0
  property var  mounts: []        // [{device, mount, fstype, size, used, avail, percent}]

  // ---- Rolling history (newest pushed last) ----
  property var cpuHistory: []
  property var cpuTempHistory: []
  property var memHistory: []
  property var netRxHistory: []
  property var netTxHistory: []
  property var diskRHistory: []
  property var diskWHistory: []
  readonly property int historyLen: 60

  // ---- Full-screen monitor window (real movable/resizable window, opened via Mod+M) ----
  property var _fullWin: null
  function _ensureFullWindow() {
    if (root._fullWin) return root._fullWin
    var c = Qt.createComponent(Qt.resolvedUrl("FullWindow.qml"))
    if (c.status === Component.Ready) {
      root._fullWin = c.createObject(root, { "pluginApi": root.pluginApi })
    } else if (c.status === Component.Error) {
      console.warn("K-Monitoring FullWindow:", c.errorString())
    }
    return root._fullWin
  }

  // ---- Processes ----
  property var processes: []      // [{pid, name, fullCommand, cpu, mem, rss, username}]

  // Column the Panel sorts by; set by a BarWidget right before opening.
  property string panelSortMode: "memory"  // "memory" | "cpu"

  // ---- internals ----
  property string _cpuCursor: ""
  property string _procCursor: ""
  property string _netCursor: ""
  property string _diskCursor: ""
  property var _prevCpu: null      // fallback /proc cpu delta state
  property bool _busy: false

  function _pushHistory(arr, v) {
    var a = arr.slice()
    a.push(v)
    if (a.length > root.historyLen) a = a.slice(a.length - root.historyLen)
    return a
  }
  function formatSpeed(bps) {
    bps = bps || 0
    if (bps < 1024) return Math.round(bps) + " B/s"
    var k = bps / 1024
    if (k < 1024) return (k >= 100 ? k.toFixed(0) : k.toFixed(1)) + " KB/s"
    var mb = k / 1024
    if (mb < 1024) return (mb >= 100 ? mb.toFixed(0) : mb.toFixed(1)) + " MB/s"
    return (mb / 1024).toFixed(1) + " GB/s"
  }
  // Whole physical disks only (exclude partitions) to avoid double-counting rates.
  function _isWholeDisk(name) {
    return /^nvme\d+n\d+$/.test(name) || /^sd[a-z]+$/.test(name) || /^mmcblk\d+$/.test(name) || /^vd[a-z]+$/.test(name) || /^zram\d+$/.test(name)
  }

  function _humanKB(kb) {
    if (kb < 1024) return kb + " KB"
    var mb = kb / 1024
    if (mb < 1024) return (mb >= 100 ? mb.toFixed(0) : mb.toFixed(1)) + " MB"
    var gb = mb / 1024
    return (gb >= 10 ? gb.toFixed(1) : gb.toFixed(2)) + " GB"
  }

  function _fmtUptime(sec) {
    sec = Math.floor(sec)
    var d = Math.floor(sec / 86400); sec -= d * 86400
    var h = Math.floor(sec / 3600);  sec -= h * 3600
    var m = Math.floor(sec / 60)
    var out = ""
    if (d > 0) out += d + "d "
    if (h > 0) out += h + "h "
    out += m + "m"
    return out.trim()
  }

  Component.onCompleted: checkProc.running = true

  // ---- detect dgop ----
  Process {
    id: checkProc
    command: ["which", "dgop"]
    running: false
    onExited: code => {
      root.dgopAvailable = (code === 0)
      if (root.dgopAvailable) {
        gpuInit.running = true     // one-shot GPU list + pci ids
        hwInit.running = true      // one-shot hostname/kernel/distro
      }
      root.refresh()
    }
  }

  Timer {
    interval: root.refreshInterval * 1000
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  function refresh() {
    uptimeProc.running = true       // /proc/uptime works in both modes
    if (root._busy) return
    root._busy = true
    if (root.dgopAvailable) {
      metaProc.command = root._buildMeta()
      metaProc.running = true
    } else {
      fallbackProc.running = true
    }
  }

  // =================== dgop init (one-shot) ===================

  Process {
    id: gpuInit
    command: ["dgop", "gpu", "--json"]
    running: false
    stdout: StdioCollector { onStreamFinished: root._parseGpuList(this.text) }
  }
  function _parseGpuList(t) {
    try {
      var d = JSON.parse((t || "").trim())
      var arr = d.gpus || (d.gpu && d.gpu.gpus) || []
      var ids = [], list = []
      for (var i = 0; i < arr.length; i++) {
        var g = arr[i]
        list.push({ name: g.displayName || g.name || "GPU", vendor: g.vendor || "", driver: g.driver || "", temp: g.temperature || 0, pciId: g.pciId || "" })
        if (g.pciId) ids.push(g.pciId)
      }
      root.gpus = list
      root._gpuPciIds = ids.join(",")
    } catch (e) {}
  }

  Process {
    id: hwInit
    command: ["dgop", "hardware", "--json"]
    running: false
    stdout: StdioCollector { onStreamFinished: root._parseHw(this.text) }
  }
  function _parseHw(t) {
    try {
      var d = JSON.parse((t || "").trim())
      root.hostname = d.hostname || root.hostname
      root.kernel = d.kernel || ""
      root.distro = d.distro || ""
      root.arch = d.arch || ""
      if (d.cpu && d.cpu.model) root.cpuModel = d.cpu.model
    } catch (e) {}
  }

  // =================== uptime (both modes) ===================

  Process {
    id: uptimeProc
    command: ["cat", "/proc/uptime"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var s = parseFloat(((this.text || "").trim().split(/\s+/))[0])
        if (!isNaN(s)) root.uptime = root._fmtUptime(s)
      }
    }
  }

  // =================== dgop meta (primary) ===================

  Process {
    id: metaProc
    running: false
    onExited: root._busy = false
    stdout: StdioCollector { onStreamFinished: root._parseMeta(this.text) }
  }

  function _buildMeta() {
    var mods = ["cpu", "memory", "processes", "system", "diskmounts", "disk-rate", "net-rate"]
    if (root._gpuPciIds) mods.push("gpu-temp")
    var c = ["dgop", "meta", "--json", "--modules", mods.join(","), "--limit", "100", "--sort", "cpu"]
    if (root._gpuPciIds) { c.push("--gpu-pci-ids", root._gpuPciIds) }
    if (root._cpuCursor) { c.push("--cpu-cursor", root._cpuCursor) }
    if (root._procCursor) { c.push("--proc-cursor", root._procCursor) }
    if (root._netCursor) { c.push("--net-rate-cursor", root._netCursor) }
    if (root._diskCursor) { c.push("--disk-rate-cursor", root._diskCursor) }
    return c
  }

  function _parseMeta(t) {
    try {
      var d = JSON.parse((t || "").trim())

      if (d.cpu) {
        var c = d.cpu
        root.cpuUsage = Math.round((c.usage || 0) * 10) / 10
        root.cpuTemp = Math.round(c.temperature || 0)
        root.cpuFreq = Math.round(c.frequency || 0)
        root.cpuCores = c.count || root.cpuCores
        root.cpuModel = c.model || root.cpuModel
        root.coreUsage = c.coreUsage || []
        if (c.cursor) root._cpuCursor = c.cursor
      }

      if (d.memory) {
        var m = d.memory
        root.memTotalKB = m.total || 0
        root.memUsedKB = (m.used !== undefined) ? m.used : ((m.total || 0) - (m.available || 0))
        root.memUsage = Math.round(((m.usedPercent !== undefined)
                          ? m.usedPercent
                          : (m.total > 0 ? 100 * (m.total - m.available) / m.total : 0)) * 10) / 10
        root.swapTotalKB = m.swaptotal || 0
        root.swapUsedKB = (m.swaptotal || 0) - (m.swapfree || 0)
      }

      if (d.system) {
        if (d.system.processes) root.procCount = d.system.processes
        root.loadavg = d.system.loadavg || root.loadavg
        root.threads = d.system.threads || root.threads
      }

      // gpu-temp module returns d.gpu.gpus with updated temps; merge by pciId
      if (d.gpu && d.gpu.gpus) {
        var list = root.gpus.slice()
        for (var i = 0; i < list.length; i++) {
          for (var j = 0; j < d.gpu.gpus.length; j++) {
            if (d.gpu.gpus[j].pciId === list[i].pciId) {
              list[i] = { name: list[i].name, vendor: list[i].vendor, driver: list[i].driver, pciId: list[i].pciId, temp: d.gpu.gpus[j].temperature || 0 }
            }
          }
        }
        root.gpus = list
      }

      // network rate (sum interfaces)
      if (d.netrate) {
        var rx = 0, tx = 0
        var ifs = d.netrate.interfaces || []
        for (var ni = 0; ni < ifs.length; ni++) { rx += ifs[ni].rxrate || 0; tx += ifs[ni].txrate || 0 }
        root.rxSpeed = rx
        root.txSpeed = tx
        if (d.netrate.cursor) root._netCursor = d.netrate.cursor
      }

      // disk rate (sum whole disks only)
      if (d.diskrate) {
        var dr = 0, dw = 0
        var disks = d.diskrate.disks || []
        for (var di = 0; di < disks.length; di++) {
          if (root._isWholeDisk(disks[di].device)) { dr += disks[di].readrate || 0; dw += disks[di].writerate || 0 }
        }
        root.diskRead = dr
        root.diskWrite = dw
        if (d.diskrate.cursor) root._diskCursor = d.diskrate.cursor
      }

      // mount points
      if (d.diskmounts && d.diskmounts.length !== undefined) {
        var ms = []
        for (var mi = 0; mi < d.diskmounts.length; mi++) {
          var mm = d.diskmounts[mi]
          ms.push({ device: mm.device || "", mount: mm.mount || "", fstype: mm.fstype || "",
                    size: mm.size || "", used: mm.used || "", avail: mm.avail || "", percent: mm.percent || "0%" })
        }
        root.mounts = ms
      }

      if (d.processes && d.processes.length !== undefined) {
        var ps = []
        for (var k = 0; k < d.processes.length; k++) {
          var p = d.processes[k]
          ps.push({
            pid: p.pid || 0,
            ppid: p.ppid || 0,
            name: p.command || "",
            fullCommand: p.fullCommand || "",
            cpu: p.cpu || 0,
            mem: p.memoryPercent || p.rssPercent || 0,
            rss: p.memoryKB || p.rssKB || 0,
            username: p.username || ""
          })
        }
        root.processes = ps
        if (!(d.system && d.system.processes)) root.procCount = ps.length
        if (d.cursor) root._procCursor = d.cursor
      }

      root.cpuHistory = _pushHistory(root.cpuHistory, root.cpuUsage)
      root.cpuTempHistory = _pushHistory(root.cpuTempHistory, root.cpuTemp)
      root.memHistory = _pushHistory(root.memHistory, root.memUsage)
      root.netRxHistory = _pushHistory(root.netRxHistory, root.rxSpeed)
      root.netTxHistory = _pushHistory(root.netTxHistory, root.txSpeed)
      root.diskRHistory = _pushHistory(root.diskRHistory, root.diskRead)
      root.diskWHistory = _pushHistory(root.diskWHistory, root.diskWrite)

      root.hasData = true
    } catch (e) {}
  }

  // =================== fallback: /proc + ps ===================

  Process {
    id: fallbackProc
    running: false
    onExited: root._busy = false
    command: ["sh", "-c",
      "echo '@@CPU'; head -n1 /proc/stat; " +
      "echo '@@MEM'; cat /proc/meminfo; " +
      "echo '@@HOST'; uname -n; " +
      "echo '@@PS'; ps -eo pid,ppid,pcpu,pmem,rss,user:32,comm --no-headers"]
    stdout: StdioCollector { onStreamFinished: root._parseFallback(this.text) }
  }

  function _parseFallback(text) {
    var section = ""
    var lines = (text || "").split("\n")
    var memTotal = 0, memAvail = 0, swapTotal = 0, swapFree = 0
    var procs = []

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.indexOf("@@") === 0) { section = line.substring(2); continue }
      if (!line.trim()) continue

      if (section === "CPU") {
        var p = line.trim().split(/\s+/)
        var nums = []
        for (var j = 1; j < p.length; j++) { var n = parseInt(p[j]); if (!isNaN(n)) nums.push(n) }
        var idle = (nums[3] || 0) + (nums[4] || 0)
        var total = 0; for (var q = 0; q < nums.length; q++) total += nums[q]
        if (root._prevCpu) {
          var dt = total - root._prevCpu.total
          var di = idle - root._prevCpu.idle
          if (dt > 0) root.cpuUsage = Math.max(0, Math.min(100, 100 * (dt - di) / dt))
        }
        root._prevCpu = { total: total, idle: idle }

      } else if (section === "MEM") {
        if (line.indexOf("MemTotal:") === 0)          memTotal  = parseInt(line.replace(/[^\d]/g, ""))
        else if (line.indexOf("MemAvailable:") === 0) memAvail  = parseInt(line.replace(/[^\d]/g, ""))
        else if (line.indexOf("SwapTotal:") === 0)    swapTotal = parseInt(line.replace(/[^\d]/g, ""))
        else if (line.indexOf("SwapFree:") === 0)     swapFree  = parseInt(line.replace(/[^\d]/g, ""))

      } else if (section === "HOST") {
        root.hostname = line.trim()

      } else if (section === "PS") {
        var cols = line.trim().split(/\s+/)
        if (cols.length >= 7) {
          var pid = parseInt(cols[0])
          if (!isNaN(pid)) procs.push({
            pid: pid, ppid: parseInt(cols[1]), cpu: parseFloat(cols[2]), mem: parseFloat(cols[3]),
            rss: parseInt(cols[4]), username: cols[5], name: cols.slice(6).join(" "), fullCommand: ""
          })
        }
      }
    }

    if (memTotal > 0) {
      root.memTotalKB = memTotal
      root.memUsedKB = memTotal - memAvail
      root.memUsage = 100 * (memTotal - memAvail) / memTotal
    }
    root.swapTotalKB = swapTotal
    root.swapUsedKB = swapTotal - swapFree
    root.procCount = procs.length
    root.processes = procs
    root.hasData = true
  }

  // =================== helpers ===================

  // Sorted copy of the process list (no re-fetch).
  function sortedProcesses(mode, limit) {
    return filteredProcesses(mode, "all", "", limit)
  }

  // Filter (scope: "all" | "user" | "system") + search + sort, no re-fetch.
  function filteredProcesses(mode, scope, query, limit) {
    var arr = processes.slice()
    if (scope === "user")        arr = arr.filter(function (p) { return p.username === currentUser })
    else if (scope === "system") arr = arr.filter(function (p) { return p.username !== currentUser })
    if (query && query.length > 0) {
      var q = query.toLowerCase()
      arr = arr.filter(function (p) {
        return (p.name || "").toLowerCase().indexOf(q) !== -1 || String(p.pid).indexOf(q) !== -1
      })
    }
    if (mode === "cpu") arr.sort(function (a, b) { return b.cpu - a.cpu })
    else                arr.sort(function (a, b) { return b.rss - a.rss })
    if (limit && limit > 0) arr = arr.slice(0, limit)
    return arr
  }

  // signal: "TERM" (default, graceful) or "KILL" (force / SIGKILL)
  function killProcess(pid, signal) {
    killProc.command = ["kill", "-" + (signal || "TERM"), String(pid)]
    killProc.running = true
  }
  Process {
    id: killProc
    running: false
    onExited: Qt.callLater(root.refresh)
  }

  // Copy text to the Wayland clipboard (needs wl-clipboard / wl-copy installed).
  function copyText(text) {
    copyProc.command = ["wl-copy", "--", String(text)]
    copyProc.running = true
  }
  Process {
    id: copyProc
    running: false
  }

  // IPC: toggle the full-screen monitor window (bound to Mod+M in niri).
  IpcHandler {
    target: "plugin:k-monitoring"
    function toggleFull(): void {
      var w = root._ensureFullWindow()
      if (w) w.visible = !w.visible
    }
    function refresh(): void { root.refresh() }
  }
}
