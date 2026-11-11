// Prepares the 3D assets for the native Android renderer (Filament).
//
//   cd tools && npm install
//   node prepare_assets.mjs <dir with the original web *.glb models> ../assets/models
//
// What it does
//  1. The original models use the EXT_texture_webp extension (REQUIRED). Filament cannot decode WebP, so every texture is
//     re-encoded as JPEG (base colour 1024px, metal/rough 512px; board 2048px / 1024px) and the extension is removed.
//  2. Generates table.glb (big dark disc with a soft radial pool of light) and the small flat "marker" models
//     used for selection / last move / legal moves / captures / check.
import { Document, NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS, KHRMaterialsUnlit } from '@gltf-transform/extensions';
import { prune, textureCompress } from '@gltf-transform/functions';
import sharp from 'sharp';
import fs from 'node:fs';

const [SRC, OUT] = process.argv.slice(2);
if (!OUT || (!SRC && !process.env.ONLY_TABLE)) { console.error('usage: node prepare_assets.mjs <src models dir> <out dir>'); process.exit(1); }
fs.mkdirSync(OUT, { recursive: true });
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);

const PIECES = ['king', 'queen', 'bishop', 'knight', 'rook', 'pawn'];
const FILES = [...PIECES.flatMap((p) => [`${p}_light`, `${p}_dark`]), 'board'];

async function convert(name) {
  const doc = await io.read(`${SRC}/${name}.glb`);
  const board = name === 'board';
  await doc.transform(
    textureCompress({ encoder: sharp, targetFormat: 'jpeg', quality: 92, slots: /baseColor/, resize: board ? [2048, 2048] : [1024, 1024] }),
    textureCompress({ encoder: sharp, targetFormat: 'jpeg', quality: 90, slots: /^(?!.*baseColor)/, resize: board ? [1024, 1024] : [512, 512] }),
    prune(),
  );
  for (const ext of doc.getRoot().listExtensionsUsed()) if (ext.extensionName === 'EXT_texture_webp') ext.dispose();
  await io.write(`${OUT}/${name}.glb`, doc);
  return fs.statSync(`${OUT}/${name}.glb`).size;
}

// ---------------------------------------------------------------- procedural models
const srgb2lin = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
const hexLin = (hex, a = 1) => [srgb2lin((hex >> 16) & 255), srgb2lin((hex >> 8) & 255), srgb2lin(hex & 255), a];

function buildModel(name, { positions, uvs, indices, material, normals: customNormals }) {
  const doc = new Document();
  doc.createBuffer();
  const buffer = doc.getRoot().listBuffers()[0];
  const n = positions.length / 3;
  const normals = new Float32Array(n * 3);
  if (customNormals) normals.set(customNormals);
  else for (let i = 0; i < n; i++) normals[i * 3 + 1] = 1; // flat models face +Y
  const acc = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buffer);
  const prim = doc.createPrimitive()
    .setAttribute('POSITION', acc('VEC3', new Float32Array(positions)))
    .setAttribute('NORMAL', acc('VEC3', normals))
    .setIndices(acc('SCALAR', new Uint16Array(indices)));
  if (uvs) prim.setAttribute('TEXCOORD_0', acc('VEC2', new Float32Array(uvs)));
  prim.setMaterial(material(doc));
  const mesh = doc.createMesh(name).addPrimitive(prim);
  const node = doc.createNode(name).setMesh(mesh);
  doc.createScene(name).addChild(node);
  return doc;
}

function quad(h) {
  return { positions: [-h, 0, -h, -h, 0, h, h, 0, h, h, 0, -h], uvs: [0, 0, 0, 1, 1, 1, 1, 0], indices: [0, 1, 2, 0, 2, 3] };
}
function disc(r, seg, uvScale) {
  const positions = [0, 0, 0], uvs = [0.5, 0.5], indices = [];
  for (let i = 0; i <= seg; i++) {
    const a = (i / seg) * Math.PI * 2;
    const x = Math.cos(a) * r, z = Math.sin(a) * r;
    positions.push(x, 0, z); uvs.push(0.5 + (x / r) * 0.5 * uvScale, 0.5 + (z / r) * 0.5 * uvScale);
  }
  for (let i = 1; i <= seg; i++) indices.push(0, i + 1, i);
  return { positions, uvs, indices };
}
function ring(r0, r1, seg) {
  const positions = [], indices = [];
  for (let i = 0; i <= seg; i++) {
    const a = (i / seg) * Math.PI * 2, c = Math.cos(a), s = Math.sin(a);
    positions.push(c * r0, 0, s * r0, c * r1, 0, s * r1);
  }
  for (let i = 0; i < seg; i++) { const a = i * 2; indices.push(a, a + 3, a + 1, a, a + 2, a + 3); }
  return { positions, indices };
}

