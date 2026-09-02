/**
 * The fake macOS desktop in the hero.
 *
 * Everything is DOM + CSS: a wallpaper, a menu bar, six overlapping windows
 * and a dock. Turning "Sharp Focus" on applies
 * `filter: grayscale() blur() brightness()` to the wallpaper and to every
 * window that isn't being kept in color — which is what the real overlay does
 * to the pixels behind it.
 */

export type WindowId = "browser" | "chat" | "calendar" | "editor" | "build" | "music";
export type Mode = "window" | "app";

interface WindowDef {
  id: WindowId;
  /** Owning app — two windows share "Ember" so the mode switch is visible. */
  app: string;
  title: string;
  x: number;
  y: number;
  w: number;
  h: number;
  z: number;
  dark: boolean;
  body: string;
}

export interface DemoState {
  enabled: boolean;
  /** 0–100 */
  grayscale: number;
  /** 0–40 px */
  blur: number;
  /** 0–90 */
  dim: number;
  mode: Mode;
  focus: WindowId;
}

export interface Preset {
  label: string;
  grayscale: number;
  blur: number;
  dim: number;
}

export const PRESETS: Record<string, Preset> = {
  deep: { label: "Deep Work", grayscale: 100, blur: 12, dim: 55 },
  soft: { label: "Soft Focus", grayscale: 55, blur: 3, dim: 22 },
  mono: { label: "Monochrome", grayscale: 100, blur: 0, dim: 0 },
};

/** Design-space size of the fake desktop; scaled to fit its container. */
const STAGE_W = 1200;
const STAGE_H = 760;

/* ── little markup helpers ─────────────────────────────────────────────── */

const times = (n: number, fn: (i: number) => string): string =>
  Array.from({ length: n }, (_, i) => fn(i)).join("");

const lights = (): string =>
  `<span class="lights" aria-hidden="true"><i class="l-r"></i><i class="l-y"></i><i class="l-g"></i></span>`;

/* ── window bodies ─────────────────────────────────────────────────────── */

const CODE: string[] = [
  `<span class="c">// occlusion-aware holes: a window above a focused one</span>`,
  `<span class="c">// still gets filtered.</span>`,
  `<span class="k">private func</span> <span class="f">rebuildMask</span>(<span class="p">for</span> screen: <span class="t">NSScreen</span>) {`,
  `  <span class="k">let</span> path = <span class="t">CGMutablePath</span>()`,
  `  path.<span class="f">addRect</span>(screen.frame)`,
  ``,
  `  <span class="k">for</span> hole <span class="k">in</span> tracker.<span class="f">holes</span>(on: screen) {`,
  `    <span class="k">guard</span> hole.<span class="v">isVisible</span> <span class="k">else</span> { <span class="k">continue</span> }`,
  `    path.<span class="f">addRoundedRect</span>(<span class="k">in</span>: hole.<span class="v">frame</span>,`,
  `                        cornerWidth: <span class="n">10</span>,`,
  `                        cornerHeight: <span class="n">10</span>)`,
  `  }`,
  ``,
  `  mask.<span class="v">fillRule</span> = .<span class="v">evenOdd</span>`,
  `  mask.<span class="v">path</span> = path`,
  `  overlay.<span class="v">layer</span>?.<span class="v">mask</span> = mask`,
  `}`,
];

const editorBody = (): string => `
  <div class="ed">
    <div class="ed-side">
      <p class="ed-side-h">EMBER</p>
      <ul>
        <li>AppDelegate.swift</li>
        <li class="on">OverlayController.swift</li>
        <li>FocusTracker.swift</li>
        <li>Backdrop.swift</li>
        <li>HotKeys.swift</li>
        <li>Settings.swift</li>
      </ul>
    </div>
    <div class="ed-main">
      <div class="ed-tabs">
        <span class="on">OverlayController.swift</span><span>FocusTracker.swift</span>
      </div>
      <div class="ed-code">
        <div class="ed-gutter">${times(CODE.length, (i) => `<i>${i + 41}</i>`)}</div>
        <div class="ed-lines">${CODE.map((l) => `<div class="ed-ln">${l || "&nbsp;"}</div>`).join("")}</div>
      </div>
      <div class="ed-status"><span>swift</span><span>Ln 54, Col 21</span><span class="ok">main ✓</span></div>
    </div>
  </div>`;

