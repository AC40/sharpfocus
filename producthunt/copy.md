# Copy — pick one per slot, don't mix

## Tagline (≤ 60 chars)
1. Only your current window stays in color.
2. Your screen is too loud. Turn the rest down.
3. A menu bar app that quiets everything you're not using.

## Description (short)
Sharp Focus desaturates, blurs and dims everything on screen except the window
you're working in. The rest is still there, still readable. It just stops
competing for attention.

No screen recording permission. No account. No network code at all.

Free, MIT, macOS 14+.

## First comment
Hey, I'm Aaron. I built Sharp Focus because my desktop kept shouting at me.

It's a menu bar app. Everything except your current window goes grayscale
(plus optional blur and dimming). Three sliders, a few presets, done.

Two things people usually ask:

- **Permissions:** none required. It only asks the window server where windows
  are — it never looks at your screen. There's no networking code, so there's
  nothing to leak.
- **Install:** it's ad-hoc signed, not notarized (that needs a paid Apple
  account). If macOS blocks it: System Settings → Privacy & Security → Open
  Anyway, or `xattr -cr /Applications/SharpFocus.app`.

It also has a CLI (`sfctl`), a URL scheme, and a Raycast script, because of
course it does. Happy to answer anything.

## Launch posts
- **X:** My screen was too loud, so I built a macOS app that quiets every window I'm not using. Free, open source, no permissions, no tracking. Launching on Product Hunt today.
- **Mastodon:** Sharp Focus is live on Product Hunt — a tiny macOS menu bar app that keeps only your current window in color. MIT, no network code, no accounts.

## FAQ (for comments)
- **App Store?** Can't. The grayscale/blur uses a private Core Animation class,
  and the sandbox wouldn't allow it anyway.
- **Windows/Linux?** No. It works by sitting inside macOS's window server.
- **Does it work with Stage Manager / Spaces / Mission Control?** Yes. Optional
  Accessibility permission pauses it in Mission Control.
