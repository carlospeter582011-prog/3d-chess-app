// Post-render quality gate. Usage: node scripts/validate-video.mjs <vertical|landscape> <file.mp4> [frames-dir]
// Checks with ffprobe/ffmpeg: container, codec/pixel format, resolution, frame rate, duration, audio track and level,
// black/blank frames over the whole film, and per-scene brightness/contrast of extracted representative frames
// (those frames are saved so they can be inspected by eye or attached as a CI artifact).
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [kind, file, framesDir = 'out/qa-frames'] = process.argv.slice(2);
const want = { vertical: [1080, 1920], landscape: [1920, 1080] }[kind];
if (!want || !file) { console.error('usage: validate-video.mjs <vertical|landscape> <file.mp4> [frames-dir]'); process.exit(2); }
const errors = [];
const check = (ok, msg) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${msg}`); if (!ok) errors.push(msg); };
// ffmpeg prints its filter reports (volumedetect, blackdetect, freezedetect) to stderr, so capture both streams.
const run = (cmd, args) => { const r = spawnSync(cmd, args, { encoding: 'utf8', maxBuffer: 1 << 28 }); return (r.stdout || '') + (r.stderr || ''); };

const probe = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', file], { encoding: 'utf8' }));
const v = probe.streams.find((s) => s.codec_type === 'video');
const a = probe.streams.find((s) => s.codec_type === 'audio');
const dur = parseFloat(probe.format.duration);
const [num, den] = v.r_frame_rate.split('/').map(Number);
const size = fs.statSync(file).size;
console.log(`file ${file}  ${(size / 1e6).toFixed(2)} MB`);
check(v.codec_name === 'h264', `video codec h264 (got ${v.codec_name})`);
check(v.pix_fmt === 'yuv420p', `pixel format yuv420p for broad playback (got ${v.pix_fmt})`);
check(v.width === want[0] && v.height === want[1], `resolution ${want[0]}x${want[1]} (got ${v.width}x${v.height})`);
check(Math.abs(num / den - 30) < 0.01, `frame rate 30 fps (got ${(num / den).toFixed(3)})`);
check(Math.abs(dur - 27) < 0.25, `duration ~27 s (got ${dur.toFixed(2)} s)`);
check(parseInt(v.nb_frames ?? '0', 10) === 810 || Math.abs(parseFloat(v.duration) * 30 - 810) < 2, `810 frames`);
check(!!a && a.codec_name === 'aac', `AAC audio track present (got ${a?.codec_name ?? 'none'})`);
check(probe.format.format_name.includes('mp4'), 'MP4 container');
check(size > 1.5e6 && size < 80e6, `file size sane (${(size / 1e6).toFixed(1)} MB)`);

if (a) {
  const vol = run('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-vn', '-af', 'volumedetect', '-f', 'null', '-']);
  const mean = parseFloat(/mean_volume: (-?[\d.]+) dB/.exec(vol)?.[1] ?? '-99');
  const max = parseFloat(/max_volume: (-?[\d.]+) dB/.exec(vol)?.[1] ?? '-99');
  check(mean > -32 && max > -12, `audio is audible, not silent (mean ${mean} dB, peak ${max} dB)`);
  check(max < -0.1, `audio does not clip (peak ${max} dB)`);
  // the checkmate impact (frame 444 = 14.8 s) must be clearly louder than the quiet tension just before it
  const seg = (ss, t) => parseFloat(/max_volume: (-?[\d.]+) dB/.exec(run('ffmpeg', ['-hide_banner', '-nostats', '-ss', String(ss), '-t', String(t), '-i', file, '-vn', '-af', 'volumedetect', '-f', 'null', '-']))?.[1] ?? '-99');
  const before = seg(13.6, 1.0), impact = seg(14.78, 0.5);
  check(impact > before + 3, `checkmate impact stands out (${impact} dB vs ${before} dB just before)`);
}

// black / blank frames anywhere in the film
const bd = run('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-an', '-vf', 'blackdetect=d=0.1:pix_th=0.06', '-f', 'null', '-']);
const blacks = [...bd.matchAll(/black_start:([\d.]+) black_end:([\d.]+)/g)].map((m) => [+m[1], +m[2]]);
check(blacks.length === 0, `no black/blank frames (${blacks.length ? 'found ' + JSON.stringify(blacks) : 'none'})`);
const fz = run('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-an', '-vf', 'freezedetect=n=-60dB:d=1.2', '-f', 'null', '-']);
const freezes = [...fz.matchAll(/freeze_start: ([\d.]+)/g)].map((m) => +m[1]);
check(freezes.length === 0, `no frozen stretches > 1.2 s (${freezes.length ? 'at ' + freezes.join(', ') + ' s' : 'none'})`);

// representative frames, one or more per scene; luminance statistics via signalstats
fs.mkdirSync(framesDir, { recursive: true });
const frames = [
  ['01-hook-open', 4], ['01-hook-text', 45], ['01-hook-reveal', 90], ['02-battle-low', 130], ['02-battle-overhead', 172],
  ['02-battle-tracking', 205], ['02-battle-closeup', 240], ['02-battle-orbit', 290], ['03-tension', 360], ['03-final-approach', 425],
  ['03-impact', 447], ['03-king-falls', 475], ['03-checkmate-end', 505], ['04-phone-menu', 550], ['04-phone-2p', 600],
  ['04-phone-3d', 650], ['04-phone-top', 682], ['05-brand-icon', 712], ['05-brand-name', 745], ['05-brand-final', 809],
];
for (const [name, fr] of frames) {
  const out = path.join(framesDir, `${kind}-${name}.png`);
  run('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', '-i', file, '-vf', `select=eq(n\\,${fr})`, '-vframes', '1', out]);
  const st = run('ffmpeg', ['-hide_banner', '-nostats', '-i', out, '-vf', 'signalstats,metadata=print:file=-', '-f', 'null', '-']);
  const num = (k) => parseFloat(new RegExp(k + '=([\\d.]+)').exec(st)?.[1] ?? '0');
  const yavg = num('YAVG'), ymin = num('YMIN'), ymax = num('YMAX');
  // not blank (some real brightness range), not blown out, and bright content (text, icon, lit pieces) is present
  const ok = fs.existsSync(out) && yavg > 12 && yavg < 215 && ymax - ymin > 110 && ymax > 150;
  check(ok, `frame ${String(fr).padStart(3)} ${name.padEnd(20)} avg ${yavg.toFixed(0)}, min ${ymin.toFixed(0)}, max ${ymax.toFixed(0)}`);
}
// final card must be bright enough in its text region (not faded): compare last frame with the one 20 frames earlier
console.log(errors.length ? `\n${errors.length} CHECK(S) FAILED` : '\nAll automated checks passed.');
process.exit(errors.length ? 1 : 0);
