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

package net.play5d.game.bvn.win.views.lan {
import flash.display.DisplayObject;
import flash.display.Sprite;
import flash.events.MouseEvent;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.text.TextFormat;

import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.ctrler.SoundCtrl;
import net.play5d.game.bvn.ui.GameUI;
import net.play5d.game.bvn.win.ctrls.LANClientCtrl;
import net.play5d.kyo.stage.IStage;

/**
 * Online join dialog — enter room code.
 */
public class OnlineJoinDialog implements IStage {
    public function OnlineJoinDialog() {
    }

    public var onClose:Function;
    public var onJoined:Function;

    private var _ui:Sprite;
    private var _input:TextField;

    public function get display():DisplayObject {
        return _ui;
    }

    public function build():void {
        _ui = new Sprite();

        var bg:Sprite = new Sprite();
        bg.graphics.beginFill(0x000000, 0.85);
        bg.graphics.drawRect(0, 0, 800, 600);
        bg.graphics.endFill();
        _ui.addChild(bg);

        var box:Sprite = new Sprite();
        box.graphics.beginFill(0x222222, 0.95);
        box.graphics.lineStyle(2, 0xffffff, 0.6);
        box.graphics.drawRect(0, 0, 420, 200);
        box.graphics.endFill();
        box.x = (800 - 420) / 2;
        box.y = (600 - 200) / 2;
        _ui.addChild(box);

        var titleFmt:TextFormat = new TextFormat(null, 20, 0xffffff, true);
        var title:TextField     = new TextField();
        title.defaultTextFormat = titleFmt;
        title.text              = 'ONLINE JOIN / 输入房间码';
        title.width             = 400;
        title.height            = 30;
        title.x                 = 20;
        title.y                 = 20;
        title.mouseEnabled      = false;
        box.addChild(title);

        var tipFmt:TextFormat = new TextFormat(null, 14, 0xcccccc);
        var tip:TextField     = new TextField();
        tip.defaultTextFormat = tipFmt;
        tip.text              = 'Room Code (6 chars)';
        tip.width             = 380;
        tip.height            = 24;
        tip.x                 = 20;
        tip.y                 = 60;
        tip.mouseEnabled      = false;
        box.addChild(tip);

        var inputFmt:TextFormat = new TextFormat(null, 28, 0x00ff00, true);
        _input                  = new TextField();
        _input.defaultTextFormat = inputFmt;
        _input.type             = TextFieldType.INPUT;
        _input.border           = true;
        _input.borderColor      = 0xffffff;
        _input.background       = true;
        _input.backgroundColor  = 0x111111;
        _input.width            = 280;
        _input.height           = 40;
        _input.x                = 70;
        _input.y                = 90;
        _input.maxChars         = 8;
        _input.restrict         = 'A-Za-z0-9';
        box.addChild(_input);

        var okBtn:Sprite = makeBtn('OK / 加入', 0x226622, onOk);
        okBtn.x = 70;
        okBtn.y = 145;
        box.addChild(okBtn);

        var cancelBtn:Sprite = makeBtn('CANCEL', 0x662222, close);
        cancelBtn.x = 230;
        cancelBtn.y  = 145;
        box.addChild(cancelBtn);

        MainGame.I.stage.focus = _input;
    }

    public function afterBuild():void {
    }

    public function destroy(back:Function = null):void {
    }

    public function close():void {
        MainGame.stageCtrl.removeLayer(this);
        if (onClose != null) {
            onClose();
        }
    }

    private function makeBtn(label:String, color:uint, handler:Function):Sprite {
        var s:Sprite = new Sprite();
        s.graphics.beginFill(color, 1);
        s.graphics.drawRect(0, 0, 120, 32);
        s.graphics.endFill();
        s.buttonMode    = true;
        s.mouseChildren = false;

        var tf:TextField        = new TextField();
        tf.defaultTextFormat    = new TextFormat(null, 14, 0xffffff, true);
        tf.text                 = label;
        tf.width                = 120;
        tf.height               = 32;
        tf.mouseEnabled         = false;
        s.addChild(tf);

        s.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void {
            handler();
        });
        return s;
    }

    private function onOk():void {
        SoundCtrl.I.sndConfrim();
        var code:String = _input.text ? _input.text.replace(/\s+/g, '').toUpperCase() : '';
        if (code.length < 4) {
            GameUI.alert('ERROR', '请输入房间码');
            return;
        }

        GameUI.alert('CONNECTING', '正在加入房间...');
        LANClientCtrl.I.joinOnline(code, function (succ:Boolean, msg:String):void {
            if (!succ) {
                GameUI.alert('ERROR', msg || '加入失败');
                return;
            }
            if (onJoined != null) {
                onJoined();
            }
            close();
        });
    }
}
}
