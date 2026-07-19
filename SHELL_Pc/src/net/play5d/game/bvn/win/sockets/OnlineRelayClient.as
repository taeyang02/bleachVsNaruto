/*
 * Copyright (C) 2021-2024, 5DPLAY Game Studio
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

package net.play5d.game.bvn.win.sockets {
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.net.Socket;
import flash.utils.ByteArray;
import flash.utils.Endian;

import net.play5d.game.bvn.win.data.HostVO;
import net.play5d.game.bvn.win.data.OnlineConfig;
import net.play5d.game.bvn.win.sockets.events.SocketEvent;
import net.play5d.game.bvn.win.sockets.udp.UDPDataVO;
import net.play5d.game.bvn.win.sockets.udp.UdpDataType;

/**
 * Online relay client.
 *
 * Connects both host and guest as TCP clients to the relay server,
 * then tunnels LAN GAME_TCP / GAME_UDP traffic through it.
 */
public class OnlineRelayClient extends EventDispatcher {
    public static const TYPE_CONTROL:int  = 1;
    public static const TYPE_GAME_TCP:int = 2;
    public static const TYPE_GAME_UDP:int = 3;

    private static var _i:OnlineRelayClient;

    public static function get I():OnlineRelayClient {
        _i ||= new OnlineRelayClient();
        return _i;
    }

    public function OnlineRelayClient() {
        _packetBuffer = new PacketBuffer();
    }

    public var isConnected:Boolean;
    public var isPaired:Boolean;
    public var roomCode:String;
    public var role:String; // 'host' | 'guest'

    /** Function(cmd:Object):void */
    public var onControl:Function;
    /** Function(e:SocketEvent):void — same shape as LAN TCP receive */
    public var onGameTcp:Function;
    /** Function(d:UDPDataVO):void */
    public var onGameUdp:Function;
    /** Function(reason:String):void */
    public var onPeerLeft:Function;

    private var _socket:Socket;
    private var _buf:ByteArray;
    private var _packetBuffer:PacketBuffer;
    private var _pendingCreateBack:Function;
    private var _pendingJoinBack:Function;
    private var _connectBack:Function;
    private var _connectFail:Function;

    public function connect(back:Function = null, fail:Function = null):void {
        OnlineConfig.load();
        _connectBack = back;
        _connectFail = fail;

        close(false);

        _socket = new Socket();
        _socket.endian = Endian.BIG_ENDIAN;
        _socket.addEventListener(Event.CONNECT, onConnect);
        _socket.addEventListener(Event.CLOSE, onClose);
        _socket.addEventListener(IOErrorEvent.IO_ERROR, onError);
        _socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
        _socket.addEventListener(ProgressEvent.SOCKET_DATA, onData);

        _buf = new ByteArray();
        _buf.endian = Endian.BIG_ENDIAN;
        isPaired = false;
        roomCode = null;
        role     = null;

        try {
            _socket.connect(OnlineConfig.host, OnlineConfig.port);
        }
        catch (e:Error) {
            failConnect(e.message);
        }
    }

    public function close(notify:Boolean = true):void {
        isConnected = false;
        isPaired    = false;
        if (_packetBuffer) {
            _packetBuffer.clear();
        }
        if (_socket) {
            try {
                _socket.removeEventListener(Event.CONNECT, onConnect);
                _socket.removeEventListener(Event.CLOSE, onClose);
                _socket.removeEventListener(IOErrorEvent.IO_ERROR, onError);
                _socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
                _socket.removeEventListener(ProgressEvent.SOCKET_DATA, onData);
                if (_socket.connected) {
                    _socket.close();
                }
            }
            catch (e:Error) {
            }
            _socket = null;
        }
        _buf = null;
        _pendingCreateBack = null;
        _pendingJoinBack   = null;
    }

    public function createRoom(host:HostVO, back:Function, fail:Function = null):void {
        role               = 'host';
        _pendingCreateBack = function (ok:Boolean, data:Object):void {
            if (ok) {
                if (back != null) {
                    back(data);
                }
            }
            else if (fail != null) {
                fail(data ? data.msg : 'create failed');
            }
        };
        sendControl({
                        cmd : 'CREATE',
                        host: {
                            ownerName: host.ownerName,
                            name     : host.name,
                            password : host.password,
                            gameMode : host.gameMode,
                            status   : host.status
                        },
                        name: host.ownerName
                    });
    }

