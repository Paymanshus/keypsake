// AppState in main.swift: tab, search, the copied flash, plus the lists the backend publishes.
import { call, on } from "./api.js";

export const app = $state({
  tab: "typed",
  query: "",
  flash: null,
  focusSearch: 0,
  status: null,
  sessions: [],
  clips: [],
});

/** Up, down, enter, delete from the keyboard; the visible pane handles them. */
const navListeners = new Set();
export function onNav(f) {
  navListeners.add(f);
  return () => navListeners.delete(f);
}
export function nav(what) {
  for (const f of navListeners) f(what);
}

export async function load() {
  const [status, sessions, clips] = await Promise.all([call("status"), call("sessions"), call("clips")]);
  Object.assign(app, { status, sessions, clips });
  on("sessions-changed", async () => (app.sessions = await call("sessions")));
  on("clips-changed", async () => (app.clips = await call("clips")));
  on("status-changed", (s) => (app.status = s));
  on("focus-search", () => app.focusSearch++);
}

let flashTimer;
export async function copy(text, id) {
  await call("copy", { text });
  app.flash = id;
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => {
    if (app.flash === id) app.flash = null;
  }, 1200);
}

export async function setPrefs(patch) {
  app.status = await call("set_prefs", { prefs: { ...app.status.prefs, ...patch } });
}
