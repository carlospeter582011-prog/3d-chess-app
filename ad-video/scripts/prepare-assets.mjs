// Prepares public/ for rendering (generated, git-ignored):
//  - the game's own 3D models and app icon, copied from ../assets (the original GLB files, unmodified)
//  - bundled OFL fonts from @fontsource
//  - the original sound design, synthesised in code (scripts/synth-audio.mjs): no third-party audio is used
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { synthAll } from './synth-audio.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '../../assets');
const pub = path.resolve(here, '../public');
for (const d of ['models', 'sfx', 'fonts']) fs.mkdirSync(path.join(pub, d), { recursive: true });

let n = 0;
for (const f of fs.readdirSync(path.join(app, 'models'))) {
  if (/^(board|table|(king|queen|rook|bishop|knight|pawn)_(light|dark))\.glb$/.test(f)) {
    fs.copyFileSync(path.join(app, 'models', f), path.join(pub, 'models', f));
    n++;
  }
}
if (n !== 14) throw new Error(`expected 14 model files, copied ${n}`);
fs.copyFileSync(path.join(app, 'icon/icon.png'), path.join(pub, 'icon.png'));

const fontRoot = path.resolve(here, '../node_modules/@fontsource');
for (const [pkg, weights] of [['cinzel', [600, 700, 900]], ['inter', [400, 500, 600, 700, 800]]]) {
  for (const w of weights) {
    const file = `${pkg}-latin-${w}-normal.woff2`;
    fs.copyFileSync(path.join(fontRoot, pkg, 'files', file), path.join(pub, 'fonts', file));
  }
}

synthAll(path.join(pub, 'sfx'));
console.log('assets ready in', pub);
