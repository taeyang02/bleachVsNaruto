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
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

import net.play5d.game.bvn.interfaces.ILogger;

/**
 * Windows 文件日志。写入 applicationStorageDirectory（可写），
 * 避免 AIR captive 下 applicationDirectory 只读导致静默失败。
 */
public class Loger implements ILogger {
    private static var _file:File;

    public function Loger() {
    }

    /**
     * 追加一行到 log.log。
     *
     * @param v 日志内容
     */
    public function log(v:String):void {
        trace(v);

        try {
            if (!_file) {
                _file = File.applicationStorageDirectory.resolvePath('log.log');
            }
            var stream:FileStream = new FileStream();
            stream.open(_file, FileMode.APPEND);
            stream.writeUTFBytes(v + '\r\n');
            stream.close();
        }
        catch (e:Error) {
            trace('Loger.write failed', e);
        }
    }

}
}
