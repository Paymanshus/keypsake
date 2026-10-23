// Screenshots of the UI with demo data, in a plain browser (no Windows needed):
//   npm run build && npm run snap [-- OUT_DIR]
// Same sizes as the macOS `--demo --snap` (main window 1080×700, Settings 480 wide), light and dark, at 2x.
import { preview } from "vite";
import { mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { execSync } from "node:child_process";

async function playwright() {
  try {
    return await import("playwright");
  } catch {
    // Fall back to a global install (npm i -g playwright).
    const root = execSync("npm root -g").toString().trim();
    return createRequire(root + "/")("playwright");
  }
}

const out = process.argv[2] ?? "../../docs/windows";
mkdirSync(out, { recursive: true });
const server = await preview({ preview: { port: 4173, strictPort: true } });
const { chromium } = await playwright();
const browser = await chromium.launch();
for (const scheme of ["light", "dark"]) {
  const suffix = scheme === "dark" ? "-dark" : "";
  const page = await browser.newPage({ viewport: { width: 1080, height: 700 }, deviceScaleFactor: 2, colorScheme: scheme });
  await page.goto("http://localhost:4173/index.html");
  await page.waitForSelector(".detail");
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: `${out}/typed${suffix}.png` });
  await page.click("text=Copied");
  await page.waitForSelector(".row");
  await page.screenshot({ path: `${out}/copied${suffix}.png` });
  const settings = await browser.newPage({ viewport: { width: 480, height: 600 }, deviceScaleFactor: 2, colorScheme: scheme });
  await settings.goto("http://localhost:4173/settings.html");
  await settings.waitForSelector(".settings");
  await settings.evaluate(() => document.fonts.ready);
  await settings.screenshot({ path: `${out}/settings${suffix}.png`, fullPage: true });
}
await browser.close();
server.httpServer.close();
console.log("wrote", out);
