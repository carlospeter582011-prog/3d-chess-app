// Original sound design for the advertisement, synthesised in code (deterministic, no samples, no third-party audio).
// Every file written here is created by this script, so the audio has no external licence: it is released under the
// same terms as the rest of this repository. Run through prepare-assets.mjs.
import fs from 'node:fs';
import path from 'node:path';

const SR = 44100;
const TAU = Math.PI * 2;

function rng(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;
}

const buf = (sec) => new Float32Array(Math.ceil(sec * SR));
const env = (t, a, d) => (t < a ? t / a : Math.exp(-(t - a) * d));

/** One-pole low-pass applied in place with a (possibly time-varying) cutoff function. */
function lowpass(x, fc) {
  let y = 0;
  for (let i = 0; i < x.length; i++) {
    const c = typeof fc === 'function' ? fc(i / SR) : fc;
    const a = 1 - Math.exp((-TAU * c) / SR);
    y += a * (x[i] - y);
    x[i] = y;
  }
  return x;
}

/** Band-pass noise with a swept centre (state-variable filter). */
function sweptNoise(sec, f0, f1, q, seed, shape) {
  const r = rng(seed);
  const out = buf(sec);
  let low = 0, band = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / SR, k = t / sec;
    const f = f0 * Math.pow(f1 / f0, k);
    const g = 2 * Math.sin((Math.PI * Math.min(f, 12000)) / SR);
    const n = r();
    low += g * band;
    const high = n - low - band / q;
    band += g * high;
    out[i] = band * shape(k);
  }
  return out;
}

/** Schroeder reverb (mono): four feedback combs into two all-pass stages, darkened, mixed with the dry signal. */
function reverb(x, tail = 2.0, mix = 0.35) {
  const len = x.length + Math.ceil(tail * SR);
  const wet = new Float32Array(len);
  for (const d of [0.0297, 0.0371, 0.0411, 0.0437]) {
    const n = Math.floor(d * SR), line = new Float32Array(n), fb = Math.pow(0.001, d / tail);
    let p = 0;
    for (let i = 0; i < len; i++) {
      const y = (i < x.length ? x[i] : 0) + line[p] * fb;
      line[p] = y;
      wet[i] += y * 0.25;
      p = (p + 1) % n;
    }
  }
  for (const d of [0.005, 0.0017]) {
    const n = Math.floor(d * SR), line = new Float32Array(n);
    let p = 0;
    for (let i = 0; i < len; i++) {
      const delayed = line[p], y = wet[i] + delayed * 0.7;
      line[p] = y;
      wet[i] = delayed - y * 0.7;
      p = (p + 1) % n;
    }
  }
  lowpass(wet, 5200);
  const out = new Float32Array(len);
  for (let i = 0; i < len; i++) out[i] = (i < x.length ? x[i] : 0) + wet[i] * mix * 1.6;
  return out;
}

const norm = (x, peak) => {
  let m = 1e-9;
  for (const v of x) m = Math.max(m, Math.abs(v));
  const g = peak / m;
  for (let i = 0; i < x.length; i++) x[i] *= g;
  return x;
};

function wav(chL, chR) {
  const n = chL.length, stereo = !!chR;
  const ch = stereo ? 2 : 1;
  const b = Buffer.alloc(44 + n * 2 * ch);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * 2 * ch, 4); b.write('WAVEfmt ', 8);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(ch, 22); b.writeUInt32LE(SR, 24);
  b.writeUInt32LE(SR * 2 * ch, 28); b.writeUInt16LE(2 * ch, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(n * 2 * ch, 40);
  const q = (v) => Math.round(Math.max(-1, Math.min(1, v)) * 32000);
  for (let i = 0; i < n; i++) {
    b.writeInt16LE(q(chL[i]), 44 + i * 2 * ch);
    if (stereo) b.writeInt16LE(q(chR[i]), 46 + i * 4);
  }
  return b;
}

