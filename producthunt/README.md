# Sharp Focus — Product Hunt launch kit

Everything in `producthunt/` is ready to upload. No build step needed.

## What goes where

| PH field | File |
|---|---|
| Thumbnail (1:1) | `icons/thumbnail-512.png` |
| Video (first media) | `video/sharpfocus-launch-30s.mp4` — or upload to YouTube and paste the link |
| Gallery, in this order | `gallery/01-cover-1270x760.png` → `02-quiet` → `03-sliders` → `04-spotify` → `05-cli` → `06-privacy` |
| Social / OG | `social/og-1200x630.png` |

Cards 1–5 use **real captures**: the interactive demo on acrichter.com
(`/projects/sharpfocus` — ON, OFF, and menu-popover states, shot with Playwright)
and a real Terminal.app `sfctl --help` session. Only card 6 is drawn.
Source crops live in `shots/`.

Use the 1x PNGs for upload (all well under PH's limit).
The `@2x` versions are there if you want retina source files.
The `.svg` files are the masters — edit, then re-run `python3 generate.py`.
To re-capture the demo shots (needs the site dev server on :4321):
run `/tmp/pwshot/capture.js` + `off.js` with Playwright Chromium,
then `python3 generate.py`.

## Specs (already met)

- Gallery: 1270×760, PNG. Thumbnail: 512×512. OG: 1200×630.
- Video: 30 s, 1920×1080, H.264. Silent slideshow of the six cards.
  Before launch, consider replacing it with a real screen recording —
  the existing demo GIF in the README (`sharpfocus-demo`) shows the actual effect
  and would make a better video than these cards.

## Checklist

- [ ] Tagline ≤ 60 chars (options in `copy.md`)
- [ ] Topics: macOS, Productivity, Developer Tools, Open Source
- [ ] Pricing: Free, link to GitHub Releases
- [ ] First comment posted (draft in `copy.md`)
- [ ] Maker comment ready for questions about notarization (answer: ad-hoc signed, `xattr -cr`, in `copy.md`)
- [ ] Launch at 12:01 AM PT, be around for the first 4 hours