const buildBody = (): string => `
  <div class="term">
    <p><span class="pr">~/dev/ember</span> <span class="cm">swift build -c release</span></p>
    <p class="dim">[1/6] Compiling Ember Backdrop.swift</p>
    <p class="dim">[2/6] Compiling Ember FocusTracker.swift</p>
    <p class="dim">[3/6] Compiling Ember OverlayController.swift</p>
    <p class="warn">warning: 'CABackdropLayer' is a private API</p>
    <p class="dim">[6/6] Linking Ember</p>
    <p class="ok">Build complete! (4.71s)</p>
    <p><span class="pr">~/dev/ember</span> <span class="cur"></span></p>
  </div>`;

const chatBody = (): string => `
  <div class="chat">
    <div class="chat-head"><span class="ch-name">#design-noise</span><span class="ch-badge">7</span></div>
    <div class="chat-list">
      <div class="msg"><i class="av a1"></i><div class="bub">did you see the new build? the blur is so smooth now</div></div>
      <div class="msg me"><div class="bub b-me">yeah I turned it up to 40 and nearly fell asleep</div></div>
      <div class="msg"><i class="av a2"></i><div class="bub">
        <span class="link-card"><i class="lc-thumb"></i><b>ember-labs/overlay</b><em>github.com</em></span>
      </div></div>
      <div class="msg"><i class="av a3"></i><div class="bub">standup in 5 ⏰</div></div>
      <div class="msg me"><div class="bub b-me">on it</div></div>
      <div class="msg"><i class="av a1"></i><div class="bub typing"><s></s><s></s><s></s></div></div>
    </div>
    <div class="chat-input"><span>Message #design-noise</span></div>
  </div>`;

const musicBody = (): string => `
  <div class="music">
    <div class="art" aria-hidden="true"><i class="art-a"></i><i class="art-b"></i><i class="art-c"></i></div>
    <div class="music-meta">
      <p class="tr">Sunset Diagonal</p>
      <p class="ar">Halogen Rivers</p>
      <div class="wave">${times(28, (i) => `<i style="--h:${20 + ((i * 37) % 80)}%"></i>`)}</div>
      <div class="bar"><i></i></div>
      <div class="tx"><span>1:48</span><span>3:52</span></div>
      <div class="transport">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M17 5 8 12l9 7zM7 5v14" /></svg>
        <svg viewBox="0 0 24 24" class="play" aria-hidden="true"><path d="M9 5v14M15 5v14" /></svg>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5l9 7-9 7zM17 5v14" /></svg>
      </div>
    </div>
  </div>`;

const HEADLINES: string[] = [
  "Every startup is now an AI startup",
  "The 14 best mechanical keyboards",
  "Markets wobble on chip news",
  "Sponsored: your new CRM",
];

const browserBody = (): string => `
  <div class="brw">
    <div class="brw-bar">
      <span class="url">the-daily-byte.example</span>
      <span class="brw-btn"></span><span class="brw-btn"></span>
    </div>
    <div class="brw-page">
      <div class="brw-mast"><b>THE DAILY BYTE</b><span>Tech · Markets · Gadgets · Opinion · Video</span></div>
      <div class="brw-hero">
        <i class="ph ph-1"></i>
        <div class="brw-txt"><b>${HEADLINES[0]}</b><s></s><s class="short"></s></div>
      </div>
      <div class="brw-ad">LIMITED TIME · 40% OFF EVERYTHING</div>
      <div class="brw-grid">
        ${times(3, (i) => `
          <div class="brw-card">
            <i class="ph ph-${i + 2}"></i>
            <b>${HEADLINES[i + 1] ?? ""}</b><s></s><s class="short"></s>
          </div>`)}
      </div>
    </div>
  </div>`;

const EVENTS: ReadonlyArray<readonly [number, number, string, string]> = [
  [1, 0, "e-a", "Standup"],
  [2, 1, "e-b", "1:1 Mara"],
  [3, 1, "e-c", "Design review"],
  [4, 2, "e-a", "Deep work"],
  [8, 0, "e-d", "Ship 0.1"],
  [9, 1, "e-b", "Lunch"],
  [11, 0, "e-c", "Retro"],
  [15, 0, "e-a", "Standup"],
  [16, 1, "e-d", "Interview"],
  [17, 0, "e-b", "Focus"],
  [18, 1, "e-c", "Demo"],
];

const calendarBody = (): string => {
  const cells = times(21, (i) => {
    const evs = EVENTS.filter((e) => e[0] === i)
      .map((e) => `<i class="ev ${e[2]}">${e[3]}</i>`)
      .join("");
    return `<div class="cal-cell${i === 3 ? " today" : ""}"><span>${i + 1}</span>${evs}</div>`;
  });
  return `
  <div class="cal">
    <div class="cal-head"><b>September</b><span class="cal-nav"><i></i><i></i></span></div>
    <div class="cal-dow">${["M", "T", "W", "T", "F", "S", "S"].map((d) => `<span>${d}</span>`).join("")}</div>
    <div class="cal-grid">${cells}</div>
  </div>`;
};

