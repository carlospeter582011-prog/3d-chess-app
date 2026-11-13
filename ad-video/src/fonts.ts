// Bundled open-licence fonts (SIL OFL 1.1, from @fontsource, copied to public/fonts by scripts/prepare-assets.mjs),
// so rendering never depends on fonts installed on the machine. Remotion waits for them before every frame.
import { continueRender, delayRender, staticFile } from 'remotion';

export const SERIF = 'Cinzel, "Times New Roman", serif';
export const SANS = 'Inter, "Segoe UI", Roboto, Arial, sans-serif';

const FACES: [string, string, string][] = [
  ['Cinzel', '600', 'cinzel-latin-600-normal.woff2'],
  ['Cinzel', '700', 'cinzel-latin-700-normal.woff2'],
  ['Cinzel', '900', 'cinzel-latin-900-normal.woff2'],
  ['Inter', '400', 'inter-latin-400-normal.woff2'],
  ['Inter', '500', 'inter-latin-500-normal.woff2'],
  ['Inter', '600', 'inter-latin-600-normal.woff2'],
  ['Inter', '700', 'inter-latin-700-normal.woff2'],
  ['Inter', '800', 'inter-latin-800-normal.woff2'],
];

let started = false;
if (typeof document !== 'undefined' && !started) {
  started = true;
  const handle = delayRender('loading fonts', { timeoutInMilliseconds: 60000 });
  Promise.all(
    FACES.map(async ([family, weight, file]) => {
      const face = new FontFace(family, `url(${staticFile('fonts/' + file)}) format('woff2')`, { weight });
      await face.load();
      document.fonts.add(face);
    }),
  )
    .then(() => continueRender(handle))
    .catch((e) => { console.error('font load failed', e); continueRender(handle); });
}