const unlitMat = (hex, alpha) => (doc) => {
  const ext = doc.createExtension(KHRMaterialsUnlit);
  return doc.createMaterial('marker').setBaseColorFactor(hexLin(hex, alpha)).setAlphaMode('BLEND').setDoubleSided(true)
    .setExtension('KHR_materials_unlit', ext.createUnlit());
};

async function png(width, height, fill) {
  const data = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) { const [r, g, b, a] = fill(x, y); const i = (y * width + x) * 4; data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = a; }
  return sharp(data, { raw: { width, height, channels: 4 } });
}
const lerp = (a, b, t) => a + (b - a) * t;
function gradient(stops, t) {
  t = Math.max(0, Math.min(1, t));
  for (let i = 1; i < stops.length; i++) if (t <= stops[i][0]) {
    const [t0, c0] = stops[i - 1], [t1, c1] = stops[i], k = (t - t0) / (t1 - t0 || 1);
    return c0.map((v, j) => lerp(v, c1[j], k));
  }
  return stops[stops.length - 1][1];
}

// ---- the table: a round walnut table top with a rounded edge and a pedestal, standing on a dark floor.
// One mesh and one material (Filament loads it as a single static model), so one texture atlas holds everything:
//   x 0..1024    table top (planks with grain, baked pool of light)
//   x 1024..1536 edge and pedestal (darker wood, grain running around)
//   x 1536..2048 floor (dark, with a soft contact shadow under the table)
const TABLE_R = 9, TABLE_THICK = 0.55, FLOOR_Y = -5, FLOOR_R = 46;

function makeNoise(seed) {
  let s = seed >>> 0; const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  const N = 256, g = Float32Array.from({ length: N * N }, rnd);
  const at = (x, y) => g[((y & 255) * N) + (x & 255)];
  const sm = (t) => t * t * (3 - 2 * t);
  const value = (x, y) => {
    const xi = Math.floor(x), yi = Math.floor(y), fx = sm(x - xi), fy = sm(y - yi);
    return lerp(lerp(at(xi, yi), at(xi + 1, yi), fx), lerp(at(xi, yi + 1), at(xi + 1, yi + 1), fx), fy);
  };
  const fbm = (x, y, o = 4) => { let a = 0.5, f = 1, t = 0; for (let i = 0; i < o; i++) { t += a * value(x * f, y * f); a *= 0.5; f *= 2; } return t; };
  return { fbm, rnd };
}

function woodColor(noise, u, v, { planks, dark }) {
  // u runs across the planks, v along the grain; both in 0..1
  const plank = Math.min(planks - 1, Math.floor(u * planks)), pu = u * planks - plank;
  const shift = noise.rnd() * 0; // keep deterministic per pixel
  const tone = 0.82 + 0.36 * (((plank * 7919) % 13) / 13); // each plank a slightly different shade
  const warp = noise.fbm(u * 6 + plank * 3.1, v * 1.5, 3) * 5;
  const rings = Math.sin((pu * 16 + warp + plank * 2.3) * Math.PI * 2 / 2);
  const fine = noise.fbm(u * 90, v * 6, 3);
  const grain = 0.5 + 0.5 * rings;
  let t = 0.35 * grain + 0.45 * fine + 0.2 * noise.fbm(u * 14, v * 40, 2) + shift;
  const c = gradient([[0, [0x3b, 0x24, 0x15]], [0.5, [0x6a, 0x42, 0x26]], [1, [0x93, 0x62, 0x3a]]], t);
  const seam = Math.min(pu, 1 - pu) < 0.012 ? 0.45 : 1; // dark gap between planks
  const k = tone * seam * (dark ? 0.62 : 1);
  return [c[0] * k, c[1] * k, c[2] * k];
}

