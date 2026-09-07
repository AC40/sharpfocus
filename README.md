# Sharp Focus

Only the window you're working in stays in color.

Sharp Focus is a macOS menu bar app. It desaturates, blurs and dims everything
on screen except the window you're currently working in. The rest of your
desktop is still there — still readable if you look at it — it just stops
competing for attention. No screen recording permission, no accessibility
permission, no network access.

![Sharp Focus demo](docs/demo.gif)

<!-- TODO: record docs/demo.gif — switching windows with grayscale + blur on, then a preset switch. -->

Requires macOS 14 or later.

## Install

Download the latest `SharpFocus.app` from
[Releases](https://github.com/ac40/sharpfocus/releases) and move it to
`/Applications`.

The app is ad-hoc signed and **not notarized**, because notarization requires a
paid Apple Developer account. macOS will refuse the first launch. On Sequoia the
old right-click → Open trick no longer works, so you have two options:

1. Double-click the app, let macOS block it, then open **System Settings →
   Privacy & Security** and click **Open Anyway** next to the warning.
2. Or strip the quarantine attribute yourself:

   ```sh
   xattr -cr /Applications/SharpFocus.app
   ```

There is no Homebrew cask yet. The main tap requires notarized apps.

### Build from source

```sh
cd app
swift build                  # debug binary at .build/debug/SharpFocus
./Scripts/bundle.sh          # release build -> build/SharpFocus.app
open build/SharpFocus.app
```

`bundle.sh` builds in release mode, renders the icon, writes `Info.plist` and
ad-hoc signs the bundle. Set `SHARPFOCUS_VERSION` to override the version
string.

Running the bare `swift build` binary works for development, but launch at
login needs a real `.app` bundle.

## Using it

The menu bar icon is a half-filled circle; it dims when the effect is off.

| Item | What it does |
| --- | --- |
| Enable Sharp Focus | Master switch. Also `⌃⌥⌘F` from anywhere (change it in Settings → General). |
| Snooze | Turn off for 15, 30, 60 or 120 minutes, then turn back on by itself. |
| Presets | Apply a saved preset, save the current settings as a new one, or open the preset editor. |
| Pin Focused Window | `⌃⌥⌘P` (change it in Settings → General). Keeps that window in color even when it isn't focused. |
| Clear Pinned Windows | Appears once something is pinned. |
| Settings… | Opens the settings window. |

The effect itself lives in **Settings → Effect**:

- **Grayscale**, 0–100%. Default 100%.
- **Blur**, 0–40 px. Default 0.
- **Dimming**, 0–90%. Default 20%.

All three stack. Turning all three to zero leaves the overlay in place doing
nothing.

**Keep in color** picks what counts as "in focus":

- *All windows of active app* (default) — every window of the frontmost app.
- *Focused window only* — just the frontmost window of the frontmost app.

**Focused window stays grayscale** (Settings → Effect → Keep in color, off by
default) splits the effect in two: blur and dimming still lift for whatever is
focused, but grayscale lifts only for pinned windows and **Always in color**
apps. The window you're working in is sharp and undimmed, just desaturated —
only your pinned and always-colored windows are ever in full color.

**Always in color** (Settings → Effect) is a list of apps whose windows never get filtered.
A music player or a chat window you want to keep an eye on. It's matched by
bundle identifier, so it survives restarts.

**Pinned windows** are matched by window ID instead, which means they are
session-only. Quit the app or the pinned app and the pin is gone.

Settings are stored in `UserDefaults`, under `de.beyond925.SharpFocus`.

### Presets

Three are seeded on first launch:

| Preset | Grayscale | Blur | Dimming | Keep in color |
| --- | --- | --- | --- | --- |
| Deep Work | 100% | 12 px | 30% | Focused window only |
| Soft Focus | 70% | 0 | 15% | All windows of active app |
| Monochrome | 100% | 0 | 10% | All windows of active app |

Edit, rename or delete them in **Settings → Presets**. The `+` button there and
"Save Current as Preset…" in the menu both capture your current sliders as a
new preset. A preset is shown as active only
while the live settings still match it — move a slider and the checkmark goes
away.

### Launch at login

**Settings → General → Launch at login**, backed by `SMAppService`. macOS may
ask you to approve the login item in System Settings; the toggle links straight
there. Only available when running from `SharpFocus.app`.

## Automation

**Settings → Automation** holds a list of "when X, do Y" rules. Two kinds of
trigger:

- **Time of day** — a start time, an end time and a set of weekdays. Overnight
  ranges (22:00–06:00) work.
- **macOS Focus mode** — matched by name, e.g. `Work` or `Do Not Disturb`.

Each rule either applies a preset (enabling Sharp Focus if it was off) or turns
Sharp Focus off.

Rules are evaluated every 30 seconds and whenever the Focus mode changes. If
several rules match, Focus-mode rules beat time rules, and the last matching
rule in the list wins. When the first rule fires, the app snapshots your manual
settings; when no rule matches anymore, that snapshot is restored. Automation
never permanently overwrites what you set by hand.

### Full Disk Access for Focus-mode rules

macOS has no public API that tells you which Focus mode is active. Sharp Focus
reads `~/Library/DoNotDisturb/DB`, the same files every other tool uses, which
macOS 14 puts behind **Full Disk Access**.

This is opt-in. Time rules work without it. If you want Focus-mode rules, the
Automation tab has a **Grant…** button that opens the right settings pane; add
Sharp Focus there and restart it. Without access the app reports "no Focus
mode" and Focus-mode rules never match.

## Scripting and integrations

Two control surfaces, same vocabulary.

### sfctl

`sfctl` ships inside the bundle at
`/Applications/SharpFocus.app/Contents/MacOS/sfctl`. Symlink it onto your
`PATH`:

```sh
ln -s /Applications/SharpFocus.app/Contents/MacOS/sfctl /usr/local/bin/sfctl
```

```
sfctl enabled 1|0                  master switch
sfctl toggle                       flip the master switch
sfctl grayscale 0..1               desaturation amount
sfctl blur 0..40                   blur radius in points
sfctl dim 0..0.9                   dimming amount
sfctl mode focusedWindow|frontApp  what stays in color
sfctl focused-gray 1|0             keep the focused window grayscale
sfctl preset "Deep Work"           apply a preset (and enable)
sfctl snooze 30                    turn off for N minutes
sfctl mc-pause 1|0                 pause in Mission Control
sfctl settings                     open the settings window
```

It talks to the running app over a distributed notification and exits
immediately. If Sharp Focus isn't running, nothing happens and there is no
error.

### URL scheme

`sharpfocus://` works from anything that can open a URL — Shortcuts, Alfred,
Keyboard Maestro, a browser bar, `open(1)`.

| URL | Effect |
| --- | --- |
| `sharpfocus://enable` | Turn on |
| `sharpfocus://disable` | Turn off |
| `sharpfocus://toggle` | Flip |
| `sharpfocus://set?grayscale=0.8&blur=10&dim=0.2&mode=frontApp` | Set any subset of the sliders |
| `sharpfocus://set?focusedGray=1` | Keep the focused window grayscale |
| `sharpfocus://preset?name=Deep%20Work` | Apply a preset by name (case-insensitive) |
| `sharpfocus://snooze?minutes=30` | Snooze |
| `sharpfocus://settings` | Open settings |

```sh
open "sharpfocus://set?grayscale=1&blur=14&dim=0.3"
```

### Raycast

`integrations/raycast/sharp-focus.sh` is a Raycast Script Command wrapping the
URL scheme, with a dropdown for toggle / enable / disable / snooze / the three
seeded presets. Install it via **Raycast → Extensions → Script Commands → Add
Directory** and point it at `integrations/raycast/`.

The integration is one-directional: Raycast → Sharp Focus. Raycast's Focus
Sessions can't be observed by third-party apps, so Sharp Focus can't react to
them. If you want that behavior, use a macOS Focus mode and an automation rule
instead.

## How it works

One borderless, click-through overlay window per display, at the floating
window level. The menu bar, the Dock and open menus sit above it and are never
touched.

The overlay hosts two private `CABackdropLayer`s with `CAFilter` instances
(`colorSaturate` on one, `gaussianBlur` on the other) — the same
window-server mechanism
behind `NSVisualEffectView` vibrancy. The window server samples and filters
what is composited behind the overlay. The app itself never reads a single
pixel, which is why it needs no screen recording permission.

A `CAShapeLayer` even-odd mask per effect layer cuts holes over the windows
that should stay unfiltered — one shared set of holes normally, or a separate
grayscale set when "Focused window stays grayscale" is on. Hole geometry is
occlusion-aware: the tracker walks the window list
front to back and subtracts anything covering a focused window, so a
non-focused window floating on top of your editor is still filtered.

Window frames come from `CGWindowList` polled at 15 Hz, plus an app-activation
notification for immediate response. No accessibility permission is needed.
Global shortcuts use Carbon's `RegisterEventHotKey`, which also needs no
permission.

Mission Control and App Exposé animate every window on screen, and compositing
the overlay through that animation is visible. The tracker detects them
(screen-sized Dock-owned windows at an elevated layer) and hides the overlay
until they're dismissed. Toggle it in **Settings → General**.

## Limitations

- **The grayscale and blur rely on private API.** Apple can change or remove
  `CABackdropLayer` in any macOS release. Availability is probed at launch: if
  it's gone, the app keeps working as a dimmer, the menu says
  "Grayscale & blur unavailable on this macOS — dimming only", and the Effect
  tab shows the same warning. Dimming uses public API and will keep working.
- **Not eligible for the App Store**, for the same reason. Distribution is
  GitHub releases and source builds.
- **Other apps' floating windows stay in color.** Picture-in-picture players,
  translucent HUDs and panels at elevated window levels sit above the overlay.
  Nothing can be done about that from below.
- **A full-screen focused window means nothing is filtered.** The hole is the
  whole screen. Sharp Focus is most useful with more than one window visible.
- **Pins don't survive a relaunch**, because they're keyed on window IDs.
- **Focus-mode automation needs Full Disk Access.** Time rules don't.

## FAQ

**Why does it need no screen recording permission?**
Because it never looks at your screen. The filtering happens inside the window
server, behind an overlay window. The app only asks for window positions, which
`CGWindowList` hands out to any process.

**Why isn't it on the App Store?**
The grayscale and blur use a private Core Animation class. App Review rejects
that, and the sandbox wouldn't allow it anyway.

**Does it send data anywhere?**
No. There is no networking code in the app at all — no analytics, no update
check, no crash reporting. Settings live in `UserDefaults` on your machine.

## Repository layout

```
app/                      Swift package (macOS 14+)
  Sources/SharpFocus/     the app
  Sources/sfctl/          the CLI
  Scripts/bundle.sh       release build -> build/SharpFocus.app
web/                      landing page (Vite + TypeScript, pnpm)
integrations/raycast/     Raycast script command
```

Inside `Sources/SharpFocus/`: `OverlayController` owns the per-display overlay
windows and mask geometry, `FocusTracker` decides which regions stay in color,
`Backdrop` wraps the private API, `Commands` defines the shared sfctl/URL
vocabulary, `Automation` and `FocusModeMonitor` handle rules, `SettingsWindow`
is the SwiftUI settings panel.

## Contributing

Issues and pull requests are welcome. Small, focused changes are much easier to
review than large ones — if you're planning something substantial, open an
issue first so we can agree on the approach before you write it. Keep the
existing style: no dependencies, no analytics, no new permissions.

## License

MIT © [Aaron Richter](https://acrichter.com)

## Credits

Built by [Aaron Richter](https://acrichter.com).

[HazeOver](https://hazeover.com) is where the dim-everything-else idea comes
from; Sharp Focus adds desaturation and blur and keeps the effect per-window.
The settings window follows the layout of [Mos](https://github.com/Caldis/Mos),
which is the nicest small-utility preferences panel on macOS.
