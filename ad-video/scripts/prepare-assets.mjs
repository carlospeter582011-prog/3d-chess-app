// Copies the game's own 3D models, icon and jingles from the app (../assets) into public/ and synthesizes the
// wood-knock move sounds. public/ is generated, so it is git-ignored.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '../../assets');
const pub = path.resolve(here, '../public');
fs.mkdirSync(path.join(pub, 'models'), { recursive: true });
fs.mkdirSync(path.join(pub, 'sfx'), { recursive: true });

for (const f of fs.readdirSync(path.join(app, 'models'))) {
  if (/^(board|table|(king|queen|rook|bishop|knight|pawn)_(light|dark))\.glb$/.test(f)) {
    fs.copyFileSync(path.join(app, 'models', f), path.join(pub, 'models', f));
  }
}
fs.copyFileSync(path.join(app, 'icon/icon.png'), path.join(pub, 'icon.png'));
for (const f of ['checkmate.mp3', 'stalemate.mp3']) fs.copyFileSync(path.join(app, 'sfx', f), path.join(pub, 'sfx', f));

// ---- synthesized knock (wood on wood): a short noise click + a few decaying resonances
const SR = 44100;
function knock({ dur = 0.16, base = 330, gain = 0.9, seed = 1 }) {
  const n = Math.floor(SR * dur);
  const out = new Float32Array(n);
  let s = seed;
  const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;
  let lp = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    lp += 0.35 * (rnd() - lp);
    const click = lp * Math.exp(-t * 400);
    let body = 0;
    for (const [m, a, d] of [[1, 1, 38], [2.32, 0.55, 55], [3.9, 0.3, 80]]) body += a * Math.sin(2 * Math.PI * base * m * t) * Math.exp(-t * d);
    out[i] = Math.tanh(gain * (0.9 * body + 1.3 * click));
  }
  return out;
}
function wav(samples) {
  const b = Buffer.alloc(44 + samples.length * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + samples.length * 2, 4); b.write('WAVEfmt ', 8);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22); b.writeUInt32LE(SR, 24);
  b.writeUInt32LE(SR * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(samples.length * 2, 40);
  samples.forEach((v, i) => b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32000), 44 + i * 2));
  return b;
}
fs.writeFileSync(path.join(pub, 'sfx/move.wav'), wav(knock({ base: 330 })));
fs.writeFileSync(path.join(pub, 'sfx/capture.wav'), wav(knock({ base: 260, dur: 0.22, gain: 1.4, seed: 7 })));
console.log('assets ready in', pub);