async function tableAtlas() {
  const W = 2048, H = 1024, noise = makeNoise(777);
  const img = await png(W, H, (x, y) => {
    if (x < 1024) { // top
      const u = x / 1024, v = y / 1024, px = (u - 0.5) * 2 * TABLE_R, pz = (v - 0.5) * 2 * TABLE_R;
      const c = woodColor(noise, u, v, { planks: 4, dark: false });
      const r = Math.hypot(px, pz) / TABLE_R;
      const pool = 1.05 - 0.55 * Math.min(1, r * r * 0.9 + (r > 0.55 ? (r - 0.55) * 0.5 : 0)); // light pool in the middle
      const n = (noise.rnd() - 0.5) * 3;
      return [c[0] * pool + n, c[1] * pool + n, c[2] * pool + n, 255];
    }
    if (x < 1536) { // edge and pedestal: grain runs around, so it is stretched along u
      const u = (x - 1024) / 512, v = y / 1024;
      const c = woodColor(noise, v, u * 0.5, { planks: 1, dark: true });
      return [c[0], c[1], c[2], 255];
    }
    // floor: centre of this tile is under the table
    const dx = ((x - 1536) / 512 - 0.5) * 2, dy = (y / 1024 - 0.5) * 2, d = Math.hypot(dx, dy);
    const shadow = gradient([[0, [0x04, 0x03, 0x02]], [0.2, [0x06, 0x05, 0x04]], [0.45, [0x12, 0x0e, 0x0b]], [1, [0x15, 0x11, 0x0e]]], d / 1);
    const n = (noise.rnd() - 0.5) * 2;
    return [shadow[0] + n, shadow[1] + n, shadow[2] + n, 255];
  });
  return img.jpeg({ quality: 93 }).toBuffer();
}

function tableGeometry() {
  const P = [], N = [], T = [], I = [];
  const SEG = 96;
  const vert = (p, n, uv) => { P.push(...p); N.push(...n); T.push(...uv); return P.length / 3 - 1; };
  // top
  const RR = 0.28, TOP_R = TABLE_R - RR; // the flat top ends where the rounded edge begins
  let c = vert([0, 0, 0], [0, 1, 0], [0.25, 0.5]);
  const top0 = P.length / 3;
  for (let i = 0; i <= SEG; i++) {
    const a = (i / SEG) * Math.PI * 2, x = Math.cos(a) * TOP_R, z = Math.sin(a) * TOP_R;
    vert([x, 0, z], [0, 1, 0], [0.5 * (0.5 + x / (2 * TABLE_R)), 0.5 + z / (2 * TABLE_R)]);
  }
  for (let i = 0; i < SEG; i++) I.push(c, top0 + i + 1, top0 + i);
  // rounded edge: quarter circle from the top going down, then straight side to the underside
  const prof = []; // [radius, y, nx, ny]
  for (let k = 0; k <= 5; k++) { const t = (k / 5) * Math.PI / 2; prof.push([TABLE_R - RR + Math.sin(t) * RR, -RR + Math.cos(t) * RR, Math.sin(t), Math.cos(t)]); }
  prof.push([TABLE_R, -TABLE_THICK, 1, 0]);
  prof[0] = [TABLE_R - RR, 0, 0, 1];
  const ringStart = [];
  prof.forEach(([r, y, nx, ny], j) => {
    ringStart.push(P.length / 3);
    for (let i = 0; i <= SEG; i++) {
      const a = (i / SEG) * Math.PI * 2, ca = Math.cos(a), sa = Math.sin(a);
      vert([ca * r, y, sa * r], [ca * nx, ny, sa * nx], [0.5 + 0.25 * (i / SEG), 1 - (j / (prof.length - 1)) * 0.6]);
    }
  });
  for (let j = 0; j < prof.length - 1; j++) for (let i = 0; i < SEG; i++) {
    const a = ringStart[j] + i, b = ringStart[j + 1] + i;
    I.push(a, a + 1, b, a + 1, b + 1, b);
  }
  // pedestal
  const PR = 1.1, y0 = -TABLE_THICK, y1 = FLOOR_Y;
  const pBase = P.length / 3;
  for (let i = 0; i <= SEG; i++) {
    const a = (i / SEG) * Math.PI * 2, ca = Math.cos(a), sa = Math.sin(a);
    vert([ca * PR, y0, sa * PR], [ca, 0, sa], [0.5 + 0.25 * (i / SEG), 0.3]);
    vert([ca * PR, y1, sa * PR], [ca, 0, sa], [0.5 + 0.25 * (i / SEG), 0.9]);
  }
  for (let i = 0; i < SEG; i++) { const a = pBase + i * 2; I.push(a, a + 1, a + 2, a + 2, a + 1, a + 3); }
  // floor
  const fc = vert([0, FLOOR_Y, 0], [0, 1, 0], [0.875, 0.5]);
  const f0 = P.length / 3;
  for (let i = 0; i <= SEG; i++) {
    const a = (i / SEG) * Math.PI * 2, x = Math.cos(a) * FLOOR_R, z = Math.sin(a) * FLOOR_R;
    vert([x, FLOOR_Y, z], [0, 1, 0], [0.875 + 0.115 * Math.cos(a), 0.5 + 0.49 * Math.sin(a)]);
  }
  for (let i = 0; i < SEG; i++) I.push(fc, f0 + i + 1, f0 + i);
  return { positions: P, normals: N, uvs: T, indices: I };
}

