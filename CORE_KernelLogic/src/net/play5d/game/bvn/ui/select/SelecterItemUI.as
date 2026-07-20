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
import flash.display.MovieClip;

import net.play5d.game.bvn.data.AssisterModel;
import net.play5d.game.bvn.data.FighterModel;
import net.play5d.game.bvn.data.vos.FighterVO;
import net.play5d.game.bvn.data.vos.SelectVO;
import net.play5d.game.bvn.utils.MCUtils;
import net.play5d.game.bvn.utils.ResUtils;

public class SelecterItemUI {
    include '../../../../../../../include/_INCLUDE_.as';

    public function SelecterItemUI(playerType:int = 1) {
        _playerType     = playerType;
        ui              = ResUtils.I.createDisplayObject(ResUtils.swfLib.select, '$select$MC_selectItemMc');
        ui.mouseEnabled = ui.mouseChildren = false;
        var frame:int   = playerType == 1 ? 1 : 2;
        // Prefer child mc (new assets); only stop if the frame exists
        if (ui.mc && ui.mc.totalFrames >= frame) {
            ui.mc.gotoAndStop(frame);
        }
        else if (ui.totalFrames >= frame) {
            ui.gotoAndStop(frame);
        }
        // Freeze cursor SWF — legacy assets loop a painful blink/pulse
        freezeCursor();
    }
    public var ui:$select$MC_selectItemMc;
    public var currentFighter:FighterVO;
    public var selectTimes:int;
    public var selectTimesCount:int = 1;
    public var inputType:String;
    public var group:SelectedFighterGroup;
    public var selectVO:SelectVO;
    public var isSelectAssist:Boolean;
    public var x:int;
    public var y:int;
    public var moreX:int            = 0;
    public var moreY:int            = 0;
    public var showingMoreSelecter:SelectFighterItem;

    public var enabled:Boolean = true;

    public var randoms:Vector.<FighterVO> = null;
    public var randFrame:int;

    public var touchHoverItem:SelectFighterItem;
    private var _moreEnable:Boolean = false;
    private var _playerType:int;

    /**
     * 是否选择完成
     */
    public function selectFinish():Boolean {
        return selectTimes >= selectTimesCount;
    }

    public function getCurrentSelectes():Array {
        if (isSelectAssist) {
            return [selectVO.fuzhu];
        }
        else {
            return [selectVO.fighter1, selectVO.fighter2, selectVO.fighter3];
        }
    }

    public function setCurrentSelect(v:Array):void {
        if (isSelectAssist) {
            selectVO.fuzhu = v[0];

            group.updateFighter(AssisterModel.I.getAssister(selectVO.fuzhu));

        }
        else {
            selectVO.fighter1 = v[0];
            selectVO.fighter2 = v[1];
            selectVO.fighter3 = v[2];

            group.updateFighter(FighterModel.I.getFighter(selectVO.fighter1));
            group.addFighter(FighterModel.I.getFighter(selectVO.fighter2));
            group.addFighter(FighterModel.I.getFighter(selectVO.fighter3));

        }

        selectTimes = selectTimesCount;

        enabled = false;

    }

    /**
     * Apply draft picks from peer (partial or complete). Mirrors local select() visuals.
     */
    public function applyNetworkPicks(v:Array):void {
        if (!v || !selectVO) {
            return;
        }
        if (isSelectAssist) {
            if (v[0] && selectTimes < 1) {
                selectVO.fuzhu = v[0];
                group.updateFighter(AssisterModel.I.getAssister(v[0]));
                selectTimes = 1;
            }
            enabled = !selectFinish();
            return;
        }

        var count:int = 0;
        if (v[0]) {
            count++;
        }
        if (v.length > 1 && v[1]) {
            count++;
        }
        if (v.length > 2 && v[2]) {
            count++;
        }

        while (selectTimes < count) {
            var id:String     = v[selectTimes];
            var fv:FighterVO  = FighterModel.I.getFighter(id);
            switch (selectTimes) {
            case 0:
                selectVO.fighter1 = id;
                break;
            case 1:
                selectVO.fighter2 = id;
                break;
            case 2:
                selectVO.fighter3 = id;
                break;
            }
            selectTimes++;
            if (!selectFinish()) {
                group.addFighter(fv);
            }
            else {
                group.updateFighter(fv);
            }
        }
        enabled = !selectFinish();
    }

