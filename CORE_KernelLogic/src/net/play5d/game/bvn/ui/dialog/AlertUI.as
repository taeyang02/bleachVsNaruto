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

package net.play5d.game.bvn.ui.dialog {
import flash.events.MouseEvent;

public class AlertUI extends MusouConfrimUI {
    include '../../../../../../../include/_INCLUDE_OVERRIDE_.as';

    public function AlertUI() {
        super();
        build();
    }

    protected override function build():void {
        super.build();

        if (_noBtn) {
            _noBtn.visible = false;
        }
        if (_yesBtn) {
            _yesBtn.x = 253;
        }
        else if (_dialogUI) {
            // Legacy dialog SWF may miss yes button — click dialog to close
            _dialogUI.buttonMode = true;
            _dialogUI.addEventListener(MouseEvent.CLICK, onDialogClickClose);
        }
    }

    private function onDialogClickClose(e:MouseEvent):void {
        if (yesBack != null) {
            yesBack();
        }
        else {
            closeSelf();
        }
    }

}
}
