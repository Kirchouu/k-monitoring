# K Monitoring (Noctalia plugin)

Bar widget showing **CPU** / **memory** usage or **GPU temperature**. Click it to
open a panel with CPU/Memory/GPU gauges and a live process list sorted by the
metric — same idea as the DankMaterialShell CPU/Memory widgets, rebuilt natively
for Noctalia.

## Features

- **Bar widget**: `metric` = `memory` / `cpu` (percentage) or `gpu` (temperature),
  color-coded (normal / warning / critical).
- **Left click**: opens the panel, process list sorted by this widget's metric.
- **Right click**: context menu (refresh / settings).
- **Middle click**: force refresh.
- **Panel**: CPU + Memory + GPU circular gauges (with CPU/GPU temps), host /
  uptime / proc-count header, sortable process list (CPU / Memory chips),
  per-row kill button.
- **Multiple widgets**: add the plugin several times in the bar — set one to
  Memory, one to CPU, one to GPU. They share one data source and one panel; the
  panel sorts by whichever widget you clicked.

## Data source

**Primary: `dgop`** (https://github.com/AvengeMedia/dgop) — the same monitoring
backend DankMaterialShell uses. Gives CPU/GPU temperatures, CPU frequency,
per-core usage, and accurate per-process CPU% (via dgop cursors). The plugin
runs `dgop meta --json --modules cpu,memory,processes,system,gpu-temp ...` every
`refreshInterval` seconds, plus one-shot `dgop gpu --json` / `dgop hardware --json`
at startup for the GPU list and host info.

**Fallback (no dgop): `/proc` + `ps`** — a single `sh` pass reads `/proc/stat`
(CPU delta), `/proc/meminfo`, `uname -n`, `ps -eo pid,pcpu,pmem,rss,comm`. No
temperatures or GPU in this mode.

Install dgop for the full experience (AUR: `dgop`). GPU temp on NVIDIA needs
`nvidia-smi`. Kill uses `kill <pid>`.

## Install

The plugin is just a folder. Drop it straight into Noctalia's plugin dir — the
folder name **must** match `manifest.id` (`k-monitoring`):

```sh
mkdir -p ~/.config/noctalia/plugins
# either copy the folder…
cp -r k-monitoring ~/.config/noctalia/plugins/k-monitoring
# …or, to keep editing it from elsewhere (e.g. a Documents/ checkout),
# symlink that working copy back to the plugin dir:
#   ln -s ~/Documents/noctalia-sysmon/k-monitoring ~/.config/noctalia/plugins/k-monitoring
```

Noctalia auto-discovers any folder in `~/.config/noctalia/plugins/` that has a
`manifest.json` (a file watcher rescans on change — no restart needed). Then:

- **Settings → Plugins** → enable **K Monitoring**.
- **Settings → Bar** → add the widget to a section.

Add it a second time and switch its `Metric` to CPU (or GPU) — all instances
share one data source and one panel.

> Enabling writes a `states` entry into `~/.config/noctalia/plugins.json`
> (alongside `sources`/`version`). Prefer the UI toggle over editing that file
> by hand, since the running shell owns it.

## Full-screen monitor (optional keybind)

Clicking the bar widget opens the **compact** panel (attached to the bar). The
plugin also exposes a **full-screen "System Monitor"** as a real, movable &
resizable window (tabs: Processes / Performance / Disks / System), opened via an
IPC call you bind to a key. On niri:

```kdl
// in your binds { } block
Mod+M hotkey-overlay-title="System Monitor" { spawn "qs" "-c" "noctalia-shell" "ipc" "call" "plugin:k-monitoring" "toggleFull"; }

// optional: float + size the window (it sets its title to "K-Monitoring")
window-rule {
    match title="^K-Monitoring$"
    open-floating true
}
```

Other compositors: bind any key to `qs -c noctalia-shell ipc call plugin:k-monitoring toggleFull`.

## Dev / hot reload

Launch with `NOCTALIA_DEBUG=1 qs -c noctalia-shell` — saving a file reloads the
plugin without restarting the shell.

> When publishing / copying to another machine, ship the QML + `manifest.json` +
> `i18n/` (and this README). The `settings.json` that may appear in the folder is
> per-machine saved state — don't commit it.

## Settings

| Key | Default | Meaning |
|-----|---------|---------|
| `metric` | `memory` | `memory` / `cpu` (%) or `gpu` (temp °C) — what this instance shows |
| `refreshInterval` | `3` | seconds between samples |
| `processLimit` | `40` | max rows in the process list |
| `showIcon` | `true` | icon before the percentage |
| `boldText` | `true` | bold percentage |

## Notes / things to tweak after first run

- Icon names (`cpu`, `memory`, `thermometer`, `x`, `refresh`, `settings`) come
  from Noctalia's Tabler icon set. If one renders blank, swap it for a name that
  exists in your build.
- Color tokens used: `mPrimary`, `mSecondary`, `mError`, `mOnPrimary`,
  `mSurfaceVariant`, `mOnSurface(Variant)`, `mHover`, `mOnHover`. All standard
  Material tokens; adjust if your theme lacks one.
