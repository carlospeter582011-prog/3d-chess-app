// Builds assets/models/labels.glb: the 32 board-coordinate labels as flat, unlit, alpha-blended quads lying on the board
// frame, exactly like the web version (0.42 x 0.42 planes at y = surface + 0.004, a-h along z = +/-4.3, 1-8 along x = -/+4.3,
// the far-side set turned 180 degrees so it reads upright from Black's side).
//   python3 make_label_atlas.py labels_atlas.png && node make_labels.mjs labels_atlas.png ../assets/models/labels.glb
import { Document, NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS, KHRMaterialsUnlit } from '@gltf-transform/extensions';
import fs from 'node:fs';

const [ATLAS, OUT] = process.argv.slice(2);
if (!ATLAS || !OUT) { console.error('usage: node make_labels.mjs <atlas.png> <out.glb>'); process.exit(1); }
const SURFACE_Y = 0.464, Y = SURFACE_Y + 0.004, H = 0.21, R = 4.3;

const positions = [], uvs = [], indices = [];
function addQuad(cx, cz, cell, flipped) {
  const u0 = (cell % 4) / 4, v0 = Math.floor(cell / 4) / 4, d = 0.25;
  const base = positions.length / 3;
  // corners in text space: (sx, sy) with sy = +1 the top of the glyph; the glyph top points to -z (flipped: +z)
  for (const [sx, sy] of [[-1, 1], [-1, -1], [1, -1], [1, 1]]) {
    const k = flipped ? -1 : 1;
    positions.push(cx + k * sx * H, Y, cz - k * sy * H);
    uvs.push(u0 + (sx + 1) / 2 * d, v0 + (1 - sy) / 2 * d);
  }
  indices.push(base, base + 1, base + 2, base, base + 2, base + 3);
}
for (let i = 0; i < 8; i++) {
  addQuad(i - 3.5, R, i, false);          // a-h, White's edge (z = +4.3)
  addQuad(i - 3.5, -R, i, true);          // a-h, Black's edge
  addQuad(-R, 3.5 - i, 8 + i, false);     // 1-8, left edge (x = -4.3)
  addQuad(R, 3.5 - i, 8 + i, true);       // 1-8, right edge
}

const doc = new Document();
const buffer = doc.createBuffer();
const acc = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buffer);
const normals = new Float32Array(positions.length); for (let i = 1; i < normals.length; i += 3) normals[i] = 1;
const ext = doc.createExtension(KHRMaterialsUnlit);
const tex = doc.createTexture('labels').setImage(new Uint8Array(fs.readFileSync(ATLAS))).setMimeType('image/png');
const mat = doc.createMaterial('labels').setBaseColorTexture(tex).setAlphaMode('BLEND').setDoubleSided(true)
  .setExtension('KHR_materials_unlit', ext.createUnlit());
const prim = doc.createPrimitive()
  .setAttribute('POSITION', acc('VEC3', new Float32Array(positions)))
  .setAttribute('NORMAL', acc('VEC3', normals))
  .setAttribute('TEXCOORD_0', acc('VEC2', new Float32Array(uvs)))
  .setIndices(acc('SCALAR', new Uint16Array(indices)))
  .setMaterial(mat);
const node = doc.createNode('labels').setMesh(doc.createMesh('labels').addPrimitive(prim));
doc.createScene('labels').addChild(node);
await new NodeIO().registerExtensions(ALL_EXTENSIONS).write(OUT, doc);
console.log('wrote', OUT, fs.statSync(OUT).size, 'bytes');
