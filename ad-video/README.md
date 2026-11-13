# THE FINAL MOVE: 3D Chess cinematic ad (Remotion + three.js)

A 27-second, 30 fps cinematic advertisement for the 3D Chess Android app, rendered in genuine 3D from the game's own
Staunton GLB models and board (`../assets/models`, copied unmodified). Two native compositions: **vertical 1080x1920**
(Shorts/Reels/TikTok) and **landscape 1920x1080** (YouTube/website). They share one scene, but each has its own camera
distances, lens, safe areas and text layout; the vertical film is not a crop of the landscape one.

Brand **3D CHESS**. Tagline **Your Move. Your Victory.**

## Scenes

| # | Frames (30 fps) | Seconds | What happens |
| --- | --- | --- | --- |
| 1 The Hook | 0-96 | 0-3.2 | Macro of the white knight, rim-lit in warm gold on a dark set; the camera orbits and pulls out to reveal the board. "THIS ISN'T ORDINARY CHESS." A low impact lands on frame 0. |
| 2 The Battle | 96-300 | 3.2-10 | Plies 1-11 of a real game (Legal's mate): low-angle glide, overhead, tracking shot following the knight, close-ups on the knight and bishop captures, controlled orbit. One whoosh per cut, a piece knock when each piece lands. |
| 3 Checkmate | 300-510 | 10-17 | The black king steps away, a slow push-in, the knight's final move (Nd5#) decelerates as it lands. Frame 444: hold, impact, the king shudders and topples (shadowed spot-light, subtle red accent), "CHECKMATE". |
| 4 Gameplay | 510-690 | 17-23 | Light-sweep transition to a 3D smartphone. The app's menu and game screens, four callouts: play the computer (Stockfish on-device, 400-3200 Elo), 2 players on 1 phone, fully 3D board, orbit/zoom/top view. |
| 5 Branding | 690-810 | 23-27 | The real app icon, "3D CHESS" with a golden light sweep, tagline, PLAY NOW button, brand chime. |

### Chess correctness
`src/game.json` is the move list (Legal's mate, 13 plies: `e4 e5 Nf3 d6 Bc4 Bg4 Nc3 g6 Nxe5 Bxd1 Bxf7+ Ke7 Nd5#`).
`npm run check` runs `scripts/validate-chess.mjs` with chess.js: every ply is legal and played by the side to move,
there is no castling/en passant/promotion, the schedule is ordered, the last ply is genuine checkmate. `src/timeline.ts`
re-validates it while building the animation and refuses to start the king's fall unless the position is checkmate.
Pieces move on arcs that clear any piece standing in the way; captured pieces are lifted away and removed.

### Gameplay claims (verified against the Flutter source)
Only features that exist in `lib/` are advertised: play vs bot with a chosen Elo (`lib/ui/menu.dart`, Stockfish on device), two
players on one phone, fully 3D board with orbit/zoom and a top view (`lib/scene`, `lib/ui/hud.dart`). The menu also contains a
"2 players, 2 phones" option; the ad does not promote it. **No online matchmaking or store listing is claimed.**
**Screens are recreated, not screenshots**: the sandbox cannot run the Android emulator, so the menu and HUD are
rebuilt in HTML/CSS (`src/AppScreens.tsx`) with the app's colours, copy and layout from `lib/ui/theme.dart`, `menu.dart` and
`hud.dart`; the board inside the phone is the real 3D scene rendered live. Icons are redrawn as vectors (the app uses emoji).
To use real screenshots instead, put them in `public/` and swap the screen components in `src/Phone.tsx`.

## Code map

| Concern | File |
| --- | --- |
| Timing, shot list, scene boundaries | `src/scenes.ts`, `src/game.json` |
| Piece motion, arcs, king fall, sound cues | `src/timeline.ts` |
| Spline (Hermite) camera, aspect-aware framing | `src/camera.ts` |
| 3D stage: GLB loading gate, lights, shadows | `src/Stage.tsx` |
| Typography and effects | `src/Overlays.tsx`, `src/fonts.ts`, `src/layout.ts` |
| Phone + app screens | `src/Phone.tsx`, `src/AppScreens.tsx` |
| Final card | `src/Brand.tsx` |
| Audio placement on the timeline | `src/AudioTrack.tsx` |
| Synthesised audio | `scripts/synth-audio.mjs` |
| Asset preparation | `scripts/prepare-assets.mjs` |
| QA gate | `scripts/validate-video.mjs`, `scripts/validate-chess.mjs` |

Everything is a pure function of the Remotion frame (`useCurrentFrame`, `interpolate`, `spring`): no timers or wall-clock
state. Models and fonts are loaded behind `delayRender`, so no frame is captured before they are ready.
Archived v1 sources are in `legacy/v1/`.

## Render

```bash
cd ad-video
npm ci
npm run check            # types, chess legality + checkmate, audio provenance (run prepare-assets first for the audio check)
npm run render           # writes out/3d-chess-cinematic-v2-vertical.mp4 and ...-landscape.mp4
npm run validate         # ffprobe/ffmpeg quality gate, writes out/qa-frames
npm run studio           # live preview
```
Output: H.264 (yuv420p, CRF 18) + AAC 192 kbps in MP4. Needs Node 22 and Google Chrome (`CHROME_BIN`). Rendering uses
software WebGL: about 4 s per frame on 2 cores, so use GitHub Actions for the full render.

## GitHub Actions
**Actions -> Render ad video -> Run workflow** (`workflow_dispatch`). It checks out, sets up Node 22, `npm ci`, type-checks,
validates the chess, prepares assets, smoke-tests a frame of each format, renders both videos, runs the quality gate
(duration, resolution, fps, codec, audio, black and frozen frames, per-scene frame stats), uploads the MP4s and QA frames as
the artifact `3d-chess-cinematic-v2`, and publishes them to the pre-release tag `ad-video-v2`. If that release already exists
only its two video assets are replaced; no other release is touched. The Android workflow (`android-apk.yml`) is unchanged.

## Assets and licences
- **3D models, board, table, app icon**: the project's own files (`../assets`), unmodified.
- **Audio: 100 % original.** Every sound (piece knocks, captures, whooshes, riser, impacts, king fall, brand chime and the
  music bed) is synthesised by `scripts/synth-audio.mjs` (no samples, no recordings), so there is no third-party licence or
  attribution. It is released under the repository's licence. `scripts/check-no-thirdparty-audio.mjs` fails the workflow if any
  other audio file is in `public/sfx`. **The Team Fortress 2 stalemate sound from v1 is not used** (it remains in `assets/sfx` for
  the app history only; remove it before publishing the app; v1 is archived without it).
- **Fonts**: Cinzel and Inter, SIL Open Font License 1.1, via `@fontsource/cinzel` and `@fontsource/inter`, bundled locally.
- **Remotion**: free for individuals and small companies; check [its licence](https://www.remotion.dev/docs/license) for larger use.
- The end card has **no Google Play badge** because no listing is claimed. Add the official badge only when the app is live.

## Troubleshooting
- *Black or empty frames*: models still loading; raise `--timeout`, and confirm `npm run prepare-assets` copied 14 GLB files.
- *"concurrency higher than CPU cores"*: pass `--concurrency=<cores>`.
- *WebGL errors on a server*: keep `--gl=swangle` (set in `remotion.config.ts`) and set `CHROME_BIN` to a real Chrome.
- *Fonts look wrong*: run `npm run prepare-assets` so `public/fonts` exists.
- *Check failed on a move list edit*: run `node scripts/validate-chess.mjs`; the message names the illegal ply.
- *Restore v1*: see `legacy/v1/README.md`.
