#!/usr/bin/env node
/**
 * 建立 6 張風格佔位 PNG（純色背景）
 * 之後可執行 GitHub Actions: .github/workflows/generate_previews.yml
 * 用 GEMINI_API_KEY 替換為真實 AI 生成圖
 */

import { writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { deflateSync } from 'zlib';

const __dir = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dir, '..', 'assets', 'images');
mkdirSync(OUT_DIR, { recursive: true });

function crc32(buf) {
  let crc = 0xFFFFFFFF;
  for (const b of buf) {
    crc ^= b;
    for (let j = 0; j < 8; j++) crc = (crc & 1) ? (0xEDB88320 ^ (crc >>> 1)) : (crc >>> 1);
  }
  return (crc ^ 0xFFFFFFFF);
}

function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const t = Buffer.from(type);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])) >>> 0);
  return Buffer.concat([len, t, data, crc]);
}

function createPNG(r, g, b) {
  const W = 256, H = 256;
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4);
  ihdr[8] = 8; ihdr[9] = 2;

  const raw = Buffer.alloc((1 + W * 3) * H);
  for (let y = 0; y < H; y++) {
    const off = y * (1 + W * 3); raw[off] = 0;
    for (let x = 0; x < W; x++) {
      raw[off + 1 + x * 3] = r;
      raw[off + 2 + x * 3] = g;
      raw[off + 3 + x * 3] = b;
    }
  }

  const compressed = deflateSync(raw, { level: 1 });
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', compressed), chunk('IEND', Buffer.alloc(0))]);
}

// 每種風格的代表色
const COLORS = {
  chibi:      [255, 230, 220],  // 溫暖粉
  popArt:     [255, 220,  50],  // 鮮黃
  pixel:      [100, 200, 255],  // 像素藍
  sketch:     [220, 215, 205],  // 米白
  watercolor: [200, 235, 255],  // 淡藍水彩
  photo:      [230, 230, 230],  // 淺灰
};

for (const [key, [r, g, b]] of Object.entries(COLORS)) {
  const png = createPNG(r, g, b);
  const outPath = join(OUT_DIR, `preview_${key}.png`);
  writeFileSync(outPath, png);
  console.log(`✅ placeholder created: preview_${key}.png (${r},${g},${b})`);
}
console.log('\n📝 Run GitHub Actions: generate_previews.yml to replace with AI images');
