# sharpfocus-web

Landing page for Sharp Focus. Vite + vanilla TypeScript + plain CSS, no framework,
no CSS library, no runtime dependencies.

```sh
pnpm install
pnpm dev        # http://localhost:5173
pnpm typecheck  # tsc --noEmit, strict
pnpm build      # -> dist/
pnpm preview    # serve dist/
```

## Files

| Path | What's in it |
| --- | --- |
| `index.html` | The whole page: hero, demo controls, feature sections, download, footer |
| `src/main.ts` | Wires the controls to the demo, hotkey handling, the headline fade |
| `src/demo.ts` | The fake macOS desktop — window definitions, markup, filter state |
| `src/styles.css` | Design tokens, page layout, and every pixel of the fake desktop |

## The demo

`src/demo.ts` renders a 1200 × 760 "desktop" (wallpaper, menu bar, six windows,
dock) and scales it with a CSS transform to whatever width the container has.
Below 720 px of viewport the scale stops at 0.5 and the stage pans horizontally
instead, so a phone gets a readable desktop rather than a postage stamp.

Turning the switch on sets `filter: grayscale() blur() brightness()` on the
wallpaper and on every window that isn't kept in color. The menu bar and the
dock are deliberately left alone — in the real app the overlay window sits
below them.

Two windows belong to the same fake app (`Ember`: the editor and the build log),
which is what makes the *Focused window* / *All windows of the app* switch
visible.

Adding or moving a window means editing the `WINDOWS` array in `src/demo.ts`.
Coordinates are in design space (the 1200 × 760 box); the dock occupies roughly
`y > 690`, so keep window bottoms above that.

## Placeholders to fill in before launch

- `[data-download-url]` in the download section — currently points at `#download`.
- `[data-version]` — the version string, and the release-notes paragraph next to it.
- The GitHub URLs assume `github.com/ac40/sharpfocus`.
- The "2.4 MB" size and "0.1.0" version in the download block are made up.

## Notes

- Light and dark come from `prefers-color-scheme`; both are defined as token
  sets at the top of `styles.css`.
- `prefers-reduced-motion` kills the entrance animation, the headline fade and
  the switch nudge.
- Fonts are Schibsted Grotesk + JetBrains Mono, loaded from Google Fonts. If
  you'd rather self-host, drop the `<link>` in `index.html` and the system
  fallbacks in `--sans` / `--mono` take over cleanly.
