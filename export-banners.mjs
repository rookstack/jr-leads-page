import { chromium } from 'playwright';
import { resolve } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

const banners = [
  { file: 'qss-banner-300x250.html', out: 'qss-banner-300x250.jpg', w: 300, h: 250 },
  { file: 'qss-banner-320x50.html',  out: 'qss-banner-320x50.jpg',  w: 320, h: 50  },
  { file: 'qss-banner-336x280.html', out: 'qss-banner-336x280.jpg', w: 336, h: 280 },
  { file: 'qss-banner-728x90.html',  out: 'qss-banner-728x90.jpg',  w: 728, h: 90  },
];

const browser = await chromium.launch();

for (const { file, out, w, h } of banners) {
  const page = await browser.newPage();
  await page.setViewportSize({ width: w, height: h });
  const filePath = resolve(__dirname, file);
  await page.goto(`file://${filePath}`);
  // wait for animations to settle slightly
  await page.waitForTimeout(200);
  const outPath = resolve(__dirname, out);
  await page.screenshot({
    path: outPath,
    type: 'jpeg',
    quality: 92,
    clip: { x: 0, y: 0, width: w, height: h }
  });
  console.log(`✓ ${out} (${w}×${h})`);
  await page.close();
}

await browser.close();
console.log('All banners exported.');
