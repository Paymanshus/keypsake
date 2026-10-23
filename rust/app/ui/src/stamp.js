// Stamp in Theme.swift: "14:05" today, "Yest 14:05", else "Mar 4".
const time = (d) => d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false });

export function short(seconds) {
  const d = new Date(seconds * 1000);
  const today = new Date();
  const yest = new Date();
  yest.setDate(today.getDate() - 1);
  const same = (a, b) => a.toDateString() === b.toDateString();
  if (same(d, today)) return time(d);
  if (same(d, yest)) return "Yest " + time(d);
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

export const count = (n) => n.toLocaleString() + (n === 1 ? " char" : " chars");

/** Whitespace runs collapsed, first n characters: row previews. */
export const oneLine = (s, n) => [...s].slice(0, n).join("").split(/\s+/).filter(Boolean).join(" ");
