/**
 * BleachVsNaruto Online Relay Server
 *
 * Host creates a room → gets a 6-char room code.
 * Guest joins with that code.
 * Server relays GAME_TCP / GAME_UDP payloads between the two players.
 *
 * Protocol frame:
 *   [uint16 BE length][uint8 type][payload]
 *   type 1 = CONTROL (UTF-8 JSON)
 *   type 2 = GAME_TCP (opaque LAN TCP packet)
 *   type 3 = GAME_UDP (opaque LAN UDP packet)
 *
 * Env:
 *   PORT      - listen port (default 17511)
 *   HOST      - bind address (default 0.0.0.0)
 *   ROOM_TTL  - idle room TTL ms (default 30 min)
 */

'use strict';

const net = require('net');
const crypto = require('crypto');

const PORT = parseInt(process.env.PORT || '17511', 10);
const HOST = process.env.HOST || '0.0.0.0';
const ROOM_TTL = parseInt(process.env.ROOM_TTL || String(30 * 60 * 1000), 10);

const TYPE_CONTROL = 1;
const TYPE_GAME_TCP = 2;
const TYPE_GAME_UDP = 3;

/** @type {Map<string, Room>} */
const rooms = new Map();

/**
 * @typedef {Object} Room
 * @property {string} code
 * @property {net.Socket} host
 * @property {net.Socket|null} guest
 * @property {object|null} hostInfo
 * @property {number} createdAt
 * @property {boolean} paired
 */

function log(...args) {
  const ts = new Date().toISOString();
  console.log(`[${ts}]`, ...args);
}

function generateRoomCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += alphabet[crypto.randomInt(0, alphabet.length)];
  }
  if (rooms.has(code)) {
    return generateRoomCode();
  }
  return code;
}

function sendFrame(socket, type, payloadBuf) {
  if (!socket || socket.destroyed) {
    return;
  }
  const len = 1 + payloadBuf.length;
  const header = Buffer.alloc(2);
  header.writeUInt16BE(len, 0);
  const typeBuf = Buffer.from([type]);
  try {
    socket.write(Buffer.concat([header, typeBuf, payloadBuf]));
  } catch (e) {
    log('sendFrame error', e.message);
  }
}

function sendControl(socket, obj) {
  sendFrame(socket, TYPE_CONTROL, Buffer.from(JSON.stringify(obj), 'utf8'));
}

function destroyRoom(code, reason) {
  const room = rooms.get(code);
  if (!room) {
    return;
  }
  rooms.delete(code);
  log(`room ${code} destroyed: ${reason}`);

  const peers = [room.host, room.guest].filter(Boolean);
  for (const s of peers) {
    if (!s.destroyed) {
      sendControl(s, { cmd: 'PEER_LEFT', reason: reason || 'peer left' });
      try {
        s.end();
      } catch (_) {}
    }
  }
}

function findRoomBySocket(socket) {
  for (const room of rooms.values()) {
    if (room.host === socket || room.guest === socket) {
      return room;
    }
  }
  return null;
}

function getPeer(room, socket) {
  if (room.host === socket) {
    return room.guest;
  }
  if (room.guest === socket) {
    return room.host;
  }
  return null;
}

