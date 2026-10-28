#!/usr/bin/env python3
"""Product Hunt gallery for Sharp Focus, v3: minimal headlines + REAL captures.

Sources:
  /tmp/shots/demo-on.png       interactive site demo, effect ON  (1952x1238)
  /tmp/shots/demo-off.png      interactive site demo, effect OFF (1952x1238)
  /tmp/shots/demo-popover.png  demo ON with SF menu popover open (1952x1238)
  /tmp/shots/terminal4.png     real Terminal.app, sfctl --help   (1440x600)
Pipeline: PIL crops -> producthunt/shots/ -> SVG (base64 <image>) -> PNG via rsvg-convert.
"""
import subprocess, os, base64, io

W, H = 1270, 760
OUT = os.path.dirname(os.path.abspath(__file__))
GAL = os.path.join(OUT, "gallery")
SHOTDIR = os.path.join(OUT, "shots")
os.makedirs(GAL, exist_ok=True)
os.makedirs(SHOTDIR, exist_ok=True)

from PIL import Image

# demo captures are the stage element at DSF2: CSS 976x618.86 -> 1952x1238
SX, SY = 1952 / 1200, 1238 / 760

def design_crop(src, name, x, y, w, h, out_w):
    """Crop design-space box from a demo capture, save at out_w wide."""
    im = Image.open(src)
    box = (int(x * SX), int(y * SY), int((x + w) * SX), int((y + h) * SY))
    c = im.crop(box)
    out_h = round(c.height * out_w / c.width)
    c = c.resize((out_w, out_h), Image.LANCZOS)
    p = os.path.join(SHOTDIR, name)
    c.save(p)
    print("crop", p, c.size)
    return p, out_w, out_h

def px_crop(src, name, box, out_w):
    im = Image.open(src)
    c = im.crop(box)
    out_h = round(c.height * out_w / c.width)
    c = c.resize((out_w, out_h), Image.LANCZOS)
    p = os.path.join(SHOTDIR, name)
    c.save(p)
    print("crop", p, c.size)
    return p, out_w, out_h

