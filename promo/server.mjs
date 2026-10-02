import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const directory = path.dirname(fileURLToPath(import.meta.url));
const project = path.resolve(directory, '..');
const mime = { '.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.ttf':'font/ttf', '.mp4':'video/mp4', '.png':'image/png', '.wav':'audio/wav', '.json':'application/json; charset=utf-8' };

export function serve(port = 4173) {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    let file;
    if (url.pathname === '/font/NotoSansSC-VF.ttf') {
      file = process.env.PACTICK_CJK_FONT || 'C:/Windows/Fonts/NotoSansSC-VF.ttf';
    } else {
      const isOutput = url.pathname.startsWith('/output/pactick-promo-swiss/');
      const base = isOutput ? path.join(project, 'output/pactick-promo-swiss') : directory;
      const requested = isOutput ? url.pathname.slice('/output/pactick-promo-swiss'.length) : url.pathname;
      file = path.resolve(base, '.' + decodeURIComponent(requested === '/' ? '/index.html' : requested));
      if (!file.startsWith(base + path.sep)) { res.writeHead(403); res.end(); return; }
    }
    fs.stat(file, (err, stat) => {
      if (err || !stat.isFile()) { res.writeHead(404); res.end('File not found'); return; }
      res.setHeader('Content-Type', mime[path.extname(file)] || 'application/octet-stream');
      res.setHeader('Cache-Control', 'no-store');
      const range = req.headers.range;
      if (range) {
        const match = /^bytes=(\d+)-(\d*)$/.exec(range);
        if (!match) { res.writeHead(416); res.end(); return; }
        const start = Number(match[1]), end = Math.min(match[2] ? Number(match[2]) : stat.size - 1, stat.size - 1);
        if (start > end || start >= stat.size) { res.writeHead(416); res.end(); return; }
        res.writeHead(206, { 'Content-Range': `bytes ${start}-${end}/${stat.size}`, 'Accept-Ranges':'bytes', 'Content-Length':end-start+1 });
        fs.createReadStream(file, { start, end }).pipe(res);
      } else {
        res.writeHead(200, { 'Content-Length': stat.size, 'Accept-Ranges':'bytes' });
        fs.createReadStream(file).pipe(res);
      }
    });
  });
  return new Promise((resolve, reject) => { server.on('error', reject); server.listen(port, '127.0.0.1', () => resolve(server)); });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = await serve(Number(process.argv[2] || 4173));
  console.log(`Pactick film: http://127.0.0.1:${server.address().port}`);
}
