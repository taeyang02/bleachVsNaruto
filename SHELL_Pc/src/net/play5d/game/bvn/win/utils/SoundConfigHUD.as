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

package net.play5d.game.bvn.win.utils {
import flash.display.Sprite;
import flash.display.Stage;
import flash.events.MouseEvent;
import flash.events.TimerEvent;
import flash.text.TextField;
import flash.text.TextFieldAutoSize;
import flash.text.TextFormat;
import flash.utils.Timer;

import net.play5d.game.bvn.GameConfig;
import net.play5d.game.bvn.MainGame;
import net.play5d.game.bvn.data.GameData;
import net.play5d.game.bvn.stage.GameStage;
import net.play5d.game.bvn.stage.LoadingStage;

/**
 * Top-right sound config HUD.
 *
 * <p>Small speaker button pinned to the top-right corner. Clicking it toggles
 * a mini panel with BGM / SFX volume rows (step 10%). Values persist to the
 * game save via ConfigVO. The whole HUD hides automatically while the player
 * is inside a match (GameStage / LoadingStage) and shows again after.</p>
 */
public class SoundConfigHUD {

    private static const STEP:Number = 0.1;

    private static var _i:SoundConfigHUD;

    public static function get I():SoundConfigHUD {
        _i ||= new SoundConfigHUD();
        return _i;
    }

    public function SoundConfigHUD() {
    }

    private var _stage:Stage;
    private var _btn:Sprite;
    private var _panel:Sprite;
    private var _bgmValueTf:TextField;
    private var _sndValueTf:TextField;
    private var _watchTimer:Timer;

    public function init(stage:Stage):void {
        if (_stage) {
            return;
        }
        _stage = stage;

        buildButton();
        buildPanel();

        // Poll current stage: hide while in a match, show otherwise
        _watchTimer = new Timer(500);
        _watchTimer.addEventListener(TimerEvent.TIMER, onWatchTimer);
        _watchTimer.start();

        layout();
    }

    private function buildButton():void {
        _btn            = new Sprite();
        _btn.buttonMode = true;

        _btn.graphics.beginFill(0x000000, 0.55);
        _btn.graphics.lineStyle(1, 0xFFFFFF, 0.6);
        _btn.graphics.drawRoundRect(0, 0, 30, 22, 8, 8);
        _btn.graphics.endFill();

        var tf:TextField    = makeText(14, 0xFFFFFF);
        tf.text             = '♪';
        tf.x                = 9;
        tf.y                = 1;
        _btn.addChild(tf);

        _btn.addEventListener(MouseEvent.CLICK, onBtnClick);
        _stage.addChild(_btn);
    }

    private function buildPanel():void {
        _panel         = new Sprite();
        _panel.visible = false;

        _panel.graphics.beginFill(0x000000, 0.75);
        _panel.graphics.lineStyle(1, 0xFFFFFF, 0.5);
        _panel.graphics.drawRoundRect(0, 0, 170, 74, 8, 8);
        _panel.graphics.endFill();

        _bgmValueTf = buildRow(8, 'BGM', function ():Number {
            return GameData.I.config.bgmVolume;
        }, 'bgmVolume');

        _sndValueTf = buildRow(42, 'SFX', function ():Number {
            return GameData.I.config.soundVolume;
        }, 'soundVolume');

        _stage.addChild(_panel);
    }

    /**
     * One volume row: label, minus, percent, plus.
     * @return the percent TextField (for refresh)
     */
    private function buildRow(y:Number, label:String, getter:Function, configKey:String):TextField {
        var labelTf:TextField = makeText(13, 0xFFFFFF);
        labelTf.text          = label;
        labelTf.x             = 10;
        labelTf.y             = y + 3;
        _panel.addChild(labelTf);

        var minus:Sprite = makeSmallBtn('-');
        minus.x          = 55;
        minus.y          = y;
        _panel.addChild(minus);

        var valueTf:TextField = makeText(13, 0xFFFF66);
        valueTf.x             = 88;
        valueTf.y             = y + 3;
        _panel.addChild(valueTf);

        var plus:Sprite = makeSmallBtn('+');
        plus.x          = 132;
        plus.y          = y;
        _panel.addChild(plus);

        minus.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void {
            changeVolume(configKey, -STEP);
        });
        plus.addEventListener(MouseEvent.CLICK, function (e:MouseEvent):void {
            changeVolume(configKey, STEP);
        });

        valueTf.text = formatPercent(getter());
        return valueTf;
    }

    private function makeSmallBtn(label:String):Sprite {
        var s:Sprite = new Sprite();
        s.buttonMode = true;

        s.graphics.beginFill(0x333333, 1);
        s.graphics.lineStyle(1, 0xFFFFFF, 0.6);
        s.graphics.drawRoundRect(0, 0, 24, 24, 6, 6);
        s.graphics.endFill();

        var tf:TextField = makeText(15, 0xFFFFFF);
        tf.text          = label;
        tf.x             = label == '+' ? 6 : 8;
        tf.y             = 1;
        s.addChild(tf);
        return s;
    }

    private function makeText(size:int, color:uint):TextField {
        var tf:TextField      = new TextField();
        tf.mouseEnabled       = false;
        tf.selectable         = false;
        tf.autoSize           = TextFieldAutoSize.LEFT;
        tf.defaultTextFormat  = new TextFormat('Arial', size, color, true);
        return tf;
    }

    private function changeVolume(configKey:String, delta:Number):void {
        var v:Number = Number(GameData.I.config.getValueByKey(configKey)) + delta;
        if (v < 0) {
            v = 0;
        }
        if (v > 1) {
            v = 1;
        }
        // Round to one decimal to avoid float drift
        v = Math.round(v * 10) / 10;

        // Applies to SoundCtrl internally (ConfigVO.setValueByKey)
        GameData.I.config.setValueByKey(configKey, v);
        GameData.I.saveData();

        refreshValues();
    }

    private function refreshValues():void {
        if (_bgmValueTf) {
            _bgmValueTf.text = formatPercent(GameData.I.config.bgmVolume);
        }
        if (_sndValueTf) {
            _sndValueTf.text = formatPercent(GameData.I.config.soundVolume);
        }
    }

    private function formatPercent(v:Number):String {
        return int(Math.round(v * 100)) + '%';
    }

    private function onBtnClick(e:MouseEvent):void {
        _panel.visible = !_panel.visible;
        if (_panel.visible) {
            refreshValues();
        }
        layout();
    }

    private function onWatchTimer(e:TimerEvent):void {
        var inGame:Boolean = false;
        // Joined a match: hide the button (and panel) entirely
        if (MainGame.stageCtrl) {
            var cur:Object = MainGame.stageCtrl.currentStage;
            inGame         = (cur is GameStage) || (cur is LoadingStage);
        }

        if (_btn) {
            _btn.visible = !inGame;
        }
        if (inGame && _panel && _panel.visible) {
            _panel.visible = false;
        }
        if (!inGame) {
            layout();
        }
    }

    private function layout():void {
        var w:Number = GameConfig.GAME_SIZE ? GameConfig.GAME_SIZE.x : 800;

        if (_btn) {
            _btn.x = w - _btn.width - 12;
            _btn.y = 34;
            bringToTop(_btn);
        }
        if (_panel) {
            _panel.x = w - _panel.width - 12;
            _panel.y = 60;
            bringToTop(_panel);
        }
    }

    private function bringToTop(s:Sprite):void {
        if (!s.parent) {
            return;
        }
        try {
            s.parent.setChildIndex(s, s.parent.numChildren - 1);
        }
        catch (e:Error) {
        }
    }

}
}
