// The fonts live once, in the macOS app's Resources/Fonts. Copy them into the web build.
import { cpSync, mkdirSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const from = join(here, "../../../Resources/Fonts");
const to = join(here, "../ui/public/fonts");
mkdirSync(to, { recursive: true });
for (const f of readdirSync(from)) if (f.endsWith(".otf") || f.endsWith(".txt")) cpSync(join(from, f), join(to, f));
