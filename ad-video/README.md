# 3D Chess promo video (Remotion)

Source of the app's ad. Everything is code, so it can be edited and re-rendered any time.

**Structure** (about 31 s): intro with logo and a short description -> a normal game (2 moves each) ->
checkmate scene (4 moves, mate, losing king thrown off the board, with the app's checkmate jingle) ->
stalemate scene (stalemate jingle) -> "Download on Google Play" end card. The board scenes show only the board and
pieces (no highlights or move list). The 3D models, icon and jingles are the game's own files from `../assets`.

| What to change | Where |
| --- | --- |
| Games shown (move lists, start position) | `src/scenes.ts` |
| Intro text / end card / timings | `src/Ad.tsx` (`INTRO`, `END`, texts) |
| Piece motion, king throw, sound timing | `src/timeline.ts` |
| Camera, lighting, board framing | `src/Board3D.tsx`, `useCam` in `src/Ad.tsx` |
| Sizes (1080x1920 and 1920x1080) | `src/Root.tsx` |

## Run

```bash
cd ad-video
npm install
npm run studio     # live preview and timeline editor
npm run render     # writes out/chess3d-ad-vertical.mp4 and out/chess3d-ad-landscape.mp4
```

Needs Node 22 and Google Chrome (set `CHROME_BIN` if Remotion cannot find it). Rendering uses software WebGL, so it is slow
on a laptop without a GPU (about 35 min per format on 2 cores). Or run the **Render ad video** workflow in GitHub Actions: it
renders both files and attaches them to a pre-release named `ad-video-<run number>`.

## Notes
- The stalemate jingle (`assets/sfx/stalemate.mp3`) is a Team Fortress 2 sound (Valve). Replace the file to publish the ad safely.
- The Google Play badge is a generic drawing without a link; add your real store link/name in `EndCard` when the listing exists.
- Remotion is free for individuals and small companies; check its licence for larger use.
