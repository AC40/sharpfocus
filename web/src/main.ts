import "./styles.css";
import { mountDemo, PRESETS, type Mode, type DemoState } from "./demo";

const byId = <T extends HTMLElement>(id: string): T | null =>
  document.getElementById(id) as T | null;

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/* ── hero headline: the phrase fades out on load, once ─────────────────── */
const fadeWord = byId<HTMLElement>("fadeWord");
if (fadeWord && !reduceMotion) {
  window.setTimeout(() => fadeWord.classList.add("faded"), 700);
} else {
  fadeWord?.classList.add("faded");
}

/* ── the demo ──────────────────────────────────────────────────────────── */
const stage = byId<HTMLElement>("stage");
const desktop = byId<HTMLElement>("desktop");

if (stage && desktop) {
  const demo = mountDemo(stage, desktop);

  const toggle = byId<HTMLInputElement>("toggle");
  const toggleState = byId<HTMLElement>("toggleState");
  const grayscale = byId<HTMLInputElement>("grayscale");
  const blur = byId<HTMLInputElement>("blur");
  const dim = byId<HTMLInputElement>("dim");
  const grayscaleOut = byId<HTMLOutputElement>("grayscaleOut");
  const blurOut = byId<HTMLOutputElement>("blurOut");
  const dimOut = byId<HTMLOutputElement>("dimOut");
  const presets = byId<HTMLElement>("presets");
  const controls = byId<HTMLElement>("controls");

  const num = (el: HTMLInputElement | null, fallback: number): number =>
    el ? Number.parseInt(el.value, 10) || 0 : fallback;

  /* Keep the visible controls in sync with demo state (presets, hotkey…). */
  const syncControls = (s: Readonly<DemoState>): void => {
    if (toggle) toggle.checked = s.enabled;
    if (toggleState) toggleState.textContent = s.enabled ? "On" : "Off";
    if (grayscale) grayscale.value = String(s.grayscale);
    if (blur) blur.value = String(s.blur);
    if (dim) dim.value = String(s.dim);
    if (grayscaleOut) grayscaleOut.value = `${s.grayscale}%`;
    if (blurOut) blurOut.value = `${s.blur} px`;
    if (dimOut) dimOut.value = `${s.dim}%`;
    controls?.classList.toggle("live", s.enabled);
    for (const btn of document.querySelectorAll<HTMLButtonElement>("[data-preset]")) {
      const p = PRESETS[btn.dataset["preset"] ?? ""];
      const match =
        p !== undefined && p.grayscale === s.grayscale && p.blur === s.blur && p.dim === s.dim;
      btn.setAttribute("aria-pressed", String(match));
    }
  };
  demo.onChange(syncControls);

  toggle?.addEventListener("change", () => demo.setEnabled(toggle.checked));

  const wireSlider = (el: HTMLInputElement | null, key: "grayscale" | "blur" | "dim"): void => {
    el?.addEventListener("input", () => {
      demo.setFilter({ [key]: num(el, 0) } as Partial<
        Pick<DemoState, "grayscale" | "blur" | "dim">
      >);
      if (!demo.state.enabled) demo.setEnabled(true);
    });
  };
  wireSlider(grayscale, "grayscale");
  wireSlider(blur, "blur");
  wireSlider(dim, "dim");

  for (const radio of document.querySelectorAll<HTMLInputElement>('input[name="mode"]')) {
    radio.addEventListener("change", () => {
      if (radio.checked) demo.setMode(radio.value as Mode);
      if (!demo.state.enabled) demo.setEnabled(true);
    });
  }

  presets?.addEventListener("click", (ev) => {
    const btn = (ev.target as HTMLElement).closest<HTMLButtonElement>("[data-preset]");
    if (!btn) return;
    const preset = PRESETS[btn.dataset["preset"] ?? ""];
    if (!preset) return;
    demo.setFilter({ grayscale: preset.grayscale, blur: preset.blur, dim: preset.dim });
    demo.setEnabled(true);
  });

  /* The real global shortcut, on the page. */
  window.addEventListener("keydown", (ev) => {
    if (ev.ctrlKey && ev.altKey && ev.metaKey && ev.key.toLowerCase() === "f") {
      ev.preventDefault();
      demo.toggle();
      stage.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "center" });
    }
  });

  /* Nudge the switch once, after the windows have landed. */
  if (!reduceMotion && toggle) {
    const label = toggle.closest(".switch");
    window.setTimeout(() => label?.classList.add("nudge"), 2200);
    const stop = (): void => label?.classList.remove("nudge");
    toggle.addEventListener("focus", stop);
    toggle.addEventListener("change", stop);
    label?.addEventListener("pointerenter", stop);
  }

  syncControls(demo.state);
}
