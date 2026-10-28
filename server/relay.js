#!/usr/bin/env node
/**
 * PolyForge: Ops — 公网中继服务器
 * ================================
 * 零依赖单文件，Node.js >= 16 直接跑：  node relay.js --port 8080
 *
 * 作用：
 *   - 房间配对：一个 host + 若干 client
 *   - 二进制转发：客户端 ↔ 房主，房主权威
 *   - HTTP `/rooms` 返回公开房间列表（游戏内 UI 直接读）
 *   - `/health` 给探活/Docker/K8s 用
 *
 * 拓扑：
 *   client ──ws──┐
 *   client ──ws──┼── relay ──ws── host(权威模拟)
 *   client ──ws──┘
 *
 * 帧格式（与游戏端 scripts/net/transport_relay.gd 完全一致）：
 *   客户端 → 中继 : 0x01 | u16(to) | payload
 *   中继 → 对端   : 0x02 | u16(from) | payload
 *   控制帧        : 0x10 | utf8 JSON
 */
'use strict';

const http = require('http');
const crypto = require('crypto');

const argv = process.argv.slice(2);
const arg = (name, dflt) => {
  const i = argv.indexOf('--' + name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};

const PORT = parseInt(arg('port', process.env.PORT || '8080'), 10);
const HOST = arg('host', '0.0.0.0');
const MAX_ROOM = parseInt(arg('max-room', '16'), 10);
const IDLE_MS = parseInt(arg('idle', '90000'), 10);
const VERBOSE = argv.includes('--verbose');

const MAGIC = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

// ---------------------------------------------------------------- 房间表
/** @type {Map<string, {code:string, host:Conn|null, clients:Set<Conn>, created:number, meta:object}>} */
const rooms = new Map();
let nextId = 1;

class Conn {
  constructor(socket, room, name, role) {
    this.socket = socket;
    this.room = room;
    this.name = name || 'Player';
    this.role = role === 'host' ? 'host' : 'client';
    this.id = 0;            // host = 0，client 由房间分配
    this.alive = true;
    this.buf = Buffer.alloc(0);
    this.frag = [];
    this.fragOp = 0;
    this.lastSeen = Date.now();
    this.bytesIn = 0;
    this.bytesOut = 0;
  }

  send(buf) {
    if (!this.alive) return;
    try {
      this.socket.write(encodeFrame(buf));
      this.bytesOut += buf.length;
    } catch (e) {
      this.close('write error');
    }
  }

  sendControl(obj) {
    const json = Buffer.from(JSON.stringify(obj), 'utf8');
    const out = Buffer.allocUnsafe(1 + json.length);
    out[0] = 0x10;
    json.copy(out, 1);
    this.send(out);
  }

  close(reason) {
    if (!this.alive) return;
    this.alive = false;
    try { this.socket.end(); } catch (e) {}
    leave(this, reason);
  }
}

function getRoom(code, create) {
  let r = rooms.get(code);
  if (!r && create) {
    r = { code, host: null, clients: new Set(), created: Date.now(), meta: {} };
    rooms.set(code, r);
    log(`room ${code} created`);
  }
  return r;
}

function roomInfo(r) {
  return {
    code: r.code,
    players: (r.host ? 1 : 0) + r.clients.size,
    max: MAX_ROOM,
    mode: r.meta.mode || '',
    map: r.meta.map || '',
    host: r.host ? r.host.name : '',
    age: Math.floor((Date.now() - r.created) / 1000),
  };
}

function leave(conn, reason) {
  const r = conn.room;
  if (!r) return;
  if (conn.role === 'host' && r.host === conn) {
    r.host = null;
    // 房主掉线：通知所有客户端并解散
    for (const c of r.clients) {
      c.sendControl({ t: 'error', msg: 'host left' });
      c.close('host left');
    }
    r.clients.clear();
    rooms.delete(r.code);
    log(`room ${r.code} closed (host left: ${reason})`);
    return;
  }
  if (r.clients.delete(conn)) {
    if (r.host && r.host.alive) {
      r.host.sendControl({ t: 'peer_leave', id: conn.id, reason: reason || '' });
    }
    for (const c of r.clients) c.sendControl({ t: 'peer_leave', id: conn.id, reason: '' });
    log(`room ${r.code} client ${conn.id} left (${reason})`);
    if (!r.host && r.clients.size === 0) rooms.delete(r.code);
  }
}

// ---------------------------------------------------------------- WebSocket 编解码
function encodeFrame(payload) {
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.allocUnsafe(2);
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.allocUnsafe(4);
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.allocUnsafe(10);
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  header[0] = 0x82; // FIN + binary
  return Buffer.concat([header, payload]);
}

function tryParse(conn) {
  const b = conn.buf;
  if (b.length < 2) return null;
  const fin = (b[0] & 0x80) !== 0;
  const opcode = b[0] & 0x0f;
  const masked = (b[1] & 0x80) !== 0;
  let len = b[1] & 0x7f;
  let off = 2;
  if (len === 126) {
    if (b.length < 4) return null;
    len = b.readUInt16BE(2);
    off = 4;
  } else if (len === 127) {
    if (b.length < 10) return null;
    const big = b.readBigUInt64BE(2);
    if (big > 8n * 1024n * 1024n) { conn.close('frame too big'); return null; }
    len = Number(big);
    off = 10;
  }
  const maskLen = masked ? 4 : 0;
  if (b.length < off + maskLen + len) return null;
  let payload = b.subarray(off + maskLen, off + maskLen + len);
  if (masked) {
    const mask = b.subarray(off, off + 4);
    payload = Buffer.from(payload);
    for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
  }
  conn.buf = b.subarray(off + maskLen + len);
  return { fin, opcode, payload };
}

function onData(conn, frame) {
  const { fin, opcode, payload } = frame;
  if (opcode === 0x8) { conn.close('close frame'); return; }
  if (opcode === 0x9) { // ping → pong
    const h = Buffer.allocUnsafe(2);
    h[0] = 0x8a; h[1] = payload.length;
    try { conn.socket.write(Buffer.concat([h, payload])); } catch (e) {}
    return;
  }
  if (opcode === 0xa) return;
  if (opcode === 0x0) {
    conn.frag.push(payload);
    if (fin) {
      const whole = Buffer.concat(conn.frag);
      conn.frag = [];
      handleMessage(conn, conn.fragOp, whole);
    }
    return;
  }
  if (!fin) {
    conn.frag = [payload];
    conn.fragOp = opcode;
    return;
  }
  handleMessage(conn, opcode, payload);
}

function handleMessage(conn, opcode, buf) {
  conn.lastSeen = Date.now();
  conn.bytesIn += buf.length;
  if (opcode === 0x1) { // 文本：只接受控制 JSON
    try {
      const o = JSON.parse(buf.toString('utf8'));
      handleControl(conn, o);
    } catch (e) {}
    return;
  }
  if (buf.length < 1) return;
  const kind = buf[0];
  if (kind === 0x10) {
    try {
      handleControl(conn, JSON.parse(buf.subarray(1).toString('utf8')));
    } catch (e) {}
    return;
  }
  if (kind !== 0x01) return;
  if (buf.length < 3) return;
  const to = buf.readUInt16BE(1);
  const payload = buf.subarray(3);
  const r = conn.room;
  if (!r) return;
  const out = Buffer.allocUnsafe(3 + payload.length);
  out[0] = 0x02;
  out.writeUInt16BE(conn.id, 1);
  payload.copy(out, 3);
  if (conn.role === 'client') {
    if (r.host && r.host.alive) r.host.send(out);
  } else {
    if (to === 0xffff) {
      for (const c of r.clients) c.send(out);
    } else {
      for (const c of r.clients) if (c.id === to) { c.send(out); break; }
    }
  }
}

function handleControl(conn, o) {
  const r = conn.room;
  if (!r) return;
  switch (o.t) {
    case 'ping':
      conn.sendControl({ t: 'pong', ts: o.ts || 0 });
      break;
    case 'meta':
      r.meta = { mode: o.mode || r.meta.mode, map: o.map || r.meta.map };
      break;
    case 'chat':
      if (r.host && r.host.alive) {
        r.host.sendControl({ t: 'chat', from: conn.name, text: String(o.text || '').slice(0, 200) });
      }
      break;
    default:
      break;
  }
}

// ---------------------------------------------------------------- 升级握手
const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (url.pathname === '/rooms') {
    const list = [];
    for (const r of rooms.values()) {
      if (r.host) list.push(roomInfo(r));
    }
    res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*' });
    res.end(JSON.stringify(list));
    return;
  }
  if (url.pathname === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, rooms: rooms.size, uptime: process.uptime() }));
    return;
  }
  if (url.pathname === '/' || url.pathname === '/index.html') {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(statusPage());
    return;
  }
  res.writeHead(404);
  res.end('not found');
});

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (url.pathname !== '/ws') {
    socket.destroy();
    return;
  }
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }
  const accept = crypto.createHash('sha1').update(key + MAGIC).digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${accept}\r\n` +
    '\r\n'
  );
  socket.setNoDelay(true);

  const code = (url.searchParams.get('room') || 'LOBBY').toUpperCase().slice(0, 12);
  const role = url.searchParams.get('role') === 'host' ? 'host' : 'client';
  const name = (url.searchParams.get('name') || 'Player').slice(0, 16);
  const ver = parseInt(url.searchParams.get('v') || '2', 10);

  if (ver !== 2) {
    socket.end();
    return;
  }

  const room = getRoom(code, true);
  const conn = new Conn(socket, room, name, role);

  if (role === 'host') {
    if (room.host && room.host.alive) {
      // 顶掉旧房主（重连场景）
      room.host.close('replaced');
    }
    conn.id = 0;
    room.host = conn;
  } else {
    if (!room.host) {
      conn.sendControl({ t: 'error', msg: 'no host in room' });
      conn.alive = false;
      socket.end();
      rooms.delete(code);
      return;
    }
    if (room.clients.size + 1 >= MAX_ROOM) {
      conn.sendControl({ t: 'error', msg: 'room full' });
      conn.alive = false;
      socket.end();
      return;
    }
    conn.id = nextId++;
    if (conn.id > 0xffff) nextId = 1;
    room.clients.add(conn);
  }

  conn.sendControl({ t: 'welcome', id: conn.id, room: code, role });
  if (role === 'client') {
    room.host.sendControl({ t: 'peer_join', id: conn.id, name });
    for (const c of room.clients) {
      if (c !== conn) c.sendControl({ t: 'peer_join', id: conn.id, name });
    }
  } else {
    for (const c of room.clients) c.sendControl({ t: 'peer_join', id: 0, name });
  }
  log(`room ${code}: ${role} "${name}" joined (id=${conn.id}), clients=${room.clients.size}`);

  if (head && head.length) conn.buf = Buffer.from(head);
  socket.on('data', (chunk) => {
    conn.buf = Buffer.concat([conn.buf, chunk]);
    let f;
    while ((f = tryParse(conn))) {
      onData(conn, f);
      if (!conn.alive) break;
    }
  });
  socket.on('error', () => conn.close('socket error'));
  socket.on('close', () => conn.close('socket closed'));
  socket.on('end', () => conn.close('socket end'));
});

// 空闲连接清理
setInterval(() => {
  const now = Date.now();
  for (const r of rooms.values()) {
    for (const c of r.clients) if (now - c.lastSeen > IDLE_MS) c.close('idle');
    if (r.host && now - r.host.lastSeen > IDLE_MS) r.host.close('idle');
    if (!r.host && r.clients.size === 0) rooms.delete(r.code);
  }
}, 15000).unref();

function statusPage() {
  const list = [];
  for (const r of rooms.values()) {
    if (r.host) list.push(roomInfo(r));
  }
  const rows = list.map((r) =>
    `<tr><td>${r.code}</td><td>${r.host}</td><td>${r.players}/${r.max}</td><td>${r.mode}</td><td>${r.map}</td><td>${r.age}s</td></tr>`
  ).join('') || '<tr><td colspan="6" class="muted">暂无房间</td></tr>';
  return `<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PolyForge Relay</title>