    public function joinRoom(code:String, playerName:String, back:Function, fail:Function = null):void {
        role             = 'guest';
        _pendingJoinBack = function (ok:Boolean, data:Object):void {
            if (ok) {
                if (back != null) {
                    back(data);
                }
            }
            else if (fail != null) {
                fail(data ? data.msg : 'join failed');
            }
        };
        sendControl({
                        cmd     : 'JOIN',
                        roomCode: code,
                        name    : playerName
                    });
    }

    public function sendControl(obj:Object):void {
        var bytes:ByteArray = new ByteArray();
        bytes.writeUTFBytes(JSON.stringify(obj));
        sendFrame(TYPE_CONTROL, bytes);
    }

    /**
     * Send game TCP payload (same encoding as SocketClient / SocketServer).
     */
    public function sendGameTcp(msg:Object):void {
        var bytes:ByteArray;
        if (msg is ByteArray) {
            bytes = PacketUtils.addByteArrayHead(msg as ByteArray);
        }
        else {
            bytes = PacketUtils.createByteArrayWithHead(msg);
        }
        if (!bytes) {
            return;
        }
        PacketUtils.compress(bytes);
        // createByteArrayWithHead already set position 0; ensure we send full buffer
        var payload:ByteArray = new ByteArray();
        bytes.position        = 0;
        payload.writeBytes(bytes, 0, bytes.length);
        sendFrame(TYPE_GAME_TCP, payload);
    }

    public function sendGameTcpJson(obj:Object):void {
        sendGameTcp(JSON.stringify(obj));
    }

    /**
     * Send game UDP payload (same encoding as UDPSocket.send).
     */
    public function sendGameUdp(msg:Object):void {
        var bytes:ByteArray = new ByteArray();
        if (msg is String) {
            bytes.writeByte(1);
            bytes.writeUTFBytes(msg as String);
        }
        else if (msg is ByteArray) {
            bytes.writeByte(2);
            var ba:ByteArray = msg as ByteArray;
            var pos:uint     = ba.position;
            ba.position      = 0;
            bytes.writeBytes(ba, 0, ba.length);
            ba.position      = pos;
        }
        else {
            bytes.writeByte(3);
            bytes.writeObject(msg);
        }
        sendFrame(TYPE_GAME_UDP, bytes);
    }

    private function sendFrame(type:int, payload:ByteArray):void {
        if (!_socket || !_socket.connected) {
            return;
        }
        payload.position = 0;
        var len:int      = 1 + payload.length;
        try {
            _socket.writeShort(len);
            _socket.writeByte(type);
            _socket.writeBytes(payload, 0, payload.length);
            _socket.flush();
        }
        catch (e:Error) {
            trace('OnlineRelayClient.sendFrame', e);
        }
    }

    private function onConnect(e:Event):void {
        isConnected = true;
        if (_connectBack != null) {
            var cb:Function = _connectBack;
            _connectBack    = null;
            cb();
        }
        dispatchEvent(new SocketEvent(SocketEvent.CLIENT_CONNECT));
    }

    private function onClose(e:Event):void {
        var wasConnected:Boolean = isConnected;
        isConnected = false;
        isPaired    = false;
        if (wasConnected) {
            dispatchEvent(new SocketEvent(SocketEvent.CLOSE));
            if (onPeerLeft != null) {
                onPeerLeft('disconnect');
            }
        }
    }

    private function onError(e:Event):void {
        failConnect(e.toString());
    }

    private function failConnect(msg:String):void {
        isConnected = false;
        if (_connectFail != null) {
            var f:Function = _connectFail;
            _connectFail   = null;
            f(msg);
        }
        var se:SocketEvent = new SocketEvent(SocketEvent.ERROR);
        se.error           = msg;
        dispatchEvent(se);
    }

