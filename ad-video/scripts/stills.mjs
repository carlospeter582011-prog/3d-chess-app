// Dev helper: renders a list of frames of one composition as PNGs using a single bundle and browser.
// usage: node scripts/stills.mjs AdLandscape out/stills 0,40,80
import { bundle } from '@remotion/bundler';
import { renderStill, selectComposition, openBrowser } from '@remotion/renderer';
import path from 'node:path';
import fs from 'node:fs';

const [id, outDir, frameList] = process.argv.slice(2);
fs.mkdirSync(outDir, { recursive: true });
const serveUrl = await bundle({ entryPoint: path.resolve('src/index.ts'), publicDir: path.resolve('public') });
const browser = await openBrowser('chrome', { browserExecutable: process.env.CHROME_BIN || null, chromiumOptions: { gl: 'swangle' } });
const comp = await selectComposition({ serveUrl, id, puppeteerInstance: browser });
for (const f of frameList.split(',').map(Number)) {
  const t = Date.now();
  await renderStill({ composition: comp, serveUrl, frame: f, output: path.join(outDir, `${id}-${String(f).padStart(4, '0')}.png`), puppeteerInstance: browser, chromiumOptions: { gl: 'swangle' }, timeoutInMilliseconds: 180000, scale: Number(process.env.SCALE || 0.5) });
  console.log(id, 'frame', f, ((Date.now() - t) / 1000).toFixed(1) + 's');
}
await browser.close({ silent: true });
