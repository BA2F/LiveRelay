// NODE_PATH must include the bundled workspace dependency node_modules directory.
const sharp = require('sharp');
const fs = require('node:fs/promises');
const path = require('node:path');
const root = __dirname;
async function exportPng(svg, output, n) {
  await fs.mkdir(path.dirname(path.join(root, output)), {recursive: true});
  await sharp(path.join(root, svg), {density: 300}).resize(n, n).ensureAlpha().png().toFile(path.join(root, output));
}
async function main() {
  for (const n of [16,24,32,48,64,128,256,512,1024]) {
    await exportPng(n <= 24 ? 'software/icon-square-micro.svg' : 'software/icon-square.svg', `software/png/icon-${n}.png`, n);
  }
  await exportPng('software/icon-square-dark.svg', 'software/png/icon-dark-1024.png', 1024);
  await exportPng('svg/mark-master.svg', 'qa/mark-master-512.png', 512);
  await exportPng('svg/mark-micro.svg', 'qa/mark-micro-512.png', 512);
  for (const [density, n] of [['mdpi',48],['hdpi',72],['xhdpi',96],['xxhdpi',144],['xxxhdpi',192]]) {
    await exportPng('software/icon-square.svg', `software/android/res/mipmap-${density}/ic_launcher.png`, n);
  }
  for (const n of [48,64,128,256]) {
    const dir = path.join(root, `software/linux/hicolor/${n}x${n}/apps`);
    await fs.mkdir(dir, {recursive:true});
    await fs.copyFile(path.join(root, `software/png/icon-${n}.png`), path.join(dir,'live-relay.png'));
  }
  const scalable = path.join(root,'software/linux/hicolor/scalable/apps');
  await fs.mkdir(scalable,{recursive:true});
  await fs.copyFile(path.join(root,'software/icon-square.svg'),path.join(scalable,'live-relay.svg'));
  console.log('Exported software PNGs, Android legacy densities, and Linux icons.');
}
main().catch(e => {console.error(e);process.exitCode = 1});