def b64(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()

INK = "#FFFFFF"
GREEN = "#3DDC84"
SUB = "#B9B9C0"

DEFS = '''
  <defs>
    <linearGradient id="warm" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FF9E2C"/><stop offset="1" stop-color="#FF4D42"/>
    </linearGradient>
    <radialGradient id="glowO" cx="0.85" cy="0.08" r="0.65">
      <stop offset="0" stop-color="#FF8A2A" stop-opacity="0.16"/><stop offset="1" stop-color="#FF8A2A" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glowG" cx="0.08" cy="1" r="0.65">
      <stop offset="0" stop-color="#3DDC84" stop-opacity="0.08"/><stop offset="1" stop-color="#3DDC84" stop-opacity="0"/>
    </radialGradient>
  </defs>'''

def base():
    return (f'<rect width="{W}" height="{H}" fill="#0B0B0E"/>'
            f'<rect width="{W}" height="{H}" fill="url(#glowO)"/>'
            f'<rect width="{W}" height="{H}" fill="url(#glowG)"/>')

def brand():
    return '''
    <rect x="64" y="52" width="36" height="36" rx="9" fill="#17171B" stroke="#FFFFFF" stroke-opacity="0.14"/>
    <clipPath id="lg"><rect x="64" y="52" width="36" height="36" rx="9"/></clipPath>
    <g clip-path="url(#lg)">
      <circle cx="82" cy="70" r="10" fill="#8E8E96"/>
      <path d="M 82 60 A 10 10 0 0 0 82 80 Z" fill="url(#warm)"/>
    </g>
    <text x="110" y="77" font-family="SF Pro Display, Helvetica, Arial, sans-serif" font-size="20" font-weight="600" fill="#FFFFFF" opacity="0.9">Sharp Focus</text>'''

def headline(lines, x=64, y=320, size=84, lh=88):
    return "\n".join(
        f'<text x="{x}" y="{y+i*lh}" font-family="SF Pro Display, Helvetica, Arial, sans-serif" font-size="{size}" font-weight="800" letter-spacing="-2" fill="{fill}">{t}</text>'
        for i, (t, fill) in enumerate(lines))

def subline(lines, x=64, y=540):
    return "\n".join(
        f'<text x="{x}" y="{y+i*30}" font-family="SF Pro Text, Helvetica, Arial, sans-serif" font-size="20" fill="{SUB}">{t}</text>'
        for i, t in enumerate(lines))

_uid = [0]
def photo(uri, x, y, w, h, r=20):
    _uid[0] += 1
    cid = f"ph{_uid[0]}"
    return f'''
    <clipPath id="{cid}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/></clipPath>
    <image href="{uri}" x="{x}" y="{y}" width="{w}" height="{h}" clip-path="url(#{cid})" preserveAspectRatio="xMidYMid slice"/>
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="none" stroke="#FFFFFF" stroke-opacity="0.16" stroke-width="1.5"/>'''

def tag(x, y, label, fill="#FFFFFF", bg="#000000", opacity=0.62):
    return f'''
    <rect x="{x}" y="{y}" width="{len(label)*9+22}" height="26" rx="13" fill="{bg}" opacity="{opacity}"/>
    <text x="{x + (len(label)*9+22)/2}" y="{y+18}" text-anchor="middle" font-family="SF Pro Text, Helvetica, Arial, sans-serif" font-size="12" font-weight="800" letter-spacing="1.5" fill="{fill}" opacity="1">{label}</text>'''

def svg_doc(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{DEFS}{body}</svg>'

ON = "/tmp/shots/demo-on.png"
OFF = "/tmp/shots/demo-off.png"
POP = "/tmp/shots/demo-popover.png"
TERM = "/tmp/shots/terminal4.png"

def card01():
    p, w, h = design_crop(ON, "hero.png", 0, 0, 1200, 760, 1116)
    y = 203
    b = base() + brand()
    b += headline([("Your screen", INK), ("is too loud.", GREEN)])
    b += subline(["Sharp Focus quiets everything", "except the window you\u2019re in."])
    b += photo(b64(p), 648, y, 558, 354)
    return svg_doc(b)

def card02():
    po, _, _ = design_crop(OFF, "split-off.png", 40, 60, 1120, 580, 1116)
    pn, _, _ = design_crop(ON, "split-on.png", 40, 60, 1120, 580, 1116)
    uo, un = b64(po), b64(pn)
    fx, fw, fh = 648, 558, 269
    y = 150
    half = fw // 2
    b = base() + brand()
    b += headline([("The rest", INK), ("goes quiet.", GREEN)])
    b += f'''
    <clipPath id="spO"><rect x="{fx}" y="{y}" width="{fw}" height="{fh}" rx="20"/></clipPath>
    <clipPath id="spL"><rect x="{fx}" y="{y}" width="{half}" height="{fh}"/></clipPath>
    <clipPath id="spR"><rect x="{fx+half}" y="{y}" width="{fw-half}" height="{fh}"/></clipPath>
    <g clip-path="url(#spO)">
      <image href="{uo}" x="{fx}" y="{y}" width="{fw}" height="{fh}" preserveAspectRatio="none" clip-path="url(#spL)"/>
      <image href="{un}" x="{fx}" y="{y}" width="{fw}" height="{fh}" preserveAspectRatio="none" clip-path="url(#spR)"/>
      <rect x="{fx+half-1}" y="{y}" width="2" height="{fh}" fill="#FFFFFF" opacity="0.5"/>
    </g>
    <rect x="{fx}" y="{y}" width="{fw}" height="{fh}" rx="20" fill="none" stroke="#FFFFFF" stroke-opacity="0.16" stroke-width="1.5"/>'''
    b += tag(fx + 14, y + fh - 40, "OFF") + tag(fx + fw - 14 - 62, y + fh - 40, "ON")
    return svg_doc(b)

def card03():
    p, w, h = design_crop(POP, "popover.png", 600, 0, 600, 640, 520)
    b = base() + brand()
    b += headline([("Three sliders.", INK), ("That\u2019s the app.", GREEN)])
    b += photo(b64(p), 700, 140, 520, 555)
    return svg_doc(b)

def card04():
    p, w, h = design_crop(ON, "spotify.png", 60, 150, 880, 540, 1116)
    y = 196
    b = base() + brand()
    b += headline([("Keep Spotify", INK), ("in color.", GREEN)])
    b += subline(["Pinned windows and always-in-color apps.", "Your call."])
    b += photo(b64(p), 648, y, 558, 342)
    return svg_doc(b)

def card05():
    p, w, h = px_crop(TERM, "terminal.png", (0, 28, 1440, 458), 1142)
    b = base() + brand()
    b += headline([("It has a CLI,", INK), ("obviously.", GREEN)], y=210, size=76, lh=80)
    b += photo(b64(p), 64, 388, 1142, 341, r=16)
    return svg_doc(b)

def card06():
    def row(y, label):
        return f'''
        <circle cx="712" cy="{y}" r="17" fill="#3DDC84" fill-opacity="0.16"/>
        <text x="712" y="{y+7}" text-anchor="middle" font-family="SF Pro Text, Helvetica, Arial, sans-serif" font-size="17" font-weight="800" fill="#3DDC84">\u2713</text>
        <text x="744" y="{y+10}" font-family="SF Pro Display, Helvetica, Arial, sans-serif" font-size="30" font-weight="700" letter-spacing="-0.5" fill="#1C1C1E">{label}</text>'''
    b = base() + brand()
    b += headline([("It can\u2019t", INK), ("spy on you.", GREEN)])
    b += subline(["No network code. Nothing to leak."])
    b += f'''
      <rect x="648" y="170" width="558" height="420" rx="24" fill="#FFFFFF"/>
      {row(280, "No screen recording")}
      {row(380, "No network")}
      {row(480, "No analytics")}'''
    return svg_doc(b)

def write(name, svg):
    sp = os.path.join(GAL, f"{name}.svg")
    with open(sp, "w") as f:
        f.write(svg)
    for w in (1270, 2540):
        png = os.path.join(GAL, f"{name}-1270x760{'@2x' if w == 2540 else ''}.png")
        cmd = ["rsvg-convert", "-w", str(w), "-h", str(int(w * H / W)), "-f", "png", "-o", png, sp]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            print("FAIL", name, r.stderr[:800]); raise SystemExit(1)
        print("wrote", png, os.path.getsize(png) // 1024, "KB")

def main():
    cards = [("01-cover", card01()), ("02-quiet", card02()), ("03-sliders", card03()),
             ("04-spotify", card04()), ("05-cli", card05()), ("06-privacy", card06())]
    for name, svg in cards:
        write(name, svg)

if __name__ == "__main__":
    main()