// ---------------------------------------------------------------- effects
function knock({ dur = 0.2, base = 330, gain = 0.9, seed = 1 }) {
  const out = buf(dur), r = rng(seed);
  let lp = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    lp += 0.35 * (r() - lp);
    const click = lp * Math.exp(-t * 400);
    let body = 0;
    for (const [m, a, d] of [[1, 1, 38], [2.32, 0.55, 55], [3.9, 0.3, 80]]) body += a * Math.sin(TAU * base * m * t) * Math.exp(-t * d);
    out[i] = Math.tanh(gain * (0.9 * body + 1.3 * click));
  }
  return out;
}

function whoosh(sec, f0, f1, seed, peakAt = 0.55) {
  const shape = (k) => Math.pow(Math.sin(Math.PI * Math.pow(k, Math.log(0.5) / Math.log(peakAt))), 2);
  return norm(sweptNoise(sec, f0, f1, 1.4, seed, shape), 0.7);
}

function riser(sec) {
  const n = sweptNoise(sec, 220, 7000, 2.2, 11, (k) => Math.pow(k, 2.2));
  const out = buf(sec);
  for (let i = 0; i < out.length; i++) {
    const t = i / SR, k = t / sec;
    const f = 180 * Math.pow(6, k);
    out[i] = n[i] * 0.8 + 0.25 * Math.sin(TAU * f * t) * Math.pow(k, 2) * (0.7 + 0.3 * Math.sin(TAU * 14 * t));
  }
  return norm(out, 0.75);
}

function subBoom(sec, f0, f1, decay) {
  const out = buf(sec);
  let ph = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const f = f1 + (f0 - f1) * Math.exp(-t * 14);
    ph += (TAU * f) / SR;
    out[i] = Math.sin(ph) * Math.exp(-t * decay);
  }
  return out;
}

function hit({ sec, sub0, sub1, subDecay, noiseDecay, noiseLp, metal, metalAmp, tail, mix, seed }) {
  const x = subBoom(sec, sub0, sub1, subDecay);
  const r = rng(seed);
  const n = buf(sec);
  for (let i = 0; i < n.length; i++) n[i] = r() * Math.exp((-i / SR) * noiseDecay);
  lowpass(n, noiseLp);
  for (let i = 0; i < x.length; i++) {
    const t = i / SR;
    let m = 0;
    for (const [mult, a] of [[1, 1], [2.76, 0.6], [5.4, 0.35], [8.93, 0.2]]) m += a * Math.sin(TAU * metal * mult * t) * Math.exp(-t * (3 + mult * 0.9));
    x[i] = x[i] * 0.95 + n[i] * 0.55 + m * metalAmp;
  }
  return norm(reverb(x, tail, mix), 0.95);
}

function bell(freq, sec, amp, idx = 2.2, ratio = 3.5, decay = 2.2) {
  const out = buf(sec);
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const mod = idx * Math.exp(-t * 3.5) * Math.sin(TAU * freq * ratio * t);
    out[i] = amp * Math.sin(TAU * freq * t + mod) * env(t, 0.003, decay);
  }
  return out;
}

function mixInto(dst, src, at, gain = 1) {
  const o = Math.floor(at * SR);
  for (let i = 0; i < src.length && o + i < dst.length; i++) dst[o + i] += src[i] * gain;
}

function brand() {
  const x = buf(3.2);
  mixInto(x, bell(880, 3, 0.5, 1.6, 3.5, 1.6), 0);
  mixInto(x, bell(1318.5, 3, 0.35, 1.4, 3.5, 1.8), 0.09);
  mixInto(x, bell(1760, 3, 0.28, 1.2, 3.5, 2.0), 0.18);
  mixInto(x, bell(2637, 2.4, 0.12, 1.0, 3.5, 2.6), 0.26);
  mixInto(x, subBoom(2.2, 110, 55, 2.2), 0, 0.35);
  return norm(reverb(x, 2.4, 0.4), 0.8);
}