async function tableModel() {
  const jpg = await tableAtlas();
  const g = tableGeometry();
  const doc = buildModel('table', {
    ...g,
    material: (d) => {
      const tex = d.createTexture('table').setImage(new Uint8Array(jpg)).setMimeType('image/jpeg');
      return d.createMaterial('table').setBaseColorTexture(tex).setBaseColorFactor([srgb2lin(0xd8), srgb2lin(0xd0), srgb2lin(0xc8), 1])
        .setRoughnessFactor(0.55).setMetallicFactor(0).setDoubleSided(true);
    },
  });
  await io.write(`${OUT}/table.glb`, doc);
}

async function checkModel() {
  const img = await png(128, 128, (x, y) => {
    const d = Math.hypot(x - 64, y - 64) / 64;
    const c = gradient([[0, [255, 40, 30, 0.95 * 255]], [0.6, [230, 40, 30, 0.5 * 255]], [1, [230, 40, 30, 0]]], (d * 64 - 4) / 60);
    return [c[0], c[1], c[2], c[3]];
  });
  const buf = await img.png().toBuffer();
  const doc = buildModel('marker_check', {
    ...quad(0.49),
    material: (d) => {
      const ext = d.createExtension(KHRMaterialsUnlit);
      const tex = d.createTexture('check').setImage(new Uint8Array(buf)).setMimeType('image/png');
      return d.createMaterial('marker_check').setBaseColorTexture(tex).setAlphaMode('BLEND').setDoubleSided(true).setExtension('KHR_materials_unlit', ext.createUnlit());
    },
  });
  await io.write(`${OUT}/marker_check.glb`, doc);
}

let total = 0;
if (!process.env.ONLY_TABLE) for (const f of FILES) { const sz = await convert(f); total += sz; console.log(f.padEnd(14), (sz / 1e6).toFixed(2), 'MB'); }
await tableModel();
if (process.env.ONLY_TABLE) process.exit(0);
await checkModel();
await io.write(`${OUT}/marker_sel.glb`, buildModel('marker_sel', { ...quad(0.49), material: unlitMat(0x4fd18b, 0.55) }));
await io.write(`${OUT}/marker_last.glb`, buildModel('marker_last', { ...quad(0.49), material: unlitMat(0xf3c64a, 0.42) }));
await io.write(`${OUT}/marker_dot.glb`, buildModel('marker_dot', { ...disc(0.16, 24, 1), material: unlitMat(0x3fa66f, 0.8) }));
await io.write(`${OUT}/marker_cap.glb`, buildModel('marker_cap', { ...ring(0.36, 0.47, 48), material: unlitMat(0xe5533d, 0.85) }));
console.log('models total', (total / 1e6).toFixed(2), 'MB');
