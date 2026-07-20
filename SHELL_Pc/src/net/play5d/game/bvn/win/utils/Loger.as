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
 * Windows file logger.
 * Prefers <code>log.log</code> next to the .exe (applicationDirectory);
 * falls back to applicationStorageDirectory if that path is not writable.
 */
public class Loger implements ILogger {
    private static var _file:File;
    private static var _resolved:Boolean;

    public function Loger() {
    }

    /**
     * Append one line to log.log.
     *
     * @param v log text
     */
    public function log(v:String):void {
        trace(v);

        try {
            ensureFile();
            if (!_file) {
                return;
            }
            var stream:FileStream = new FileStream();
            stream.open(_file, FileMode.APPEND);
            stream.writeUTFBytes(v + '\r\n');
            stream.close();
        }
        catch (e:Error) {
            trace('Loger.write failed', e);
            // Retry once with storage fallback
            try {
                _file     = File.applicationStorageDirectory.resolvePath('log.log');
                _resolved = true;
                var fs:FileStream = new FileStream();
                fs.open(_file, FileMode.APPEND);
                fs.writeUTFBytes(v + '\r\n');
                fs.close();
            }
            catch (e2:Error) {
                trace('Loger.fallback failed', e2);
            }
        }
    }

    private function ensureFile():void {
        if (_resolved) {
            return;
        }
        _resolved = true;
        // Same folder as the captive .exe
        try {
            var besideExe:File = File.applicationDirectory.resolvePath('log.log');
            var test:FileStream = new FileStream();
            test.open(besideExe, FileMode.APPEND);
            test.writeUTFBytes('');
            test.close();
            _file = besideExe;
            return;
        }
        catch (e:Error) {
            trace('Loger: applicationDirectory not writable, using storage');
        }
        _file = File.applicationStorageDirectory.resolvePath('log.log');
    }

}
}
