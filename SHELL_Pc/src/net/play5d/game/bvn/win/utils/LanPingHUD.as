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
import flash.display.Stage;
import flash.text.TextField;
import flash.text.TextFieldAutoSize;
import flash.text.TextFormat;

import net.play5d.game.bvn.GameConfig;
import net.play5d.game.bvn.MainGame;

/**
 * Corner ping / latency HUD for online & LAN (both host and guest).
 */
public class LanPingHUD {

    private static var _i:LanPingHUD;

    public static function get I():LanPingHUD {
        _i ||= new LanPingHUD();
        return _i;
    }

    public function LanPingHUD() {
    }

    private var _tf:TextField;
    private var _samples:Array = [];

    public function show():void {
        var stage:Stage = MainGame.I ? MainGame.I.stage : null;
        if (!stage) {
            return;
        }
        if (!_tf) {
            _tf                        = new TextField();
            _tf.mouseEnabled           = false;
            _tf.selectable             = false;
            _tf.autoSize               = TextFieldAutoSize.RIGHT;
            var fmt:TextFormat         = new TextFormat('Arial', 14, 0x00FF00, true);
            _tf.defaultTextFormat      = fmt;
            _tf.text                   = 'Ping -- ms';
            _tf.filters                = [];
        }
        if (!_tf.parent) {
            stage.addChild(_tf);
        }
        layout();
    }

    public function hide():void {
        _samples = [];
        if (_tf && _tf.parent) {
            try {
                _tf.parent.removeChild(_tf);
            }
            catch (e:Error) {
            }
        }
    }

    /**
     * Update with a raw RTT sample (ms). Averages last few samples.
     */
    public function update(rttMs:int):void {
        if (rttMs < 0) {
            rttMs = 0;
        }
        if (rttMs > 9999) {
            rttMs = 9999;
        }
        _samples.push(rttMs);
        if (_samples.length > 5) {
            _samples.shift();
        }
        var sum:int = 0;
        for each (var v:int in _samples) {
            sum += v;
        }
        var avg:int = sum / _samples.length;
        applyDisplay(avg);
    }

    private function applyDisplay(ms:int):void {
        show();
        if (!_tf) {
            return;
        }
        var color:uint = 0x00FF00;
        if (ms >= 150) {
            color = 0xFFFF00;
        }
        if (ms >= 300) {
            color = 0xFF6600;
        }
        if (ms >= 500) {
            color = 0xFF0000;
        }
        _tf.textColor = color;
        _tf.text      = 'Ping ' + ms + ' ms';
        layout();
    }

    private function layout():void {
        if (!_tf || !_tf.parent) {
            return;
        }
        var w:Number = GameConfig.GAME_SIZE ? GameConfig.GAME_SIZE.x : 800;
        _tf.x        = w - _tf.width - 12;
        _tf.y        = 8;
        // Keep on top
        try {
            _tf.parent.setChildIndex(_tf, _tf.parent.numChildren - 1);
        }
        catch (e:Error) {
        }
    }

}
}
