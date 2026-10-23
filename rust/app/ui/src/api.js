// The backend: Tauri commands in the app, or a demo-data mock in a plain browser (screenshots, UI work on any OS).
import * as mock from "./mock.js";

export const inTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;

let tauri;
async function core() {
  tauri ??= {
    ...(await import("@tauri-apps/api/core")),
    event: await import("@tauri-apps/api/event"),
    window: await import("@tauri-apps/api/window"),
    menu: await import("@tauri-apps/api/menu"),
  };
  return tauri;
}

export async function call(cmd, args = {}) {
  if (!inTauri) return mock.call(cmd, args);
  return (await core()).invoke(cmd, args);
}

export async function on(event, f) {
  if (!inTauri) return mock.on(event, f);
  return (await core()).event.listen(event, (e) => f(e.payload));
}

export async function currentWindow() {
  if (!inTauri) return null;
  return (await core()).window.getCurrentWindow();
}

/** Native right-click menu: items are [label, action]. */
export async function contextMenu(items) {
  if (!inTauri) return;
  const { Menu } = (await core()).menu;
  const menu = await Menu.new({ items: items.map(([text, action]) => ({ text, action })) });
  await menu.popup();
}

export async function fitWindow(width) {
  if (!inTauri) return;
  const { LogicalSize } = await import("@tauri-apps/api/dpi");
  const w = await currentWindow();
  await w.setSize(new LogicalSize(width, Math.ceil(document.documentElement.scrollHeight)));
}
