import { Config } from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);
// WebGL in headless Chrome without a GPU (CI and cloud machines)
Config.setChromiumOpenGlRenderer('swangle');
if (process.env.CHROME_BIN) Config.setBrowserExecutable(process.env.CHROME_BIN);