/* ── the windows ───────────────────────────────────────────────────────── */

const WINDOWS: readonly WindowDef[] = [
  { id: "browser", app: "Kestrel", title: "The Daily Byte — Kestrel", x: 380, y: 70, w: 640, h: 420, z: 1, dark: false, body: browserBody() },
  { id: "chat", app: "Chatter", title: "Chatter", x: 60, y: 118, w: 296, h: 380, z: 2, dark: false, body: chatBody() },
  { id: "calendar", app: "Almanac", title: "Almanac", x: 800, y: 330, w: 350, h: 290, z: 3, dark: false, body: calendarBody() },
  { id: "build", app: "Ember", title: "build — Ember", x: 640, y: 430, w: 380, h: 210, z: 4, dark: true, body: buildBody() },
  { id: "music", app: "Turntable", title: "Turntable", x: 90, y: 430, w: 310, h: 196, z: 5, dark: true, body: musicBody() },
  { id: "editor", app: "Ember", title: "OverlayController.swift — Ember", x: 250, y: 190, w: 560, h: 380, z: 6, dark: true, body: editorBody() },
];

const APP_OF: Record<WindowId, string> = WINDOWS.reduce(
  (acc, w) => {
    acc[w.id] = w.app;
    return acc;
  },
  {} as Record<WindowId, string>,
);

/* ── chrome ────────────────────────────────────────────────────────────── */

const menuBar = (): string => `
  <div class="menubar" aria-hidden="true">
    <div class="mb-left">
      <svg class="mb-apple" viewBox="0 0 24 24"><path d="M16.7 12.7c0-2.5 2-3.7 2.1-3.8-1.1-1.7-2.9-1.9-3.6-1.9-1.5-.2-3 .9-3.8.9s-2-.9-3.2-.9c-1.7 0-3.2 1-4 2.5-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.1-.8s1.9.8 3.2.8 2.1-1.2 2.9-2.3c.9-1.3 1.3-2.6 1.3-2.7-.1 0-2.4-1-2.2-3zM14.4 5.4c.7-.8 1.1-2 1-3.1-1 0-2.2.7-2.9 1.5-.6.7-1.2 1.9-1 3 1.1.1 2.2-.6 2.9-1.4z"/></svg>
      <b>Ember</b><span>File</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span>
    </div>
    <div class="mb-right">
      <svg class="mb-sf" id="mbIcon" viewBox="0 0 32 32"><circle cx="16" cy="16" r="12" class="mb-ring"/><path d="M16 5.4a10.6 10.6 0 0 1 0 21.2Z" class="mb-fill"/></svg>
      <svg class="mb-i" viewBox="0 0 24 24"><path d="M12 18.5h.01M4.5 11a10.6 10.6 0 0 1 15 0M7.6 14.3a6.2 6.2 0 0 1 8.8 0"/></svg>
      <svg class="mb-i" viewBox="0 0 26 24"><rect x="2.5" y="8.5" width="17" height="9" rx="2.6"/><rect x="4.5" y="10.5" width="11" height="5" rx="1.2" class="fill"/><path d="M21.5 11.5v5"/></svg>
      <span class="mb-clock" id="clock">Tue 09:41</span>
    </div>
  </div>`;

const DOCK_APPS = ["d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9"];

const dock = (): string => `
  <div class="dock" aria-hidden="true">
    <div class="dock-tray">
      ${DOCK_APPS.map((c, i) => `<i class="dk ${c}${i === 2 || i === 5 ? " running" : ""}"></i>`).join("")}
      <i class="dock-sep"></i>
      <i class="dk d-trash"></i>
    </div>
  </div>`;

const windowEl = (w: WindowDef, i: number): string => `
  <div class="win ${w.dark ? "dark" : "light"}" data-win="${w.id}" role="button" tabindex="0"
       aria-label="Focus the ${w.title.replace(/"/g, "")} window" aria-pressed="false"
       style="--x:${w.x}px; --y:${w.y}px; --w:${w.w}px; --h:${w.h}px; --z:${w.z}; --i:${i}">
    <div class="win-bar" aria-hidden="true">${lights()}<span class="win-title">${w.title}</span></div>
    <div class="win-body" aria-hidden="true">${w.body}</div>
  </div>`;

/* ── mount ─────────────────────────────────────────────────────────────── */

