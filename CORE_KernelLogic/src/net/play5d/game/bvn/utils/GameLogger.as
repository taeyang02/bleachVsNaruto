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

package net.play5d.game.bvn.utils {
public class GameLogger {
    include '../../../../../../include/_INCLUDE_.as';

    private static var _loger:Object;

    /**
     * 设置日志记录器（Windows 端写入文件）。
     *
     * @param v 实现 log(String) 的对象，可为 null
     */
    public static function setLoger(v:Object):void {
        _loger = v;
    }

    /**
     * 输出日志：优先写文件，同时 trace。
     *
     * @param v 日志内容
     */
    public static function log(v:String):void {
        trace(v);
        if (_loger) {
            try {
                _loger.log(v);
            }
            catch (e:Error) {
                trace('GameLogger file write failed:', e);
            }
        }
    }

    public function GameLogger() {
    }

}
}
