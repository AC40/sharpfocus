# Sharp Focus

Sharp Focus is a macOS menu bar app. It desaturates, blurs and dims everything
on screen except the window you're currently working in. The rest of your
desktop is still there, still readable if you look at it. It just stops
competing for attention. No screen recording permission, no accessibility
permission, no network access.

![Sharp Focus demo](docs/demo.gif)

<!-- TODO: record docs/demo.gif — switching windows with grayscale + blur on, then a preset switch. -->

Requires macOS 14 or later.

## Install

Download the latest `SharpFocus.app` from
[Releases](https://github.com/ac40/sharpfocus/releases) and move it to
`/Applications`.

The app is ad-hoc signed and **not notarized**, because notarization needs a
paid Apple Developer account. macOS will refuse the first launch. On Sequoia the
old right-click → Open trick no longer works, so you have two options:

1. Double-click the app, let macOS block it, then open **System Settings →
   Privacy & Security** and click **Open Anyway** next to the warning.
2. Or strip the quarantine attribute yourself:

   ```sh
   xattr -cr /Applications/SharpFocus.app
   ```

There is no Homebrew cask yet.

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

### Settings and Configuration

- **Grayscale.** 0–100%. Default 100%.
- **Blur.** 0–40 px. Default 0.
- **Dimming.** 0–90%. Default 20%.

**Keep in color** picks what counts as "in focus":

- _All windows of active app_, the default: every window of the frontmost app.
- _Focused window only_: just the frontmost window of the frontmost app.

**Focused window stays grayscale**: It splits the effect in two: blur and dimming still
lift for whatever is focused, but grayscale lifts only for pinned windows and
**Always in color** apps: The window you're working in is sharp and undimmed,
just desaturated. Only pinned and always-colored windows are ever in full color.

**Always in color**: A list of apps whose windows
never get filtered. A music player, a chat window you want to keep an eye on.
Matched by bundle identifier, so it survives restarts.

**Pinned windows** are matched by window ID instead, so they are session-only.
Quit the app or the pinned app and the pin is gone.

Settings live in `UserDefaults` under `com.acrichter.SharpFocus`.

## Scripting and integrations

### sfctl

`sfctl` is the [command-line interface](`/Applications/SharpFocus.app/Contents/MacOS/sfctl`) to Sharp Focus. Symlink it onto your `PATH`:

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
sfctl preset "Deep Work"           apply a preset and enable
sfctl snooze 30                    turn off for N minutes
sfctl mc-pause 1|0                 pause in Mission Control
sfctl settings                     open the settings window
```

It talks to the running app over a distributed notification and exits
immediately. If Sharp Focus isn't running, nothing happens and there is no
error.

### URL scheme

`sharpfocus://` works from anything that can open a URL. Shortcuts, Alfred,
Keyboard Maestro, a browser bar, `open`.

| URL                                                            | Effect                                   |
| -------------------------------------------------------------- | ---------------------------------------- |
| `sharpfocus://enable`                                          | Turn on                                  |
| `sharpfocus://disable`                                         | Turn off                                 |
| `sharpfocus://toggle`                                          | Flip                                     |
| `sharpfocus://set?grayscale=0.8&blur=10&dim=0.2&mode=frontApp` | Set any subset of the sliders            |
| `sharpfocus://set?focusedGray=1`                               | Keep the focused window grayscale        |
| `sharpfocus://preset?name=Deep%20Work`                         | Apply a preset by name, case-insensitive |
| `sharpfocus://snooze?minutes=30`                               | Snooze                                   |
| `sharpfocus://settings`                                        | Open settings                            |

```sh
open "sharpfocus://set?grayscale=1&blur=14&dim=0.3"
```

### Raycast

`integrations/raycast/sharp-focus.sh` is a Raycast Script Command wrapping the
URL scheme, with a dropdown for toggle / enable / disable / snooze / the three
seeded presets. Install it via **Raycast → Extensions → Script Commands → Add
Directory** and point it at `integrations/raycast/` or copy into your own folder.

## FAQ

**Why does it need no screen recording permission?**
Because it never looks at your screen. The filtering happens inside the window
server, behind an overlay window. The app only asks for window positions, which
`CGWindowList` hands out to any process.

**Why isn't it on the App Store?**
The grayscale and blur use a private Core Animation class. App Review rejects
that, and the sandbox wouldn't allow it anyway.

**Does it send data anywhere?**
No. There is no networking code in the app at all. No analytics, no update
check, no crash reporting. Settings live in `UserDefaults` on your machine.

## Contributing

Issues and pull requests are welcome. Small, focused changes are much easier to
review than large ones. If you're planning something substantial, open an issue
first so we can agree on the approach before you write it.

## License

MIT © [Aaron Richter](https://acrichter.com)
