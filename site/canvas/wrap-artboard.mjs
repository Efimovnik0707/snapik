// Оборачивает статический дамп страницы (после рендера в браузере) в артборд .dc.html для design-канваса.
// Использование: node wrap-artboard.mjs <dump.html> <Out.dc.html>
import { readFileSync, writeFileSync } from 'node:fs';
const [,, input, output] = process.argv;
let html = readFileSync(input, 'utf8');
html = html.replace(/<script\b[\s\S]*?<\/script>/gi, '');
const head = (html.match(/<head[\s\S]*?<\/head>/i) || [''])[0];
const links = [...head.matchAll(/<link[^>]+rel=["'](?:stylesheet|preconnect)["'][^>]*>/gi)].map(m => m[0]).join('\n');
const styles = [...head.matchAll(/<style\b[\s\S]*?<\/style>/gi)].map(m => m[0]).join('\n');
const bodyMatch = html.match(/<body([^>]*)>([\s\S]*)<\/body>/i);
const bodyAttrs = bodyMatch ? bodyMatch[1] : '';
let body = bodyMatch ? bodyMatch[2] : html;
body = body.replace(/<style\b[\s\S]*?<\/style>/gi, s => { return s; });
const cls = (bodyAttrs.match(/class=["']([^"']*)["']/) || [,''])[1];
const out = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
${links}
${styles}
<style>a{color:inherit}a:hover{color:inherit}</style>
</helmet>
<div class="${cls}" style="position:relative;width:1440px;min-height:900px;overflow:hidden">
${body}
</div>
</x-dc>
</body>
</html>
`;
writeFileSync(output, out, 'utf8');
console.log('wrote', output, Math.round(out.length/1024)+'KB');