// ---------------------------------------------------------------- music
/** Original cinematic bed, 120 BPM (one beat = 15 frames at 30 fps), A minor -> F major. Peak-normalised later. */
function music(sec) {
  const L = buf(sec), R = buf(sec);
  const add = (src, at, g, pan = 0) => {
    const o = Math.floor(at * SR);
    const gl = g * (1 - Math.max(0, pan)), gr = g * (1 + Math.min(0, pan));
    for (let i = 0; i < src.length && o + i < L.length; i++) { L[o + i] += src[i] * gl; R[o + i] += src[i] * gr; }
  };
  const pad = (freq, dur, amp, att = 1.2, rel = 1.5) => {
    const x = buf(dur + rel);
    for (let i = 0; i < x.length; i++) {
      const t = i / SR;
      const e = Math.min(1, t / att) * (t < dur ? 1 : Math.exp(-(t - dur) * (4 / rel)));
      let s = 0;
      for (const det of [-0.0035, 0, 0.0035]) for (let h = 1; h <= 5; h++) s += Math.sin(TAU * freq * (1 + det) * h * t) / (h * h * 0.6);
      x[i] = s * e * amp * 0.28;
    }
    return lowpass(x, 1400);
  };
  const pluck = (freq, dur, amp) => {
    const x = buf(dur);
    for (let i = 0; i < x.length; i++) {
      const t = i / SR;
      x[i] = amp * (Math.sin(TAU * freq * t) + 0.35 * Math.sin(TAU * freq * 2 * t)) * env(t, 0.004, 5.5);
    }
    return lowpass(x, 2400);
  };
  const beat = 0.5;
  const A1 = 55, F1 = 43.65, G1 = 49, E1 = 41.2;
  // A  0-3.2: dark swell
  add(pad(A1 * 2, 3.4, 1.0, 1.8), 0, 1);
  add(pad(110 * 1.5, 3.4, 0.7, 2.4), 0, 0.8, 0.3);
  add(sweptNoise(3.2, 200, 4000, 1.6, 5, (k) => Math.pow(k, 2.4) * 0.5), 0, 0.5);
  // B  3.2-10: pulsing 8th-note plucks, soft
  const bass = [A1, A1, F1, G1];
  for (let b = 0, t = 3.0; t < 14.0; b++, t += beat) {
    const root = bass[Math.floor(b / 4) % 4];
    add(pluck(root * 2, 0.4, 0.55), t, 1);
    if (b % 2 === 1) add(pluck(root * 4 * 1.5, 0.25, 0.18), t + beat / 2, 1, 0.4);
  }
  add(pad(110, 7.5, 0.8, 1.5), 3.2, 0.9, -0.2);
  add(pad(164.8, 7.5, 0.6, 1.5), 3.2, 0.8, 0.25);
  // C 10-14.8: tension - dissonant cluster, tremolo, heartbeat, riser
  add(pad(110, 5, 0.9, 1.5, 0.3), 10, 0.8);
  add(pad(116.5, 5, 0.6, 2.5, 0.3), 10.5, 0.7, 0.3);
  add(pad(82.4, 5, 0.9, 1.0, 0.3), 10, 0.9, -0.3);
  for (let t = 10.4; t < 14.7; t += 1.0 - (t - 10.4) * 0.11) {
    add(subBoom(0.35, 80, 48, 9), t, 0.8);
    add(subBoom(0.3, 80, 48, 10), t + 0.22, 0.5);
  }
  add(sweptNoise(3.4, 300, 6500, 2.0, 21, (k) => Math.pow(k, 2.6) * 0.8), 11.3, 0.55);
  // D 14.8-17: aftermath - a thin ringing tone and a sub tail
  add(bell(1568, 2.6, 0.12, 0.6, 2.0, 1.2), 14.85, 1, 0.3);
  add(pad(A1 * 2, 2.4, 0.8, 0.4, 1.2), 14.85, 0.7);
  // E 17-23: hopeful - Fmaj7 -> C -> Dm7 -> Am, bell arpeggios
  const prog = [[174.6, [349.2, 440, 523.3, 659.3]], [130.8, [261.6, 329.6, 392, 523.3]], [146.8, [293.7, 349.2, 440, 523.3]], [110, [220, 261.6, 329.6, 440]]];
  prog.forEach(([root, notes], c) => {
    const t0 = 16.9 + c * 1.55;
    add(pad(root, 1.7, 1.0, 0.5, 1.0), t0, 0.9);
    add(pad(root * 1.5, 1.7, 0.5, 0.6, 1.0), t0, 0.6, 0.3);
    notes.concat(notes.slice().reverse()).forEach((f, i) => add(bell(f * 2, 1.3, 0.2, 0.9, 3.5, 3.2), t0 + i * (beat / 2) * 0.75, 0.9, ((i % 2) - 0.5) * 0.6));
  });
  // F 23-27: resolution on F then A minor, long warm swell
  add(pad(174.6, 3.0, 1.0, 0.8, 1.6), 23.0, 1);
  add(pad(261.6, 3.0, 0.7, 1.0, 1.6), 23.0, 0.7, 0.3);
  add(pad(220, 4.2, 1.0, 1.2, 1.8), 25.4, 0.9);
  add(pad(329.6, 4.2, 0.6, 1.6, 1.8), 25.4, 0.7, -0.3);
  add(subBoom(3.4, 55, 55, 0.7), 23.0, 0.5);

  // sidechain-style ducking so the sound effects always sit on top
  const duck = (t) => {
    let g = 1;
    for (const [at, depth, hold, rec] of [[0, 0.5, 0.1, 1.2], [14.65, 1.0, 0.12, 0.9], [14.8, 0.4, 0.0, 1.0], [23.0, 0.35, 0.1, 0.8]]) {
      if (t >= at - 0.04 && t < at + hold) g *= 1 - depth;
      else if (t >= at + hold && t < at + hold + rec) g *= 1 - depth * Math.pow(1 - (t - at - hold) / rec, 2);
    }
    return g;
  };
  // gentle overall fade in at the start and out over the very end
  for (let i = 0; i < L.length; i++) {
    const t = i / SR;
    const g = duck(t) * Math.min(1, t / 0.25) * Math.min(1, (sec - t) / 1.8);
    L[i] *= g; R[i] *= g;
  }
  lowpass(L, 9000); lowpass(R, 9000);
  let m = 1e-9;
  for (let i = 0; i < L.length; i += 7) m = Math.max(m, Math.abs(L[i]), Math.abs(R[i]));
  const g = 0.55 / m;
  for (let i = 0; i < L.length; i++) { L[i] *= g; R[i] *= g; }
  return [L, R];
}