function handleControl(socket, jsonStr) {
  let msg;
  try {
    msg = JSON.parse(jsonStr);
  } catch (e) {
    sendControl(socket, { cmd: 'ERROR', msg: 'invalid json' });
    return;
  }

  const cmd = msg && msg.cmd;
  switch (cmd) {
    case 'CREATE': {
      if (socket._roomCode) {
        sendControl(socket, { cmd: 'ERROR', msg: 'already in a room' });
        return;
      }
      const code = generateRoomCode();
      /** @type {Room} */
      const room = {
        code,
        host: socket,
        guest: null,
        hostInfo: msg.host || {},
        createdAt: Date.now(),
        paired: false
      };
      rooms.set(code, room);
      socket._roomCode = code;
      socket._role = 'host';
      sendControl(socket, {
        cmd: 'CREATE_OK',
        roomCode: code,
        host: room.hostInfo
      });
      log(`room ${code} created by ${socket.remoteAddress}`);
      break;
    }
    case 'JOIN': {
      const code = String(msg.roomCode || '')
        .trim()
        .toUpperCase();
      const room = rooms.get(code);
      if (!room) {
        sendControl(socket, { cmd: 'ERROR', msg: 'room not found' });
        return;
      }
      if (room.guest) {
        sendControl(socket, { cmd: 'ERROR', msg: 'room is full' });
        return;
      }
      if (room.host === socket) {
        sendControl(socket, { cmd: 'ERROR', msg: 'cannot join own room' });
        return;
      }
      room.guest = socket;
      room.paired = true;
      socket._roomCode = code;
      socket._role = 'guest';
      sendControl(socket, {
        cmd: 'JOIN_OK',
        roomCode: code,
        host: room.hostInfo
      });
      sendControl(room.host, {
        cmd: 'PEER_READY',
        roomCode: code,
        guestName: msg.name || 'guest'
      });
      sendControl(socket, {
        cmd: 'PEER_READY',
        roomCode: code
      });
      log(`room ${code} paired (${socket.remoteAddress})`);
      break;
    }
    case 'PING': {
      sendControl(socket, { cmd: 'PONG', t: msg.t || Date.now() });
      break;
    }
    default:
      sendControl(socket, { cmd: 'ERROR', msg: 'unknown cmd: ' + cmd });
  }
}

function handleFrame(socket, type, payload) {
  if (type === TYPE_CONTROL) {
    handleControl(socket, payload.toString('utf8'));
    return;
  }

  if (type !== TYPE_GAME_TCP && type !== TYPE_GAME_UDP) {
    return;
  }

  const room = findRoomBySocket(socket);
  if (!room || !room.paired) {
    return;
  }
  const peer = getPeer(room, socket);
  if (!peer) {
    return;
  }
  sendFrame(peer, type, payload);
}

function attachSocket(socket) {
  socket.setNoDelay(true);
  socket.setKeepAlive(true, 15000);
  socket._buf = Buffer.alloc(0);
  socket._roomCode = null;
  socket._role = null;

  log(`connect ${socket.remoteAddress}:${socket.remotePort}`);

  socket.on('data', (chunk) => {
    socket._buf = Buffer.concat([socket._buf, chunk]);
    while (socket._buf.length >= 2) {
      const len = socket._buf.readUInt16BE(0);
      if (len < 1 || len > 1024 * 1024) {
        log('invalid frame length', len);
        socket.destroy();
        return;
      }
      if (socket._buf.length < 2 + len) {
        break;
      }
      const frame = socket._buf.slice(2, 2 + len);
      socket._buf = socket._buf.slice(2 + len);
      const type = frame[0];
      const payload = frame.slice(1);
      try {
        handleFrame(socket, type, payload);
      } catch (e) {
        log('handleFrame error', e);
      }
    }
  });

  socket.on('close', () => {
    log(`close ${socket.remoteAddress}:${socket.remotePort}`);
    const code = socket._roomCode;
    if (code) {
      destroyRoom(code, 'disconnect');
    }
  });

  socket.on('error', (err) => {
    log(`socket error ${socket.remoteAddress}:`, err.message);
  });
}

function cleanupIdleRooms() {
  const now = Date.now();
  for (const [code, room] of rooms) {
    if (!room.paired && now - room.createdAt > ROOM_TTL) {
      destroyRoom(code, 'idle timeout');
    }
  }
}

const server = net.createServer(attachSocket);
server.listen(PORT, HOST, () => {
  log(`BVN online relay listening on ${HOST}:${PORT}`);
});

setInterval(cleanupIdleRooms, 60 * 1000);

process.on('SIGINT', () => {
  log('shutting down');
  server.close();
  process.exit(0);
});
