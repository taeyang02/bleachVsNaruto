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

package net.play5d.game.bvn.win.data {
import flash.filesystem.File;

import net.play5d.game.bvn.win.utils.FileUtils;

/**
 * Online relay server config.
 *
 * Prefer <code>config/online.json</code> next to the app:
 * <pre>
 * {"host":"your.server.ip","port":17511}
 * </pre>
 */
public class OnlineConfig {
    /** Default relay host — change before shipping, or override via online.json */
    public static var host:String = '127.0.0.1';

    /** Default relay TCP port */
    public static var port:int = 17511;

    /** Extra lock-frame delay for online latency */
    public static var lockKeyframe:int = 6;

    private static var _loaded:Boolean;

    public static function load():void {
        if (_loaded) {
            return;
        }
        _loaded = true;

        try {
            var candidates:Array = [
                FileUtils.getAppFloderFileUrl('config/online.json'),
                FileUtils.getAppFloderFileUrl('assets/config/online.json'),
                File.applicationDirectory.resolvePath('config/online.json').nativePath,
                File.applicationDirectory.resolvePath('assets/config/online.json').nativePath
            ];
            var text:String = null;
            for each(var url:String in candidates) {
                text = FileUtils.readTextFile(url);
                if (text && text != '') {
                    break;
                }
            }
            if (text && text != '') {
                var o:Object = JSON.parse(text);
                if (o.host) {
                    host = String(o.host);
                }
                if (o.port) {
                    port = int(o.port);
                }
                if (o.lockKeyframe) {
                    lockKeyframe = int(o.lockKeyframe);
                }
            }
        }
        catch (e:Error) {
            trace('OnlineConfig.load', e);
        }
    }

    public function OnlineConfig() {
    }
}
}
