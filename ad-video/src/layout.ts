import { useVideoConfig } from 'remotion';

/** Aspect-aware layout numbers. `u` is the short side; safe areas keep text clear of Shorts/Reels/TikTok UI. */
export function useLayout() {
  const { width, height } = useVideoConfig();
  const portrait = height > width;
  const u = Math.min(width, height);
  const safe = portrait
    ? { top: height * 0.1, bottom: height * 0.2, side: width * 0.07 }
    : { top: height * 0.07, bottom: height * 0.08, side: width * 0.06 };
  return { width, height, portrait, u, safe };
}
