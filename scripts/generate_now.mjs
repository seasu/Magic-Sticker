#!/usr/bin/env node
/**
 * 立即執行：用 Gemini 2.0 Flash 產生 6 種風格貓咪示意圖
 * node scripts/generate_now.mjs
 */

import { writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dir, '..', 'assets', 'images');
mkdirSync(OUT_DIR, { recursive: true });

const API_KEY = process.env.GEMINI_API_KEY;
if (!API_KEY) { console.error('❌ GEMINI_API_KEY not set'); process.exit(1); }

const BASE = [
  'A cute brown tabby cat with big sparkly eyes, raising one paw in a',
  'friendly waving gesture, smiling happily. LINE sticker.',
  'Square 512x512, centered subject, white or very light background.',
].join(' ');

const STYLES = {
  chibi: BASE + ' Style: chibi Q-version cartoon, thick black outlines, flat clean illustration, big round sparkly eyes, chubby adorable proportions, soft warm colors. Kawaii quality.',
  popArt: BASE + ' Style: Pop Art, bold vivid colors (bright pink yellow cyan), thick black outlines, flat color areas, Ben-Day dot shading, Andy Warhol / Roy Lichtenstein aesthetic.',
  pixel: BASE + ' Style: retro 8-bit pixel art, chunky visible pixels 8px grid, limited 12-color palette, no anti-aliasing, Nintendo SNES sprite aesthetic.',
  sketch: BASE + ' Style: pencil sketch, hand-drawn lines, crosshatching for shadows, monochrome sepia tones, rough expressive strokes.',
  watercolor: BASE + ' Style: soft watercolor painting, color washes bleeding at edges, translucent layered colors, paper texture, dreamy pastel pinks and oranges.',
  photo: BASE + ' Style: photo-realistic digital painting, detailed fur, natural lighting, professional portrait, vibrant natural colors.',
};

async function generate(styleKey, prompt) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-preview-image-generation:generateContent?key=${API_KEY}`;
  const body = {
    contents: [{ parts: [{ text: prompt }] }],
    generationConfig: { responseModalities: ['image'], temperature: 1.0 },
  };

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`HTTP ${res.status}: ${err.slice(0, 200)}`);
  }

  const data = await res.json();
  const parts = data?.candidates?.[0]?.content?.parts ?? [];
  for (const part of parts) {
    if (part.inlineData?.data) {
      return Buffer.from(part.inlineData.data, 'base64');
    }
  }
  throw new Error('No image in response: ' + JSON.stringify(data).slice(0, 200));
}

console.log('🐱 Generating 6 style preview images with Gemini...\n');
let ok = 0;
for (const [key, prompt] of Object.entries(STYLES)) {
  process.stdout.write(`  🎨 ${key}... `);
  try {
    const imgBuf = await generate(key, prompt);
    const outPath = join(OUT_DIR, `preview_${key}.png`);
    writeFileSync(outPath, imgBuf);
    console.log(`✅ ${Math.round(imgBuf.length / 1024)}KB`);
    ok++;
  } catch (e) {
    console.log(`❌ ${e.message}`);
  }
}
console.log(`\n✨ Done: ${ok}/${Object.keys(STYLES).length} images`);
console.log(`   Output: ${OUT_DIR}`);