    public function moreEnabled():Boolean {
        return _moreEnable;
    }

    public function setMoreEnabled(enab:Boolean, curSelecter:SelectFighterItem = null):void {
        _moreEnable = enab;

        if (enab) {
            this.moreX = 0;
            this.moreY = 0;
            if (!curSelecter) {
                throw Error('Need SelectFighterItem !!');
            }
            this.showingMoreSelecter = curSelecter;
            if (this.showingMoreSelecter) {
                this.showingMoreSelecter.setMoreNumberVisible(false);
            }
        }
        else {
            if (this.showingMoreSelecter) {
                this.showingMoreSelecter.setMoreNumberVisible(true);
            }
            this.showingMoreSelecter = null;
        }

    }

    /**
     * 是否已经选过该角色
     */
    public function isSelected(id:String):Boolean {
        if (!selectVO) {
            return false;
        }
        if (isSelectAssist) {
            return selectVO.fuzhu == id;
        }
        return selectVO.fighter1 == id || selectVO.fighter2 == id || selectVO.fighter3 == id;
    }

    public function select(back:Function = null):void {

        if (!selectVO) {
            throw new Error('未设置selectVO!');
            return;
        }

//			trace('P'+_playerType+"::",currentFighter.id);

//			if(randoms) currentFighter = KyoRandom.getRandomInArray(randoms, false);

        if (isSelectAssist) {
            selectVO.fuzhu = currentFighter.id;
        }
        else {
            switch (selectTimes) {
            case 0:
                selectVO.fighter1 = currentFighter.id;
                break;
            case 1:
                selectVO.fighter2 = currentFighter.id;
                break;
            case 2:
                selectVO.fighter3 = currentFighter.id;
                break;
            }
        }

        selectTimes++;

        if (!selectFinish()) {
            group.addFighter(currentFighter);
        }

        enabled = false;

        // No confirm flash/blink — finish immediately (legacy SWF select anim is harsh)
        freezeCursor();
        finishSelectAnim(this, back);

        updateRandom();

    }

    private function freezeCursor():void {
        if (!ui) {
            return;
        }
        ui.stop();
        MCUtils.stopAllMovieClips(ui);
        if (ui.mc is MovieClip) {
            var child:MovieClip = ui.mc as MovieClip;
            child.stop();
            MCUtils.stopAllMovieClips(child);
        }
    }

    private function finishSelectAnim(_this:*, back:Function):void {
        if (!selectFinish()) {
            enabled = true;
        }
        if (back != null) {
            back(_this);
        }
    }

    public function moveTo(x:Number, y:Number):void {
        ui.x = x;
        ui.y = y;
    }

    public function destory():void {
        enabled = false;
        removeSelecter();
        removeGroup();
    }

    public function removeSelecter():void {
        if (ui && ui.parent) {
            try {
                ui.parent.removeChild(ui);
            }
            catch (e:Error) {
            }
            ui = null;
        }
    }

    public function removeGroup():void {
        if (group && group.parent) {
            try {
                group.parent.removeChild(group);
            }
            catch (e:Error) {
            }
            group = null;
        }
    }

    private function updateRandom():void {
        if (!randoms) {
            return;
        }
        if (!selectVO) {
            return;
        }

        selectVO.fighter1 && removeRand(selectVO.fighter1);
        selectVO.fighter2 && removeRand(selectVO.fighter2);
        selectVO.fighter3 && removeRand(selectVO.fighter3);
    }

    private function removeRand(id:String):void {
        var index:int = -1;
        for (var i:int; i < randoms.length; i++) {
            if (randoms[i].id == id) {
                index = i;
                break;
            }
        }

        if (index != -1) {
            randoms.splice(index, 1);
        }

    }

}
}
