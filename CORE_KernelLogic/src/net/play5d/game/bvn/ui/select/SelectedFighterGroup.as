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

package net.play5d.game.bvn.ui.select {
import com.greensock.TweenLite;

import flash.display.Sprite;

import net.play5d.game.bvn.data.vos.FighterVO;

public class SelectedFighterGroup extends Sprite {
    include '../../../../../../../include/_INCLUDE_.as';

    public function SelectedFighterGroup(uiClass:Class) {
        _uiClass = uiClass;
    }
    private var _uiClass:Class;
    private var _uis:Array = [];
    private var _curUI:SelectedFighterUI;

    public function destory():void {
        for each (var i:SelectedFighterUI in _uis) {
            if (i) {
                i.destory();
            }
        }
        _uis    = [];
        _curUI  = null;
        while (numChildren > 0) {
            removeChildAt(0);
        }
    }

    /**
     * Push current card back and add a new front slot (null = empty preview).
     * Does NOT destroy previous confirmed cards (keeps face + name).
     * Blank templates are never kept behind — they are pruned first.
     */
    public function addFighter(vo:FighterVO):void {
        pruneEmptySlots();

        var ui:SelectedFighterUI;
        var addy:Number  = 20 - (
                           _uis.length - 1
        ) * 3;
        var ty:Number    = _uis.length * -20;
        var alpha:Number = 0.7 - (
                           _uis.length - 1
        ) * 0.3;
        var scale:Number = 0.85 - (
                           _uis.length - 1
        ) * 0.15;

        for (var i:int; i < _uis.length; i++) {
            ui = _uis[i];
            if (!ui || !ui.ui) {
                continue;
            }

            TweenLite.to(ui.ui, 0.1, {y: ty, alpha: alpha, scaleX: scale, scaleY: scale});

            ty += addy;
            alpha += 0.3;
            scale += 0.15;
        }

        if (_curUI) {
            // Keep previous confirmed card visible — only disable input
            _curUI.mouseEnabled(false);
        }

        ui = new SelectedFighterUI(new _uiClass());
        if (vo) {
            ui.setFighter(vo);
        }
        else {
            // Faint empty preview on top only — never stacked as opaque blanks behind
            ui.ui.alpha = 0.2;
        }

        ui.ui.y = 50;
        TweenLite.to(ui.ui, 0.1, {y: 0, delay: 0.05, alpha: vo ? 1 : 0.2});

        addChild(ui.ui);
        _uis.push(ui);
        _curUI = ui;
    }

    public function updateFighter(vo:FighterVO):void {
        if (!_curUI) {
            addFighter(vo);
            return;
        }
        _curUI.setFighter(vo);
        if (_curUI.ui) {
            _curUI.ui.alpha  = 1;
            _curUI.ui.scaleX = 1;
            _curUI.ui.scaleY = 1;
        }
    }

    /** Strip blank preview frames so they never stack behind named faces. */
    private function pruneEmptySlots():void {
        for (var k:int = _uis.length - 1; k >= 0; k--) {
            var oldUI:SelectedFighterUI = _uis[k];
            if (!oldUI || oldUI.getFighter()) {
                continue;
            }
            if (oldUI.ui && oldUI.ui.parent) {
                try {
                    oldUI.ui.parent.removeChild(oldUI.ui);
                }
                catch (e:Error) {
                }
            }
            oldUI.destory();
            _uis.splice(k, 1);
            if (_curUI == oldUI) {
                _curUI = _uis.length > 0 ? _uis[_uis.length - 1] : null;
            }
        }
    }

}
}