<style>
body{margin:0;background:#0b0e14;color:#dfe6f2;font:14px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif}
.wrap{max-width:900px;margin:0 auto;padding:40px 20px}
h1{font-size:22px;letter-spacing:.06em;color:#ffd83d;margin:0 0 4px}
.muted{color:#7a8699}
table{width:100%;border-collapse:collapse;margin-top:20px}
th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #1b2432}
th{color:#8ea0bb;font-weight:500;font-size:12px;letter-spacing:.08em;text-transform:uppercase}
code{background:#141a24;padding:2px 6px;border-radius:4px;color:#7ddc8f}
</style></head><body><div class="wrap">
<h1>POLYFORGE RELAY</h1>
<div class="muted">在线中继 · 房间 ${list.length} 个 · 运行 ${Math.floor(process.uptime())}s</div>
<table><thead><tr><th>房间码</th><th>房主</th><th>人数</th><th>模式</th><th>地图</th><th>存活</th></tr></thead>
<tbody>${rows}</tbody></table>
<p class="muted" style="margin-top:24px">游戏内填写 <code>ws://本机地址:${PORT}</code> 即可加入。</p>
</div></body></html>`;
}

function log(s) {
  if (VERBOSE) console.log(`[relay] ${s}`);
}

server.listen(PORT, HOST, () => {
  console.log(`[relay] PolyForge relay listening on ws://${HOST}:${PORT}/ws`);
  console.log(`[relay] rooms: http://${HOST}:${PORT}/rooms   health: /health`);
});
