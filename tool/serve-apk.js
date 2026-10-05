// =====================================================================
//  pi 远程 —— APK 局域网分发服务
//
//  双击同目录的 serve-apk.cmd 即可启动；手机浏览器打开提示的地址就能
//  下载安装包，不需要数据线，也不经过微信/网盘。
//
//  注意：仅在可信局域网内临时使用，用完 Ctrl+C 关掉。
// =====================================================================

const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 8899;
const ROOT = path.resolve(__dirname, '..', 'build', 'app', 'outputs', 'flutter-apk');

function localIPv4() {
  const out = [];
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] ?? []) {
      if (net.family === 'IPv4' && !net.internal) out.push(net.address);
    }
  }
  return out;
}

function human(bytes) {
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + ' KB';
  return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}

const server = http.createServer((req, res) => {
  let rel = decodeURIComponent((req.url ?? '/').split('?')[0]);
  if (rel === '/' || rel === '') rel = '/app-debug.apk';
  const target = path.join(ROOT, rel.replace(/^\//, ''));

  // 目录穿越防护
  if (!target.startsWith(ROOT)) {
    res.writeHead(403).end('forbidden');
    return;
  }

  let stat;
  try {
    stat = fs.statSync(target);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('未找到文件：' + rel);
    return;
  }
  if (!stat.isFile()) {
    res.writeHead(404).end('not a file');
    return;
  }

  console.log(`  ↓ ${req.socket.remoteAddress} 拉取 ${path.basename(target)} (${human(stat.size)})`);

  res.writeHead(200, {
    'Content-Type': 'application/vnd.android.package-archive',
    'Content-Length': String(stat.size),
    'Content-Disposition': `attachment; filename="${path.basename(target)}"`,
  });
  fs.createReadStream(target).pipe(res);
});

server.listen(PORT, '0.0.0.0', () => {
  const ips = localIPv4();
  console.log('');
  console.log('  pi 远程 —— APK 分发已启动');
  console.log('  ============================================');
  if (ips.length === 0) {
    console.log('  未检测到局域网 IP，请确认已连 WiFi/网线');
  }
  for (const ip of ips) {
    console.log(`  APK 下载地址：  http://${ip}:${PORT}/app-debug.apk`);
  }
  console.log('');
  console.log('  手机连同一个 WiFi，用浏览器打开上面地址');
  console.log('  按 Ctrl+C 停止服务');
  console.log('');
});
