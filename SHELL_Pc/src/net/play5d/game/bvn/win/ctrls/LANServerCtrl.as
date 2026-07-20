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

package net.play5d.game.bvn.win.ctrls {
import flash.net.Socket;
import flash.events.TimerEvent;
import flash.utils.Timer;
import flash.utils.clearTimeout;
import flash.utils.getTimer;
import flash.utils.setTimeout;

import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.ctrler.game_ctrls.GameCtrl;
import net.play5d.game.bvn.data.vos.GameRunDataVO;
import net.play5d.game.bvn.events.GameEvent;
import net.play5d.game.bvn.fighter.FighterMain;
import net.play5d.game.bvn.input.GameInputer;
import net.play5d.game.bvn.interfaces.GameInterface;
import net.play5d.game.bvn.stage.GameStage;
import net.play5d.game.bvn.stage.LoadingStage;
import net.play5d.game.bvn.stage.SelectFighterStage;
import net.play5d.game.bvn.ui.GameUI;
import net.play5d.game.bvn.win.data.ClientVO;
import net.play5d.game.bvn.win.data.HostVO;
import net.play5d.game.bvn.win.input.InputManager;
import net.play5d.game.bvn.win.sockets.OnlineRelayClient;
import net.play5d.game.bvn.win.sockets.SocketServer;
import net.play5d.game.bvn.win.sockets.events.SocketEvent;
import net.play5d.game.bvn.win.sockets.udp.UDPDataVO;
import net.play5d.game.bvn.win.sockets.udp.UDPSocket;
import net.play5d.game.bvn.win.utils.JsonUtils;
import net.play5d.game.bvn.win.utils.LANUtils;
import net.play5d.game.bvn.win.utils.LanPingHUD;
import net.play5d.game.bvn.win.utils.LanSyncType;
import net.play5d.game.bvn.win.utils.LockFrameLogic;
import net.play5d.game.bvn.win.utils.MsgType;
import net.play5d.game.bvn.win.utils.SocketMsgFactory;
import net.play5d.game.bvn.win.views.lan.LANGameState;
import net.play5d.game.bvn.win.views.lan.LANRoomState;

public class LANServerCtrl {
    private static var _i:LANServerCtrl;

    public static function get I():LANServerCtrl {
        _i ||= new LANServerCtrl();
        return _i;
    }

    public function LANServerCtrl() {
    }
    public var active:Boolean;
    public var onPlayerJoinSuccess:Function;
    /** Online: called with roomCode after CREATE_OK */
    public var onOnlineRoomCreated:Function;
    public var onOnlineRoomFailed:Function;
    private var _room:LANRoomState;
    private var _clientK:int;
    private var _serverK:int;
    private var _clients:Vector.<ClientVO> = new Vector.<ClientVO>();
    private var _udpClientMap:Object       = {};
    /**
     * 运行帧数
     */
    private var _renderFrame:uint;
    private var _renderFrameClient:uint;

    private var _renderNextFrame:uint;

    private var _renderSyncFrame:int;

    private var _sendUpdateFrame:int;

    private var _selectLogic:SelectFighterServerLogic;
    private var _connGameLogic:LockFrameServerLogic;

    private var _udpSocket:UDPSocket;
    private var _kickTimeoutInt:int;

    private var _host:HostVO;
    private var _pingTimer:Timer;

    public function get host():HostVO {
        return _host;
    }

    public function setRoom(v:LANRoomState):void {
        _room = v;
        _room.setStartAble(false);
    }

    public function startServer(host:HostVO):void {
        _host = host;
        if (LANGameCtrl.I.isOnline) {
            startOnlineServer(host);
            return;
        }

        SocketServer.I.bind(LANGameCtrl.PORT_TCP);
        SocketServer.I.addEventListener(SocketEvent.CLIENT_CONNECT, socketHandler);
        SocketServer.I.addEventListener(SocketEvent.CLIENT_DIS_CONNECT, socketHandler);
        SocketServer.I.addEventListener(SocketEvent.RECEIVE_DATA, tcpDataHandler);

        _udpSocket = new UDPSocket();
        _udpSocket.listen(LANGameCtrl.PORT_UDP_SERVER);
        _udpSocket.addDataHandler(udpDataHandler);

    }

    public function startOnlineServer(host:HostVO):void {
        _host           = host;
        _clients        = new Vector.<ClientVO>();
        _onlineClosing  = false;

        var relay:OnlineRelayClient = OnlineRelayClient.I;
        relay.onGameTcp  = tcpDataHandler;
        relay.onGameUdp  = udpDataHandler;
        relay.onPeerLeft = onOnlinePeerLeft;

        relay.connect(function ():void {
            relay.createRoom(host, function (data:Object):void {
                _host.roomCode = data.roomCode;
                if (onOnlineRoomCreated != null) {
                    onOnlineRoomCreated(data.roomCode);
                }
            }, function (msg:String):void {
                if (onOnlineRoomFailed != null) {
                    onOnlineRoomFailed(msg);
                }
                else {
                    GameUI.alert('ERROR', msg || 'Failed to create room');
                }
            });
        }, function (err:String):void {
            if (onOnlineRoomFailed != null) {
                onOnlineRoomFailed(err);
            }
            else {
                GameUI.alert('ERROR', 'Cannot connect to online server: ' + (err || ''));
            }
        });
    }

    public function stopServer():void {
        stopPing();
        _host = null;
        if (LANGameCtrl.I.isOnline) {
            var relay:OnlineRelayClient = OnlineRelayClient.I;
            relay.onGameTcp  = null;
            relay.onGameUdp  = null;
            relay.onPeerLeft = null;
            relay.close();
        }
        else {
            SocketServer.I.close();
            SocketServer.I.removeEventListener(SocketEvent.CLIENT_CONNECT, socketHandler);
            SocketServer.I.removeEventListener(SocketEvent.CLIENT_DIS_CONNECT, socketHandler);
            SocketServer.I.removeEventListener(SocketEvent.RECEIVE_DATA, tcpDataHandler);

            if (_udpSocket) {
                _udpSocket.unListen();
                _udpSocket.removeDataHandler(udpDataHandler);
                _udpSocket = null;
            }
        }

        if (_selectLogic) {
            _selectLogic.dispose();
            _selectLogic = null;
        }
        if (_connGameLogic) {
            _connGameLogic.dispose();
            _connGameLogic = null;
        }

        _clients = new Vector.<ClientVO>();
        _room    = null;
        _host    = null;
    }

    public function sendChart(chart:String, name:String = null):void {
        sendClientsChart(chart, name);
        if (_room) {
            _room.pushChart(chart, name);
        }
    }

    public function sendStart():void {
        var msg:Object = SocketMsgFactory.createStartGame();
        for each(var i:ClientVO in _clients) {
            sendJsonToClient(i, msg);
        }
        if (_room) {
            _room.startGameTimer();
            _room.lockStart();
        }
    }

    public function kickOut(id:String):void {

        var client:ClientVO;

        for (var i:int; i < _clients.length; i++) {
            if (_clients[i].id == id) {
                client = _clients[i];

                sendJsonToClient(client, SocketMsgFactory.createKickOutMsg('You were kicked from the room'));

                if (_kickTimeoutInt == 0) {
                    _kickTimeoutInt = setTimeout(kickTimeout, 3000);
                }
                else {
                    clearTimeout(_kickTimeoutInt);
                    kickTimeout();
                }

                return;
            }
        }

        function kickTimeout():void {

            _kickTimeoutInt = 0;

            if (LANGameCtrl.I.isOnline) {
                OnlineRelayClient.I.close();
                return;
            }

            if (client && client.socket && client.socket.connected) {
//					view.removePlayer(id);
//					_clients.splice(i,1);
                client.socket.close();
            }
        }


    }

    public function gameStart():void {
        active = true;
        GameCtrl.I.backToSelectOnFightEnd = false;
        GameInterface.instance.updateInputConfig();
        LockFrameLogic.I.initServer();
        _renderFrame = 1;
        LANUtils.updateParams();
        _room = null;

        _selectLogic = new SelectFighterServerLogic();
        _selectLogic.init();

        _connGameLogic = new LockFrameServerLogic();

        LanGameMenuCtrl.I.init();

        initSyncEvent();
        startPing();
    }

    /**
     * Match over: keep sockets, reopen room lobby for rematch.
     */
    public function returnToRoom():void {
        if (_selectLogic) {
            _selectLogic.dispose();
            _selectLogic = null;
        }
        if (_connGameLogic) {
            _connGameLogic.dispose();
            _connGameLogic = null;
        }
        disposeSyncEvent();
        LockFrameLogic.I.dispose();

        active                             = false;
        GameCtrl.I.autoEndRoundAble        = true;
        GameCtrl.I.autoStartAble           = true;
        GameCtrl.I.backToSelectOnFightEnd  = true;
        GameCtrl.I.fightFinished           = false;
        SelectFighterStage.AUTO_FINISH     = true;
        SelectFighterStage.DRAFT_MODE      = false;
        SelectFighterStage.ONLY_INPUT_PLAYER = 0;
        LoadingStage.AUTO_START_GAME       = true;

        GameInterface.instance.updateInputConfig();
        GameInputer.enabled = true;
        GameUI.closeAlert();
        GameUI.closeConfrim();
        LanGameMenuCtrl.I.dispose();

        var room:LANRoomState = new LANRoomState();
        MainGame.stageCtrl.goStage(room);
        room.hostMode();

        for each (var cv:ClientVO in _clients) {
            if (cv) {
                room.addPlayer(cv.id || cv.name, cv.name);
            }
        }
        room.setStartAble(_clients && _clients.length > 0);
        room.pushChart('Match finished — press Start for rematch');
        startPing();
    }

    public function gameEnd():void {
        stopPing();
        active = false;
        GameCtrl.I.backToSelectOnFightEnd = true;
        GameInterface.instance.updateInputConfig();
        LockFrameLogic.I.dispose();

        if (_selectLogic) {
            _selectLogic.dispose();
            _selectLogic = null;
        }
        if (_connGameLogic) {
            _connGameLogic.dispose();
            _connGameLogic = null;
        }

        disposeSyncEvent();

        GameInputer.enabled = true;
        GameUI.closeAlert();
        GameUI.closeConfrim();

        var room:LANRoomState = new LANRoomState();
        MainGame.stageCtrl.goStage(room);
        room.hostMode();

        LanGameMenuCtrl.I.dispose();
    }

    public function gameQuit():void {
        stopPing();
        active = false;
        GameCtrl.I.backToSelectOnFightEnd = true;
        GameInterface.instance.updateInputConfig();
        LockFrameLogic.I.dispose();

        disposeSyncEvent();
        LanGameMenuCtrl.I.dispose();

        stopServer();

        MainGame.stageCtrl.goStage(new LANGameState());

    }

    public function renderGame():Boolean {
        if (MainGame.stageCtrl.currentStage is GameStage) {
            return _connGameLogic.render();
        }

        InputManager.I.socket_input_p1.freeRender();

        return true;
    }

    public function sendTCP(data:Object):void {
        if (LANGameCtrl.I.isOnline) {
            OnlineRelayClient.I.sendGameTcp(data);
            return;
        }
        for each(var i:ClientVO in _clients) {
            SocketServer.I.send(i.socket, data);
        }
    }

    public function sendUDP(data:Object):void {
        if (LANGameCtrl.I.isOnline) {
            OnlineRelayClient.I.sendGameUdp(data);
            return;
        }
        for each(var i:String in _udpClientMap) {
            _udpSocket.send(i, LANGameCtrl.PORT_UDP_CLIENT, data);
        }
    }

    private function sendJsonToClient(client:ClientVO, msg:Object):void {
        if (LANGameCtrl.I.isOnline) {
            OnlineRelayClient.I.sendGameTcpJson(msg);
            return;
        }
        if (client && client.socket) {
            SocketServer.I.sendJson(client.socket, msg);
        }
    }

    private var _onlineClosing:Boolean;

    private function onOnlinePeerLeft(reason:String):void {
        if (_onlineClosing) {
            return;
        }
        _onlineClosing = true;
        if (active) {
            gameEnd();
            GameUI.alert('PLAYER EXIT', 'Player left the room');
            return;
        }
        if (_clients.length > 0) {
            var cv:ClientVO = _clients[0];
            if (_room) {
                _room.removePlayer(cv.ip);
                _room.pushChart((cv.name || 'Player') + ' left the room');
                _room.setStartAble(false);
            }
            _clients.length = 0;
        }
    }

    private function udpDataHandler(d:UDPDataVO):void {

        if (d.getDataObject() && d.getDataObject().type == MsgType.FIND_HOST) {
            if (!active && _udpSocket) {
                _udpSocket.send(d.fromIP, d.fromPort, SocketMsgFactory.createFindHostBackMsg());
            }
            return;
        }

        if (_connGameLogic && _connGameLogic.receiveInput(d.getDataByteArray())) {
            _udpClientMap[d.fromIP + ':' + d.fromPort] = d.fromIP;
            return;
        }
    }

    private function receiveJson(msgObj:Object, clientSocket:Socket):void {
        switch (msgObj.type) {
        case MsgType.JOIN:
            receiveJoin(msgObj, clientSocket);
            break;
        case MsgType.JOIN_IN:
            if (_room) {
                _room.setStartAble(true);
                sendChart(msgObj.name + ' joined the room');
            }
            startPing();
            break;
        case MsgType.CHART:
            var cv:ClientVO = findClient(clientSocket);
            if (!cv && _clients.length > 0) {
                cv = _clients[0];
            }
            if (_room && cv) {
                _room.pushChart(msgObj.msg, cv.name);
            }
            if (cv) {
                sendClientsChart(msgObj.msg, cv.name);
            }
            break;
        }

    }

    private function receiveJoin(msgObj:Object, clientSocket:Socket):void {
        if (_clients.length > 0) {
            //超出人数限制
            if (LANGameCtrl.I.isOnline) {
                OnlineRelayClient.I.sendGameTcpJson(SocketMsgFactory.createJoinFailMsg('Room is full'));
            }
            else {
                SocketServer.I.sendJson(clientSocket, SocketMsgFactory.createJoinFailMsg('Room is full'));
            }
            return;
        }


        var cv:ClientVO = new ClientVO();
        if (LANGameCtrl.I.isOnline) {
            cv.ip     = 'online';
            cv.socket = null;
        }
        else {
            cv.ip     = clientSocket.remoteAddress;
            cv.socket = clientSocket;
        }
        cv.name = msgObj.name;

        _clients.push(cv);
        if (_room) {
            _room.addPlayer(cv.ip, cv.name);
            sendChart(cv.name + ' is joining...');
            _room.setStartAble(false);
        }

        sendJsonToClient(cv, SocketMsgFactory.createJoinSuccMsg());

        if (onPlayerJoinSuccess != null) {
            onPlayerJoinSuccess();
            onPlayerJoinSuccess = null;
        }
    }

    private function findClient(socket:Socket):ClientVO {
        if (LANGameCtrl.I.isOnline) {
            return _clients.length > 0 ? _clients[0] : null;
        }
        for each(var i:ClientVO in _clients) {
            if (i.socket == socket) {
                return i;
            }
//				if(i.socket.remoteAddress == socket.remoteAddress) return i;
        }
        return null;
    }

    private function sendClientsChart(chart:String, name:String):void {
        var msg:Object = SocketMsgFactory.createChart(chart, name);
        for each(var i:ClientVO in _clients) {
            sendJsonToClient(i, msg);
        }
    }

    private function initSyncEvent():void {

        GameEvent.addEventListener(GameEvent.ROUND_END, onGameRoundEnd);
        GameEvent.addEventListener(GameEvent.GAME_START, onGameStart);
        GameEvent.addEventListener(GameEvent.GAME_END, onGameEnd);
        GameEvent.addEventListener(GameEvent.ROUND_START, onRoundStart);
    }

    private function disposeSyncEvent():void {
        GameEvent.removeEventListener(GameEvent.ROUND_END, onGameRoundEnd);
        GameEvent.removeEventListener(GameEvent.GAME_START, onGameStart);
        GameEvent.removeEventListener(GameEvent.GAME_END, onGameEnd);
        GameEvent.removeEventListener(GameEvent.ROUND_START, onRoundStart);
    }

    private function socketHandler(e:SocketEvent):void {
        trace(e);
        switch (e.type) {
        case SocketEvent.CLIENT_CONNECT:


            break;
        case SocketEvent.CLIENT_DIS_CONNECT:

            if (active) {
                gameEnd();
                GameUI.alert('PLAYER EXIT', 'Player left the room');
            }
            for (var i:int; i < _clients.length; i++) {
                if (_clients[i].socket == e.clientSocket) {
                    if (_room) {
                        _room.removePlayer(_clients[i].ip);
                        _room.pushChart(_clients[i].name + ' left the room');
                        _room.setStartAble(false);
                    }
                    _clients.splice(i, 1);
                }
            }

            break;
        }
    }

    private function tcpDataHandler(e:SocketEvent):void {
        var obj:Object = e.getDataObject();

        if (!obj) {
            return;
        }

        if (handlePingMessage(obj)) {
            return;
        }

        if (_selectLogic && _selectLogic.receiveSelect(obj)) {
            return;
        }

        var json:Object = JsonUtils.str2json(obj);
        if (json) {
            receiveJson(json, e.clientSocket);
        }
    }

    public function startPing():void {
        LanPingHUD.I.show();
        if (_pingTimer) {
            return;
        }
        _pingTimer = new Timer(1000);
        _pingTimer.addEventListener(TimerEvent.TIMER, onPingTimer);
        _pingTimer.start();
        sendPingNow();
    }

    public function stopPing():void {
        if (_pingTimer) {
            _pingTimer.stop();
            _pingTimer.removeEventListener(TimerEvent.TIMER, onPingTimer);
            _pingTimer = null;
        }
        LanPingHUD.I.hide();
    }

    private function onPingTimer(e:TimerEvent):void {
        sendPingNow();
    }

    private function sendPingNow():void {
        if (_clients.length < 1 && !LANGameCtrl.I.isOnline) {
            return;
        }
        sendTCP(['SYNC', LanSyncType.PING, getTimer()]);
    }

    /**
     * @return true if message was a ping/pong
     */
    private function handlePingMessage(obj:Object):Boolean {
        var arr:Array = obj as Array;
        if (!arr || arr[0] != 'SYNC') {
            return false;
        }
        var type:int = int(arr[1]);
        if (type == LanSyncType.PING) {
            sendTCP(['SYNC', LanSyncType.PONG, arr[2]]);
            return true;
        }
        if (type == LanSyncType.PONG) {
            var rtt:int = getTimer() - int(arr[2]);
            LanPingHUD.I.update(rtt);
            return true;
        }
        return false;
    }

    private function onGameStart(e:GameEvent):void {
        //SYNC,type,round

        _connGameLogic.enabled = true;
        _connGameLogic.reset();

        var data:Array = ['SYNC', LanSyncType.GAME_START];
        sendTCP(data);
    }

    private function onGameEnd(e:GameEvent):void {
        if (_connGameLogic) {
            _connGameLogic.enabled = false;
            _connGameLogic.reset();
        }

        var data:Array = ['SYNC', LanSyncType.GAME_FINISH];
        sendTCP(data);

        // Both return to shared room for rematch
        returnToRoom();
    }

    private function onRoundStart(e:GameEvent):void {
        //SYNC,type,round
//			var data:Array = ['SYNC' , LanSyncType.ROUND_START , GameCtrl.I.gameRunData.round];
//			sendAll(data);
        _connGameLogic.enabled = true;
    }

    private function onGameRoundEnd(e:GameEvent):void {
        //SYNC,type,round,p1hp,p2hp
        var runData:GameRunDataVO = GameCtrl.I.gameRunData;
        var p1:FighterMain        = runData.p1FighterGroup.currentFighter;
        var p2:FighterMain        = runData.p2FighterGroup.currentFighter;
        var data:Array            = [
            'SYNC', LanSyncType.ROUND_FINISH,
            runData.round, runData.isTimerOver, runData.isDrawGame,
            p1.hp << 0, p2.hp << 0
        ];
        sendTCP(data);

        _connGameLogic.enabled = false;
        _connGameLogic.reset();
    }

}
}