    private function onData(e:ProgressEvent):void {
        if (!_buf) {
            _buf = new ByteArray();
            _buf.endian = Endian.BIG_ENDIAN;
        }
        _socket.readBytes(_buf, _buf.length);

        _buf.position = 0;
        while (_buf.bytesAvailable >= 2) {
            var startPos:uint = _buf.position;
            var len:uint      = _buf.readUnsignedShort();
            if (len < 1) {
                break;
            }
            if (_buf.bytesAvailable < len) {
                _buf.position = startPos;
                break;
            }
            var type:int          = _buf.readUnsignedByte();
            var payload:ByteArray = new ByteArray();
            _buf.readBytes(payload, 0, len - 1);
            payload.position = 0;
            handleFrame(type, payload);
        }

        // keep remainder
        if (_buf.bytesAvailable > 0) {
            var rest:ByteArray = new ByteArray();
            rest.endian        = Endian.BIG_ENDIAN;
            _buf.readBytes(rest, 0, _buf.bytesAvailable);
            _buf = rest;
        }
        else {
            _buf = new ByteArray();
            _buf.endian = Endian.BIG_ENDIAN;
        }
    }

    private function handleFrame(type:int, payload:ByteArray):void {
        switch (type) {
        case TYPE_CONTROL:
            handleControl(payload.readUTFBytes(payload.bytesAvailable));
            break;
        case TYPE_GAME_TCP:
            dispatchGameTcp(payload);
            break;
        case TYPE_GAME_UDP:
            dispatchGameUdp(payload);
            break;
        }
    }

    private function handleControl(jsonStr:String):void {
        var msg:Object;
        try {
            msg = JSON.parse(jsonStr);
        }
        catch (e:Error) {
            return;
        }

        switch (msg.cmd) {
        case 'CREATE_OK':
            roomCode = msg.roomCode;
            if (_pendingCreateBack != null) {
                var cb:Function    = _pendingCreateBack;
                _pendingCreateBack = null;
                cb(true, msg);
            }
            break;
        case 'JOIN_OK':
            roomCode = msg.roomCode;
            if (_pendingJoinBack != null) {
                var jb:Function  = _pendingJoinBack;
                _pendingJoinBack = null;
                jb(true, msg);
            }
            break;
        case 'PEER_READY':
            isPaired = true;
            break;
        case 'ERROR':
            if (_pendingCreateBack != null) {
                var cf:Function    = _pendingCreateBack;
                _pendingCreateBack = null;
                cf(false, msg);
            }
            if (_pendingJoinBack != null) {
                var jf:Function  = _pendingJoinBack;
                _pendingJoinBack = null;
                jf(false, msg);
            }
            break;
        case 'PEER_LEFT':
            isPaired = false;
            if (onPeerLeft != null) {
                onPeerLeft(msg.reason || 'peer left');
            }
            break;
        }

        if (onControl != null) {
            onControl(msg);
        }
    }

    private function dispatchGameTcp(payload:ByteArray):void {
        PacketUtils.uncompress(payload);
        _packetBuffer.push(payload);
        var packets:Array = _packetBuffer.getPackets();
        for each(var data:ByteArray in packets) {
            var se:SocketEvent = new SocketEvent(SocketEvent.RECEIVE_DATA);
            se.data            = data;
            if (onGameTcp != null) {
                onGameTcp(se);
            }
            dispatchEvent(se);
        }
    }

    private function dispatchGameUdp(payload:ByteArray):void {
        var data:UDPDataVO = new UDPDataVO();
        data.fromIP        = 'relay';
        data.fromPort      = 0;

        var type:int = payload.readByte();
        switch (type) {
        case 1:
            data.dataType = UdpDataType.STRING;
            data.setData(payload.readUTFBytes(payload.bytesAvailable));
            break;
        case 2:
            data.dataType = UdpDataType.BYTEARRAY;
            var tmp:ByteArray = new ByteArray();
            tmp.writeBytes(payload, payload.position, payload.bytesAvailable);
            tmp.position = 0;
            data.setData(tmp);
            break;
        case 3:
            data.dataType = UdpDataType.OBJECT;
            data.setData(payload.readObject());
            break;
        }

        if (onGameUdp != null) {
            onGameUdp(data);
        }
    }

}
}
