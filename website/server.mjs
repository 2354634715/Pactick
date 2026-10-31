import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const files = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/index.html', ['index.html', 'text/html; charset=utf-8']],
  ['/index.en.html', ['index.en.html', 'text/html; charset=utf-8']],
  ['/styles.css', ['styles.css', 'text/css; charset=utf-8']],
  ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
  ['/assets/pactick-icon.png', ['assets/pactick-icon.png', 'image/png']],
]);

// 仅提供官网静态文件，不暴露仓库、配置或本地验证记录。
export function serve(port = 4187) {
  return new Promise((resolve, reject) => {
    const server = http.createServer((request, response) => {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        response.writeHead(405, { Allow: 'GET, HEAD' });
        response.end();
        return;
      }
      let pathname;
      try { pathname = new URL(request.url, 'http://127.0.0.1').pathname; }
      catch { response.writeHead(400); response.end(); return; }
      const entry = files.get(pathname);
      if (!entry) { response.writeHead(404); response.end('Not found'); return; }
      fs.readFile(path.join(directory, entry[0]), (error, data) => {
        if (error) { response.writeHead(500); response.end('Unable to read site file'); return; }
        response.writeHead(200, {
          'Content-Type': entry[1],
          'Content-Length': data.length,
          'Cache-Control': 'no-store',
          'X-Content-Type-Options': 'nosniff',
          'Referrer-Policy': 'strict-origin-when-cross-origin',
          'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
        });
        response.end(request.method === 'HEAD' ? undefined : data);
      });
    });
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => resolve(server));
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = process.argv[2] === undefined ? 4187 : Number(process.argv[2]);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    console.error('端口须为 0–65535 的整数；0 表示使用系统分配的端口。');
    process.exitCode = 1;
  } else {
    try {
      const server = await serve(port);
      console.log(`Pactick 官网本地预览：http://127.0.0.1:${server.address().port}`);
      console.log('仅监听本机。按 Ctrl+C 停止。');
    } catch (error) {
      console.error(error.code === 'EADDRINUSE' ? '端口已占用，请指定其他端口，例如 node website/server.mjs 4188。' : error.message);
      process.exitCode = 1;
    }
  }
}
