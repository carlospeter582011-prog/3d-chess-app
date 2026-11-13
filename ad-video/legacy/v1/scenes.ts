// The game positions shown in the ad. Edit the move lists to show different games.
import { buildScene } from './timeline';

// (not used in the current cut) a normal opening, 2 moves each, at the app's normal speed; add it back in Ad.tsx if wanted
export const playScene = buildScene({ sans: ['e4', 'e5', 'Nf3', 'Nc6'], lead: 25, tail: 45, pauseMs: 650 });

// 2) four moves, then checkmate (1.e4 f6 2.d4 g5 3.Qh5#): the losing king is thrown
export const mateScene = buildScene({ sans: ['e4', 'f6', 'd4', 'g5', 'Qh5#'], ending: 'mate', lead: 20, tail: 50, pauseMs: 550 });

// 3) a stalemate: nobody wins, the position just freezes (white Qg6, black Kh8 has no move)
export const staleScene = buildScene({
  fen: '7k/8/5K2/8/8/8/8/6Q1 w - - 0 1',
  sans: ['Ke7', 'Kh7', 'Kf8', 'Kh8', 'Qg6'],
  ending: 'stalemate',
  lead: 20,
  tail: 80,
  pauseMs: 550,
});
