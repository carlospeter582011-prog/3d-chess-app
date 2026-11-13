// The film's chess content, timing and camera plan.
//   Scene 1  The Hook         0 -  96   hero white knight close-up, pull-out reveal of the board
//   Scene 2  The Battle      96 - 300   Legal's mate, plies 1-11, five different shots
//   Scene 3  Checkmate      300 - 510   tension, Nd5#, impact, the king falls, "CHECKMATE"
//   Scene 4  Gameplay       510 - 690   the app on a 3D phone
//   Scene 5  Final branding 690 - 810   icon, wordmark, tagline, PLAY NOW
import game from './game.json';
import { K, Shot } from './camera';
import { buildAuto, buildFromPlies, idOfSquare, PlySpec } from './timeline';

export const T = { hook: 0, battle: 96, mate: 300, phone: 510, brand: 690, end: 810 } as const;
export const TOTAL_FRAMES = T.end;
export const MATE_FRAME = 444;

export const mainScene = buildFromPlies(game.plies as PlySpec[], { fallDir: [0, -1] });
if (mainScene.mate?.start !== MATE_FRAME) throw new Error(`mate expected at frame ${MATE_FRAME}, got ${mainScene.mate?.start}`);
if (mainScene.total > T.phone) throw new Error('main scene runs into the gameplay reveal');

/** The demo shown on the phone: the opening of the same game, paced like the app. */
export const phoneScene = buildAuto(game.phonePlies, { lead: 30, pauseMs: 450 });

const hero = idOfSquare(mainScene, 'b1'); // the white knight that delivers mate
const knightG1 = idOfSquare(mainScene, 'g1');
const bishopC8 = idOfSquare(mainScene, 'c8');
const kingE8 = idOfSquare(mainScene, 'e8');

export const shots: Shot[] = [
  // 1. HOOK: macro of the hero knight (rim-lit), orbiting out over the board to a wide reveal
  {
    from: 0, to: 96, pr: 1.5, pf: 1.0, follow: hero,
    keys: [
      K(0, 1.6, -150, 75, [-2.5, 1.1, 3.5], 25, 1, 0.8),
      K(34, 3.2, -100, 66, [-2.5, 1.1, 3.3], 29, 0.8, 0.6),
      K(68, 7.8, -34, 60, [-1.2, 0.9, 2.6], 32, 0),
      K(96, 11.5, 14, 55, [0, 0.6, 0.9], 32, 0),
    ],
  },
  // 2a. low-angle glide between the pieces (plies 1-4)
  {
    from: 96, to: 154, pr: 1.6, pf: 1.0,
    keys: [K(96, 8.4, -36, 83, [0, 0.9, 0.5], 34), K(125, 8.2, -20, 84, [0, 0.9, 0.2], 34), K(154, 7.8, -6, 83, [0.2, 0.9, 0], 34)],
  },
  // 2b. smooth overhead (plies 5-6)
  {
    from: 154, to: 190, pr: 1.0, pf: 1.75,
    keys: [K(154, 16, -10, 16, [0, 0.4, 0.3], 34), K(190, 16, 22, 12, [0, 0.4, 0.1], 34)],
  },
  // 2c. tracking shot following the knight (ply 7 Nc3, then the g-pawn)
  {
    from: 190, to: 226, pr: 1.7, pf: 1.0, follow: hero,
    keys: [K(190, 4.6, 58, 74, [-2.5, 1, 3], 30, 1, 0.55), K(208, 5.2, 28, 70, [-1.5, 1, 1.5], 30, 1, 0.55), K(226, 6.4, 6, 66, [-1.4, 0.9, 1.3], 30, 0.8, 0.5)],
  },
  // 2d. close-ups of the moving pieces (Nxe5, Bxd1)
  {
    from: 226, to: 248, pr: 1.25, pf: 1.0, follow: knightG1,
    keys: [K(226, 4.4, 32, 70, [0, 1, 1], 30, 1, 0.5), K(248, 4.0, 8, 72, [0, 1, 1], 30, 1, 0.5)],
  },
  {
    from: 248, to: 276, pr: 1.3, pf: 1.0, follow: bishopC8,
    keys: [K(248, 4.6, -52, 68, [1.5, 1, 0], 30, 1, 0.5), K(276, 5.2, -22, 64, [0, 1, 1], 30, 0.6, 0.5)],
  },
  // 2e. controlled orbit (Bxf7+: check)
  {
    from: 276, to: 300, pr: 1.9, pf: 1.0,
    keys: [K(276, 9.4, -44, 52, [0.4, 0.7, -1.2], 32), K(300, 9.0, -12, 50, [0.5, 0.8, -2.1], 32)],
  },
  // 3a. close on the king as it steps away (Ke7)
  {
    from: 300, to: 336, pr: 1.3, pf: 1.0, follow: kingE8,
    keys: [K(300, 3.8, -30, 76, [0.5, 1.1, -3], 30, 1, 0.55), K(336, 4.2, -14, 74, [0.5, 1.1, -2.6], 30, 1, 0.5)],
  },
  // 3b. slow push-in: tension builds between the knight on c3 and the king on e7
  {
    from: 336, to: 374, pr: 1.5, pf: 1.0,
    keys: [K(336, 8.6, 18, 74, [-0.2, 0.9, -0.2], 32), K(374, 6.0, 12, 72, [0.1, 1.0, -1.2], 30)],
  },
  // 3c. tracking the winning knight, decelerating with it, until it lands on d5 and the board holds
  {
    from: 374, to: 444, pr: 1.5, pf: 1.0, follow: hero,
    keys: [
      K(374, 5.0, 40, 72, [-1.5, 1, 1.5], 30, 1, 0.55),
      K(410, 5.4, 22, 70, [-0.6, 1, 0], 30, 0.7, 0.55),
      K(444, 5.8, 10, 68, [0, 1.7, -2], 30, 0),
    ],
  },
  // 3d. the pause (frames 444-456 are held), then a slow push towards the fallen king
  {
    from: 444, to: 510, pr: 1.45, pf: 1.0,
    keys: [
      K(444, 5.8, 10, 68, [0, 1.7, -2], 30),
      K(456, 5.8, 10, 68, [0, 1.7, -2], 30),
      K(482, 5.4, -30, 64, [0.3, 1.5, -2.6], 30),
      K(510, 4.9, -42, 62, [0.3, 1.2, -3.0], 30),
    ],
  },
];

export const MATE_SOUND_FRAME = MATE_FRAME;
