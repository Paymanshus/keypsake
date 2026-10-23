// Demo data for a plain browser, from the same demo.json the app's --demo mode seeds.
import demo from "../../../crates/core/src/demo.json";

const now = Date.now() / 1000;
const len = (s) => [...new Intl.Segmenter().segment(s)].length;
let nextId = 1;
const sessions = [];
const snaps = {};
for (const s of demo.sessions) {
  const id = nextId++;
  snaps[id] = s.versions.map((v) => ({ id: nextId++, created: now - v.ago * 60, length: len(v.text), cliff: v.cliff, text: v.text }));
  const last = s.versions.at(-1);
  sessions.push({ id, created: now - s.versions[0].ago * 60, updated: now - last.ago * 60, app: s.app, bundle: s.bundle, window: s.window, domain: s.domain, text: last.text });
}
sessions.sort((a, b) => b.updated - a.updated);
const clips = demo.clips.map((c) => ({ id: nextId++, created: now - c.ago * 60, app: c.app, bundle: c.bundle, domain: c.domain, text: c.text }));
const prefs = { paused: false, retentionDays: 30, clipLimit: 50, shortcutOpen: "Ctrl+Alt+K", shortcutPause: "Ctrl+Alt+P", showChanges: true };
const listeners = {};

function emit(event, payload) {
  for (const f of listeners[event] ?? []) f(payload);
}

function defaultVersion(s) {
  if (!s.length) return null;
  const longest = s.reduce((a, b) => (b.length > a.length ? b : a));
  const last = s.at(-1);
  return last.length < Math.floor(longest.length / 2) ? longest.id : last.id;
}

const tokens = (s) => s.match(/\s+|\S+/g) ?? [];
const isSpace = (t) => /^\s+$/.test(t);

// Mock only: LCS word diff, rendered with the same rules as keypsake-core's diff.rs.
function compare(oldText, newText) {
  const a = tokens(oldText), b = tokens(newText);
  const dp = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
  for (let i = a.length - 1; i >= 0; i--)
    for (let j = b.length - 1; j >= 0; j--) dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  const removed = new Set(), inserted = new Set();
  let i = 0, j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) { i++; j++; }
    else if (j < b.length && (i >= a.length || dp[i][j + 1] >= dp[i + 1][j])) inserted.add(j++);
    else removed.add(i++);
  }
  const spans = [];
  const push = (text, kind) => (spans.at(-1)?.kind === kind ? (spans.at(-1).text += text) : spans.push({ text, kind }));
  let added = 0, gone = 0;
  i = 0; j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && removed.has(i)) {
      if (!isSpace(a[i])) { push(a[i], "removed"); push(" ", "same"); gone++; }
      i++;
    } else if (j < b.length && inserted.has(j)) {
      const ws = isSpace(b[j]);
      const joined = ws && !b[j].includes("\n") && inserted.has(j + 1);
      push(b[j], ws && !joined ? "same" : "added");
      if (!ws) added++;
      j++;
    } else {
      if (j < b.length) push(b[j], "same");
      i++; j++;
    }
  }
  const words = (n) => (n === 1 ? "1 word" : `${n} words`);
  const summary = !added && !gone ? "Same words as the version before" : !gone ? `${words(added)} added` : !added ? `${words(gone)} removed` : `${words(added)} added, ${gone} removed`;
  return { spans, summary };
}

const status = () => ({ prefs: { ...prefs }, typingError: null, clipboardError: null, shortcutError: null, demo: true });

const commands = {
  status,
  sessions: () => sessions,
  clips: () => clips,
  snapshots: ({ session }) => ({ snaps: snaps[session] ?? [], defaultVersion: defaultVersion(snaps[session] ?? []) }),
  compare: ({ old, new: n }) => compare(old, n),
  copy: () => null,
  delete_session: ({ id }) => { sessions.splice(sessions.findIndex((s) => s.id === id), 1); emit("sessions-changed"); },
  delete_clip: ({ id }) => { clips.splice(clips.findIndex((c) => c.id === id), 1); emit("clips-changed"); },
  delete_all: () => { sessions.length = 0; clips.length = 0; emit("sessions-changed"); emit("clips-changed"); },
  set_prefs: ({ prefs: p }) => { Object.assign(prefs, p); const s = status(); emit("status-changed", s); return s; },
  autostart: () => true,
  set_autostart: () => null,
  open_settings: () => window.open("settings.html", "_blank", "width=480,height=640"),
  app_icon: () => null,
  favicon: () => null,
};

export async function call(cmd, args) {
  return structuredClone(await commands[cmd](args));
}

export async function on(event, f) {
  (listeners[event] ??= []).push(f);
  return () => {};
}
