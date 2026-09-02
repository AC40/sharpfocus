# Sharp Focus

A macOS menu bar app that draws a live black-and-white filter over everything on
screen **except** the windows you're focusing on. Keep your editor in full color
while your music app, chats, and everything else fade into calm grayscale.

## How it works

One borderless, click-through overlay window per display sits just above the
normal window level (menu bar, Dock, and menus stay above it, untouched). A
`CAShapeLayer` even-odd mask cuts holes over the in-focus windows; hole
geometry is occlusion-aware, so a non-focused window floating above a focused
one is still filtered. Window frames come from `CGWindowList` polling (15 Hz)
— no Accessibility permission required.

### Three switchable filter engines

| Engine | Grayscale | Blur | Permissions | Measured cost* |
| --- | --- | --- | --- | --- |
| **Backdrop** (default) | ✓ | ✓ (native) | none | ~0 WindowServer, ~6% app |
| **Capture** | ✓ | ✓ (CoreImage) | Screen Recording | ~+38 pts WindowServer, ~22% app |
| **Dim Only** | – | – | none | ~0 |

*measured on a busy 2-display setup (1080p + Retina); idle screens cost far less.

- **Backdrop** uses the private `CABackdropLayer` + `CAFilter` API
  (`windowServerAware` behind-window sampling — the mechanism behind
  NSVisualEffectView vibrancy). The *window server* desaturates/blurs what's
  behind the overlay; the app never sees a pixel and needs no screen recording
  permission. Private API: could break on a macOS update, availability is
  probed at runtime with automatic fallback backdrop → capture → dim.
- **Capture** runs one ScreenCaptureKit stream per display (overlay excluded
  from its own capture) and filters frames in-process with a Metal-backed
  CIContext (max 15 fps; frames only arrive when content changes).
- **Dim Only** is a plain translucent layer, HazeOver-style.

Dimming works in every engine and stacks with grayscale/blur.

### Mission Control pause

Entering Mission Control / App Exposé animates every window and the overlay
used to cost visible frame drops there. The tracker detects it (screen-sized
Dock-owned windows at layers 18–20) and hides the overlay + pauses frame
processing for the duration. Toggle: "Pause in Mission Control".

## Usage

Menu bar icon (half-filled circle):

- **Enable Sharp Focus** — master toggle, also `⌃⌥⌘F` globally.
- **Keep in Color** — *Focused Window Only* or *All Windows of Active App*.
- **Always in Focus** — pick running apps whose windows always stay in color
  (e.g. your music player).
- **Pin Focused Window** (`⌃⌥⌘P`) — additionally keep the current window in
  color regardless of focus; *Clear Pinned Windows* resets (pins are
  session-only).
- **Engine** — Backdrop / Screen Capture / Dim Only, with live availability
  and the effective (post-fallback) engine shown.
- **Grayscale / Blur / Dimming sliders** — all three stack; blur is 0–40 pt
  (backdrop + capture engines).

Settings persist in `UserDefaults`.

### sfctl

`sfctl` drives the running app from the shell (distributed notifications):

```sh
sfctl engine backdrop|capture|dim
sfctl grayscale 0.8   # 0..1
sfctl blur 15         # 0..40 points
sfctl dim 0.3         # 0..0.9
sfctl mode focusedWindow|frontApp
sfctl enabled 1|0
sfctl mc-pause 1|0
```

## Build & run

```sh
swift build                       # debug build
./.build/debug/SharpFocus         # run directly (inherits the terminal's
                                  # Screen Recording permission)

./Scripts/bundle.sh               # release build -> build/SharpFocus.app
open build/SharpFocus.app         # first launch prompts for Screen Recording;
                                  # grant it in System Settings > Privacy &
                                  # Security > Screen Recording, then relaunch
```

Requires macOS 14+. The bundle is ad-hoc signed; for distribution, sign with a
Developer ID and notarize.

## Architecture

| File | Responsibility |
| --- | --- |
| `AppDelegate.swift` | Menu bar UI, engine lifecycle, sfctl command channel |
| `Settings.swift` | `UserDefaults`-backed config + change notifications |
| `FocusTracker.swift` | CGWindowList polling, occlusion-aware holes, Mission Control detection |
| `OverlayController.swift` | Per-screen overlay windows, layer stack per engine, mask geometry |
| `CaptureEngine.swift` | ScreenCaptureKit streams, CoreImage grayscale/blur pipeline |
| `Backdrop.swift` | Private CABackdropLayer/CAFilter wrapper + engine resolution |
| `HotKeys.swift` | Carbon global hotkeys (no permissions needed) |
| `SliderMenuItem.swift` | Slider controls inside the menu |
| `../sfctl/main.swift` | Shell control CLI |

## Known limitations / ideas

- Windows of *other* apps at elevated window levels (floating panels,
  picture-in-picture) sit above the overlay and stay in color.
- When the focused window covers the whole screen, nothing is visibly filtered
  (the hole is the screen).
- Pinned windows are tracked by window ID and don't survive app relaunch.
- Possible extensions: launch at login, per-app remembered profiles,
  configurable hotkeys, adaptive capture frame rate, Space-aware pinning.