export function synthAll(dir) {
  fs.mkdirSync(dir, { recursive: true });
  const out = (name, x) => fs.writeFileSync(path.join(dir, name), x);
  out('move.wav', wav(knock({ base: 330 })));
  out('capture.wav', wav(knock({ base: 250, dur: 0.26, gain: 1.5, seed: 7 })));
  out('whoosh.wav', wav(whoosh(0.5, 250, 3200, 3)));
  out('swish.wav', wav(whoosh(0.8, 500, 5200, 9, 0.45)));
  out('riser.wav', wav(riser(1.4)));
  out('tick.wav', wav(norm(lowpass(knock({ base: 1900, dur: 0.07, gain: 0.7, seed: 4 }), 6000), 0.5)));
  out('hit_intro.wav', wav(hit({ sec: 2.4, sub0: 95, sub1: 38, subDecay: 2.2, noiseDecay: 14, noiseLp: 900, metal: 210, metalAmp: 0.12, tail: 2.2, mix: 0.4, seed: 31 })));
  out('impact.wav', wav(hit({ sec: 3.4, sub0: 110, sub1: 32, subDecay: 1.5, noiseDecay: 9, noiseLp: 2600, metal: 185, metalAmp: 0.32, tail: 2.6, mix: 0.5, seed: 77 })));
  out('fall1.wav', wav(norm(mixTwo(knock({ base: 118, dur: 0.5, gain: 1.4, seed: 5 }), lowpass(sweptNoise(0.45, 900, 300, 1.0, 8, (k) => Math.exp(-k * 6)), 2500)), 0.9)));
  out('fall2.wav', wav(norm(knock({ base: 150, dur: 0.35, gain: 1.1, seed: 6 }), 0.6)));
  out('brand.wav', wav(brand()));
  const [L, R] = music(27.2);
  out('music.wav', wav(L, R));
  console.log('audio synthesised in', dir);
}

function mixTwo(a, b) {
  const o = new Float32Array(Math.max(a.length, b.length));
  for (let i = 0; i < o.length; i++) o[i] = (a[i] ?? 0) + (b[i] ?? 0) * 0.35;
  return o;
}
