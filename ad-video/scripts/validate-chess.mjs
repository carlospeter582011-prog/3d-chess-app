// Static check of the advertisement's chess content (run in CI before rendering).
// Verifies with chess.js: every ply is legal and played by the side to move, no unsupported special moves,
// the schedule is ordered and non-overlapping, and the last ply is a genuine checkmate.
import fs from 'node:fs';
import { Chess } from 'chess.js';

const game = JSON.parse(fs.readFileSync(new URL('../src/game.json', import.meta.url), 'utf8'));
const chess = new Chess();
let prevEnd = -1;
const fail = (m) => { console.error('FAIL:', m); process.exit(1); };

game.plies.forEach((p, i) => {
  const side = chess.turn();
  let m;
  try { m = chess.move(p.san); } catch { fail(`ply ${i + 1} ${p.san} is illegal in ${chess.fen()}`); }
  if (m.color !== side) fail(`ply ${i + 1}: wrong side`);
  if (m.flags.match(/[ekqnb]/) && !m.flags.match(/^[cnb]*$/) ) { /* flags checked below */ }
  if (m.flags.includes('e') || m.flags.includes('k') || m.flags.includes('q') || m.promotion) fail(`ply ${i + 1} ${p.san} is a special move`);
  if (p.start < prevEnd) fail(`ply ${i + 1} starts at ${p.start} before the previous one lands at ${prevEnd}`);
  prevEnd = p.start + p.dur;
  console.log(`ok  ply ${String(i + 1).padStart(2)}  ${m.color} ${m.san.padEnd(6)} ${m.from}->${m.to}${m.captured ? ' x' + m.captured : ''}  frames ${p.start}-${prevEnd}`);
});
if (!chess.isCheckmate()) fail('final position is not checkmate');
const last = game.plies[game.plies.length - 1];
if (!last.final || last.san !== chess.history().at(-1)) fail('last ply is not flagged final');
if (chess.history().length !== game.plies.length) fail('history length mismatch');
console.log('ok  final position is checkmate, loser to move:', chess.turn() === 'b' ? 'black' : 'white');
console.log('    FEN', chess.fen());

const p = new Chess();
for (const san of game.phonePlies) p.move(san);
console.log('ok  phone demo plies are legal:', game.phonePlies.join(' '));
console.log('Chess validation passed.');
