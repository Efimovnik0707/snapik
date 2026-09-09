// Собирает три автономных HTML из src/*.html, инлайня общий словарь copy.json.
// Запуск: node build.mjs   → dist/light.html, dist/dark.html, dist/editorial.html
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const copy = readFileSync(join(root, 'copy.json'), 'utf8');
JSON.parse(copy); // валидируем
const inline = JSON.stringify(JSON.parse(copy)).replace(/<\/script/gi, '<\/script');

for (const file of readdirSync(join(root, 'src')).filter(f => f.endsWith('.html'))) {
  const html = readFileSync(join(root, 'src', file), 'utf8');
  if (!html.includes('/*__COPY__*/')) throw new Error(`${file}: нет маркера /*__COPY__*/`);
  writeFileSync(join(root, 'dist', file), html.replace('/*__COPY__*/', inline), 'utf8');
  console.log('built', file);
}
