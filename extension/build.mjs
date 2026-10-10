import { build } from "esbuild";
import { mkdir, cp, copyFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL(".", import.meta.url));
const dist = fileURLToPath(new URL("./dist/", import.meta.url));
await mkdir(dist, { recursive: true });
for (const file of ["manifest.json", "client.html", "popup.html", "popup.js", "floating-orb.js", "pcm-worklet.js", "orb-icon.svg"]) {
  await copyFile(root + file, dist + file);
}
await cp(root + "icons", dist + "icons", { recursive: true });
await build({ absWorkingDir: root, entryPoints: ["client.js", "background.mjs"], outdir: dist,
  bundle: true, format: "esm", platform: "browser", target: "chrome116", legalComments: "eof" });