export interface Demo {
  readonly state: Readonly<DemoState>;
  setEnabled(on: boolean): void;
  toggle(): void;
  setFilter(part: Partial<Pick<DemoState, "grayscale" | "blur" | "dim">>): void;
  setMode(mode: Mode): void;
  setFocus(id: WindowId): void;
  onChange(fn: (s: Readonly<DemoState>) => void): void;
}

export function mountDemo(stage: HTMLElement, desktop: HTMLElement): Demo {
  desktop.innerHTML = `
    <div class="wallpaper" aria-hidden="true"></div>
    ${menuBar()}
    <div class="win-layer">${WINDOWS.map(windowEl).join("")}</div>
    ${dock()}`;

  const wins = new Map<WindowId, HTMLElement>();
  for (const el of desktop.querySelectorAll<HTMLElement>("[data-win]")) {
    const id = el.dataset["win"] as WindowId | undefined;
    if (id) wins.set(id, el);
  }
  const wallpaper = desktop.querySelector<HTMLElement>(".wallpaper");
  const mbIcon = desktop.querySelector<HTMLElement>("#mbIcon");

  const state: DemoState = {
    enabled: false,
    grayscale: 100,
    blur: 6,
    dim: 35,
    mode: "window",
    focus: "editor",
  };

  let topZ = WINDOWS.length;
  const listeners: Array<(s: Readonly<DemoState>) => void> = [];

  const keptInColor = (id: WindowId): boolean =>
    id === state.focus ||
    (state.mode === "app" && APP_OF[id] === APP_OF[state.focus]);

  const filterValue = (): string => {
    const parts: string[] = [];
    if (state.grayscale > 0) parts.push(`grayscale(${state.grayscale}%)`);
    if (state.blur > 0) parts.push(`blur(${state.blur}px)`);
    if (state.dim > 0) parts.push(`brightness(${(1 - state.dim / 100).toFixed(3)})`);
    return parts.length > 0 ? parts.join(" ") : "none";
  };

  const render = (): void => {
    const f = state.enabled ? filterValue() : "none";
    desktop.classList.toggle("on", state.enabled);
    if (wallpaper) wallpaper.style.filter = f;
    if (mbIcon) mbIcon.classList.toggle("active", state.enabled);
    for (const [id, el] of wins) {
      const kept = keptInColor(id);
      el.style.filter = kept ? "none" : f;
      el.classList.toggle("kept", state.enabled && kept);
      el.classList.toggle("muted", state.enabled && !kept);
      el.classList.toggle("focused", id === state.focus);
      el.setAttribute("aria-pressed", String(id === state.focus));
    }
    for (const fn of listeners) fn(state);
  };

  const raise = (el: HTMLElement): void => {
    topZ += 1;
    el.style.setProperty("--z", String(topZ));
  };

  for (const [id, el] of wins) {
    const focus = (): void => {
      state.focus = id;
      raise(el);
      render();
    };
    el.addEventListener("click", focus);
    el.addEventListener("keydown", (ev: KeyboardEvent) => {
      if (ev.key === "Enter" || ev.key === " ") {
        ev.preventDefault();
        focus();
      }
    });
  }

  /* Clock in the fake menu bar. */
  const clock = desktop.querySelector<HTMLElement>("#clock");
  const tick = (): void => {
    if (!clock) return;
    clock.textContent = new Intl.DateTimeFormat(undefined, {
      weekday: "short",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date());
  };
  tick();
  window.setInterval(tick, 20_000);

  /* Scale the 1200×760 design space into whatever width we get. */
  const fit = (): void => {
    const s = stage.clientWidth / STAGE_W;
    desktop.style.setProperty("--s", String(s));
    stage.style.setProperty("--stage-h", `${STAGE_H * s}px`);
  };
  fit();
  if (typeof ResizeObserver !== "undefined") {
    new ResizeObserver(fit).observe(stage);
  } else {
    window.addEventListener("resize", fit);
  }

  /* Staggered entrance once the desktop is on screen. */
  const reveal = (): void => desktop.classList.add("entered");
  if (typeof IntersectionObserver !== "undefined") {
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) {
            reveal();
            io.disconnect();
          }
        }
      },
      { threshold: 0.25 },
    );
    io.observe(stage);
  } else {
    reveal();
  }

  render();

  return {
    get state() {
      return state;
    },
    setEnabled(on) {
      state.enabled = on;
      render();
    },
    toggle() {
      state.enabled = !state.enabled;
      render();
    },
    setFilter(part) {
      Object.assign(state, part);
      render();
    },
    setMode(mode) {
      state.mode = mode;
      render();
    },
    setFocus(id) {
      const el = wins.get(id);
      if (el) raise(el);
      state.focus = id;
      render();
    },
    onChange(fn) {
      listeners.push(fn);
    },
  };
}
